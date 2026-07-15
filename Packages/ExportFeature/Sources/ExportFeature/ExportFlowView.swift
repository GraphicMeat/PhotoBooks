import AppSupport
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SwiftUI
import UniformTypeIdentifiers

/// The export sheet: preflight list → destination → progress → done/failed,
/// driven entirely by `ExportModel.phase`.
public struct ExportFlowView: View {
    let model: ExportModel
    let editor: BookEditorModel

    @State private var showFolderPicker = false

    public init(model: ExportModel, editor: BookEditorModel) {
        self.model = model
        self.editor = editor
    }

    private var fileExporterBinding: Binding<Bool> {
        Binding(get: { model.renderedDocument != nil },
                set: { if !$0 { model.finishSingleFile(at: nil) } })
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                EmptyView()
            case .preflight:
                preflightStep
            case .choosingDestination:
                destinationStep
            case .exporting(let value):
                progressStep(value)
            case .failed(let message, let retryIDs):
                failureStep(message: message, retryIDs: retryIDs)
            case .finished(let urls):
                finishedStep(urls)
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
        .padding()
        .fileImporter(isPresented: $showFolderPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result {
                model.exportBlurbPair(into: folder)
            }
        }
        .fileExporter(isPresented: fileExporterBinding,
                      document: model.renderedDocument,
                      contentType: .pdf,
                      defaultFilename: model.defaultSingleFilename) { result in
            model.finishSingleFile(at: try? result.get())
        }
    }

    // MARK: 1 — preflight

    private var preflightStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preflight — \(model.target.menuTitle.replacingOccurrences(of: "…", with: ""))", bundle: .module)
                .font(.headline)
            if model.issues.isEmpty {
                Label(String(localized: "No issues found. Ready to export.", bundle: .module), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                    preflightRow(issue)
                }
                .listStyle(.plain)
                .accessibilityIdentifier("preflight-list")
            }
            HStack {
                Button(String(localized: "Cancel", bundle: .module)) { model.dismissFlow() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Continue", bundle: .module)) { model.continueFromPreflight() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.summary.hasBlockingIssues)
                    .help(Text("Proceed to choose where to export", bundle: .module))
                    .accessibilityIdentifier("preflight-continue")
            }
        }
    }

    @ViewBuilder
    private func preflightRow(_ issue: PreflightIssue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: PreflightSummary.systemImage(for: issue))
                .foregroundStyle(issue.isBlocking ? .red : .yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(PreflightSummary.message(for: issue))
                    .fixedSize(horizontal: false, vertical: true)
                if case .pageCountOutOfRange(let actual, let min, _) = issue.kind, actual < min {
                    Button(String(localized: "Add \(min - actual) blank pages", bundle: .module)) {
                        editor.padToMinimumPages()
                        model.begin(model.target)        // re-run preflight on the padded book
                    }
                    .font(.caption)
                    .help(Text("Append blank pages to meet the minimum page count", bundle: .module))
                }
            }
            Spacer()
            if let pageIndex = issue.pageIndex, model.book.pages.indices.contains(pageIndex) {
                Button(String(localized: "Page \(pageIndex)", bundle: .module)) {
                    editor.selectPage(model.book.pages[pageIndex].id)
                    model.dismissFlow()              // jump: close the sheet, select in browser
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help(Text("Jump to this page in the editor", bundle: .module))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 2 — destination

    private var destinationStep: some View {
        VStack(spacing: 16) {
            Text(model.target.menuTitle.replacingOccurrences(of: "…", with: ""))
                .font(.headline)
            switch model.target {
            case .blurb:
                Text("Blurb needs two files. Pick a folder; PhotoBooks writes \u{201C}\(ExportFilenames.interior(title: model.book.title))\u{201D} and \u{201C}\(ExportFilenames.cover(title: model.book.title))\u{201D} into it.", bundle: .module)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Choose Folder…", bundle: .module)) { showFolderPicker = true }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Pick the folder PhotoBooks writes the two Blurb files into", bundle: .module))
                    .accessibilityIdentifier("export-choose-folder")
            case .genericPrint, .digital:
                Text(model.target == .digital
                     ? String(localized: "A screen-resolution PDF for sharing and on-device viewing.", bundle: .module)
                     : String(localized: "A print-ready PDF with bleed for generic print services.", bundle: .module))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Export…", bundle: .module)) { model.exportSingleFileToTemporary() }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Render the book and save the PDF", bundle: .module))
                    .accessibilityIdentifier("export-single-file")
            }
            Button(String(localized: "Cancel", bundle: .module)) { model.dismissFlow() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 3 — progress

    private func progressStep(_ value: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: value) {
                Text(value < 0.5 ? String(localized: "Fetching photos…", bundle: .module) : String(localized: "Rendering pages…", bundle: .module))
            }
            .progressViewStyle(.linear)
            .accessibilityIdentifier("export-progress")
            Button(String(localized: "Cancel", bundle: .module)) { model.cancelExport() }
                .help(Text("Stop the export in progress", bundle: .module))
                .accessibilityIdentifier("export-cancel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: 4 — failure / success

    private func failureStep(message: String, retryIDs: [PhotoID]) -> some View {
        VStack(spacing: 16) {
            Label(String(localized: "Export failed", bundle: .module), systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Close", bundle: .module)) { model.dismissFlow() }
                Button(retryIDs.isEmpty ? String(localized: "Try Again", bundle: .module) : String(localized: "Retry Failed Photos", bundle: .module)) { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .help(retryIDs.isEmpty ? Text("Run the export again", bundle: .module)
                                           : Text("Re-render only the photos that failed", bundle: .module))
                    .accessibilityIdentifier("export-retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finishedStep(_ urls: [URL]) -> some View {
        VStack(spacing: 16) {
            Label(String(localized: "Export complete", bundle: .module), systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            ForEach(urls, id: \.absoluteString) { url in
                Text(url.lastPathComponent)
                    .font(.callout.monospaced())
            }
            HStack {
                Button(String(localized: "Done", bundle: .module)) { model.dismissFlow() }
                    .keyboardShortcut(.defaultAction)
                #if os(macOS)
                Button(String(localized: "Reveal in Finder", bundle: .module)) {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                .help(Text("Show the exported files in Finder", bundle: .module))
                .accessibilityIdentifier("export-reveal")
                #else
                if !urls.isEmpty {
                    ShareLink(items: urls) {
                        Label(String(localized: "Share", bundle: .module), systemImage: "square.and.arrow.up")
                    }
                }
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - macOS File menu

/// The focused-window export model, published by the browser via
/// `.focusedSceneValue(\.exportModel, …)` so the File menu drives the
/// frontmost document's flow.
extension FocusedValues {
    @Entry public var exportModel: ExportModel?
}

public struct ExportCommands: Commands {
    @FocusedValue(\.exportModel) private var exportModel

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            ForEach(ExportModel.ExportTarget.allCases, id: \.self) { target in
                Button(String(localized: "Export \(target.menuTitle)", bundle: .module)) {
                    exportModel?.begin(target)
                }
                .disabled(exportModel == nil)
            }
        }
    }
}
