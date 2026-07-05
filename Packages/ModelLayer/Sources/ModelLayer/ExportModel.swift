import AppSupport
import Foundation
import Observation
import PhotoBookCore
import PhotoBookRender

/// Combined progress for the Blurb two-file flow (D11), weighted by sheet
/// count: the interior's S sheets span [0, S/(S+1)); the cover finishes
/// the bar.
struct BlurbProgress: Sendable {
    let interiorSheets: Double
    var totalSheets: Double { interiorSheets + 1 }
    func duringInterior(_ value: Double) -> Double { value * interiorSheets / totalSheets }
    func duringCover(_ value: Double) -> Double { (interiorSheets + value) / totalSheets }
}

/// Sequences one export flow (D11): preflight list → destination → progress
/// → finished/failed. One instance per document window (it lives on
/// `BookSession` like the editor model); `begin(_:)` resets it for a fresh
/// run. All UI state is main-actor; the render itself runs in `exportTask`
/// and reports back through the @Sendable progress callback.
@Observable @MainActor
public final class ExportModel {

    /// The user-facing export choices: the contract's `PDFTarget`s grouped
    /// the way the menu offers them (Blurb = the interior + cover pair).
    public enum ExportTarget: String, CaseIterable {
        case blurb
        case genericPrint
        case digital

        public var menuTitle: String {
            switch self {
            case .blurb: "Blurb Book…"
            case .genericPrint: "Print PDF…"
            case .digital: "Digital PDF…"
            }
        }

        /// The single-file targets' PDF flavor (Blurb resolves to two
        /// exports inside `exportBlurbPair`).
        var singleFileTarget: PDFTarget? {
            switch self {
            case .blurb: nil
            case .genericPrint: .genericPrint(includeBleed: true)
            case .digital: .digital
            }
        }
    }

    public enum Phase: Equatable {
        case idle
        case preflight
        case choosingDestination
        case exporting(Double)
        case failed(message: String, retryIDs: [PhotoID])
        case finished([URL])
    }

    /// What to re-run on Retry (D2: the second run is cheap because
    /// downloads persist below the store).
    private enum Destination {
        case blurbFolder(URL)
        case temporaryFile
    }

    @ObservationIgnored private let document: BookDocument
    @ObservationIgnored private let imageStore: any ImageStore
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var lastDestination: Destination?

    public private(set) var phase: Phase = .idle
    public private(set) var target: ExportTarget = .digital
    public private(set) var issues: [PreflightIssue] = []

    /// Set by the single-file path once rendering succeeds; the flow view
    /// hands it to `.fileExporter`.
    public var renderedDocument: PDFExportDocument?

    public init(document: BookDocument, imageStore: any ImageStore) {
        self.document = document
        self.imageStore = imageStore
    }

    var preset: PrintPreset {
        PresetLibrary.preset(id: document.book.presetID) ?? PresetLibrary.all()[0]
    }

    public var summary: PreflightSummary { PreflightSummary(issues: issues) }

    public var book: Book { document.book }

    public var isFlowPresented: Bool { phase != .idle }

    public var defaultSingleFilename: String {
        ExportFilenames.sanitized(title: document.book.title)
            + (target == .genericPrint ? "-print" : "")
    }

    // MARK: Flow steps

    /// Entry point from the export menu: runs preflight and opens the sheet.
    public func begin(_ target: ExportTarget) {
        exportTask?.cancel()
        self.target = target
        renderedDocument = nil
        lastDestination = nil
        issues = Preflight.check(document.book, preset: preset)
        phase = .preflight
    }

    /// Preflight → destination. Blocked while blocking issues exist (the
    /// button is also disabled — this is the model-side guarantee).
    public func continueFromPreflight() {
        guard !summary.hasBlockingIssues else { return }
        phase = .choosingDestination
    }

    public func dismissFlow() {
        exportTask?.cancel()
        exportTask = nil
        phase = .idle
    }

    public func cancelExport() {
        exportTask?.cancel()
    }

    public func retry() {
        switch lastDestination {
        case .blurbFolder(let url): exportBlurbPair(into: url)
        case .temporaryFile: exportSingleFileToTemporary()
        case nil: phase = .choosingDestination
        }
    }

    // MARK: Blurb pair (folder destination — D11)

    /// Writes `<Title>-interior.pdf` + `<Title>-cover.pdf` straight into the
    /// picked folder, with one combined progress bar (`BlurbProgress`).
    public func exportBlurbPair(into folder: URL) {
        lastDestination = .blurbFolder(folder)
        let book = document.book
        let preset = preset
        let store = imageStore
        let interiorURL = folder.appendingPathComponent(ExportFilenames.interior(title: book.title))
        let coverURL = folder.appendingPathComponent(ExportFilenames.cover(title: book.title))
        let combined = BlurbProgress(
            interiorSheets: Double(book.pages.count(where: { $0.role == .standard })))
        phase = .exporting(0)
        exportTask = Task {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                try await PDFExporter().export(book, preset: preset, target: .blurbInterior,
                                               imageStore: store, to: interiorURL) { value in
                    Task { @MainActor [weak self] in
                        self?.noteProgress(combined.duringInterior(value))
                    }
                }
                try await PDFExporter().export(book, preset: preset, target: .blurbCover,
                                               imageStore: store, to: coverURL) { value in
                    Task { @MainActor [weak self] in
                        self?.noteProgress(combined.duringCover(value))
                    }
                }
                phase = .finished([interiorURL, coverURL])
            } catch {
                handle(error)
            }
        }
    }

    // MARK: Single file (temp render, then .fileExporter places it — D11)

    public func exportSingleFileToTemporary() {
        guard let pdfTarget = target.singleFileTarget else { return }
        lastDestination = .temporaryFile
        let book = document.book
        let preset = preset
        let store = imageStore
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBooks-export-\(UUID().uuidString).pdf")
        phase = .exporting(0)
        exportTask = Task {
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            do {
                try await PDFExporter().export(book, preset: preset, target: pdfTarget,
                                               imageStore: store, to: temporaryURL) { value in
                    Task { @MainActor [weak self] in self?.noteProgress(value) }
                }
                renderedDocument = PDFExportDocument(data: try Data(contentsOf: temporaryURL))
                // The flow view presents .fileExporter when renderedDocument
                // is set; `finishSingleFile(at:)` runs on save completion.
            } catch {
                handle(error)
            }
        }
    }

    public func finishSingleFile(at url: URL?) {
        renderedDocument = nil
        if let url {
            phase = .finished([url])
        } else {
            phase = .choosingDestination      // save panel cancelled
        }
    }

    // MARK: Internals

    private func noteProgress(_ value: Double) {
        if case .exporting = phase { phase = .exporting(value) }
    }

    private func handle(_ error: Error) {
        switch error {
        case PDFExportError.cancelled:
            phase = .choosingDestination
        case PDFExportError.imageFetchFailed(let ids):
            phase = .failed(message: failedFetchMessage(for: ids), retryIDs: ids)
        case PDFExportError.preflightBlocked(let blocked):
            issues = blocked
            phase = .preflight
        default:
            phase = .failed(message: error.localizedDescription, retryIDs: [])
        }
    }

    /// "Couldn't load 2 photos: IMG_0012, IMG_0288" — IDs double as display
    /// names (PhotoKit local identifiers / file names from import).
    private func failedFetchMessage(for ids: [PhotoID]) -> String {
        let names = ids.map(\.rawValue).joined(separator: ", ")
        let count = ids.count == 1 ? "1 photo" : "\(ids.count) photos"
        return "Couldn't load \(count): \(names). Check iCloud connectivity and retry — finished downloads are kept."
    }
}
