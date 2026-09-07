import AppSupport
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SwiftUI
import UniformTypeIdentifiers

/// The export overlay: preflight list → destination → progress → done/failed,
/// driven entirely by `ExportModel.phase`.
public struct ExportFlowView: View {
    let model: ExportModel
    let editor: BookEditorModel

    @State private var showFolderPicker = false
    // Owned here, not by ThankYouView, so the loaded products and any
    // in-flight purchase survive re-renders of the finished step.
    @State private var tipJar = TipJar()

    public init(model: ExportModel, editor: BookEditorModel) {
        self.model = model
        self.editor = editor
    }

    private var fileExporterBinding: Binding<Bool> {
        Binding(get: { model.renderedDocument != nil },
                set: { if !$0 { model.finishSingleFile(at: nil) } })
    }

    private var isFinished: Bool {
        if case .finished = model.phase { return true }
        return false
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
                ThankYouView(urls: urls, tipJar: tipJar) { model.dismissFlow() }
            }
        }
        .frame(maxWidth: isFinished ? .infinity : 640,
               maxHeight: isFinished ? .infinity : 480)
        .padding(isFinished ? 0 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nativeImporter(isPresented: $showFolderPicker) { folder in
            model.exportBlurbPair(into: folder)
        }
        .fileExporter(isPresented: fileExporterBinding,
                      document: model.renderedDocument,
                      contentType: .pdf,
                      defaultFilename: model.defaultSingleFilename) { result in
            model.finishSingleFile(at: try? result.get())
        }
    }

    // MARK: 1 — preflight

    private var targetTitle: String {
        targetTitle(model.target)
    }

    private func targetTitle(_ target: ExportModel.ExportTarget) -> String {
        switch target {
        case .blurb: String(localized: "Blurb Book", bundle: .module)
        case .genericPrint: String(localized: "Print PDF", bundle: .module)
        case .digital: String(localized: "Digital PDF", bundle: .module)
        }
    }

    private func targetDescription(_ target: ExportModel.ExportTarget) -> String {
        switch target {
        case .blurb: String(localized: "Two PDFs for Blurb printing: one for the pages and one for the cover.", bundle: .module)
        case .genericPrint: String(localized: "A print-ready PDF with bleed for other print services.", bundle: .module)
        case .digital: String(localized: "A screen-resolution PDF for sharing and on-device viewing.", bundle: .module)
        }
    }

    private var exportStep: Int {
        switch model.phase {
        case .idle, .preflight: 0
        case .choosingDestination: 1
        case .exporting, .failed: 2
        case .finished: 3
        }
    }

    private var exportFailed: Bool {
        if case .failed = model.phase { return true }
        return false
    }

    /// A stable reading area and trailing action row across export steps.
    private func stepLayout<Content: View, Actions: View>(
        title: String, @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ExportStepTracker(titles: [
                String(localized: "Check", bundle: .module),
                String(localized: "Setup", bundle: .module),
                String(localized: "Export", bundle: .module),
                String(localized: "Saved", bundle: .module)
            ], current: exportStep, failed: exportFailed)
            .padding(.bottom, 24)
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.bottom, 24)
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            Divider().padding(.top, 20)
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                actions()
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .padding(.top, 16)
        }
    }

    private var cancelButton: some View {
        Button(String(localized: "Cancel", bundle: .module)) { model.dismissFlow() }
            .keyboardShortcut(.cancelAction)
    }

    private var preflightStep: some View {
        stepLayout(title: String(localized: "Check your book", bundle: .module)) {
            if model.issues.isEmpty {
                Label(String(localized: "No issues found. Ready to export.", bundle: .module), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.issues.enumerated()), id: \.offset) { index, issue in
                        if index > 0 { Divider() }
                        preflightRow(issue)
                    }
                }
                .accessibilityIdentifier("preflight-list")
            }
        } actions: {
            cancelButton
            Button(String(localized: "Continue", bundle: .module)) { model.continueFromPreflight() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.summary.hasBlockingIssues)
                .help(Text("Choose an export type and where to save it", bundle: .module))
                .accessibilityIdentifier("preflight-continue")
        }
    }

    private func issueLocation(_ issue: PreflightIssue) -> String {
        if issue.pageID == model.book.backCover?.id, issue.pageID != nil {
            return String(localized: "Back cover", bundle: .module)
        }
        if let index = issue.pageIndex, model.book.pages.indices.contains(index) {
            return model.book.pages[index].role == .cover
                ? String(localized: "Cover", bundle: .module)
                : String(localized: "Page \(index)", bundle: .module)
        }
        return String(localized: "Book", bundle: .module)
    }

    private func preflightRow(_ issue: PreflightIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: PreflightSummary.systemImage(for: issue))
                .foregroundStyle(issue.isBlocking ? .red : .yellow)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(issueLocation(issue))
                    .font(.subheadline.weight(.semibold))
                Text(PreflightSummary.message(for: issue))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { issueActions(issue) }
                    VStack(alignment: .leading, spacing: 8) { issueActions(issue) }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func issueActions(_ issue: PreflightIssue) -> some View {
        Button {
            editor.revealPreflightIssue(issue)
            model.dismissFlow()
        } label: {
            Label(issue.slotID == nil
                  ? String(localized: "Show page", bundle: .module)
                  : String(localized: "Show in editor", bundle: .module), systemImage: "arrow.up.forward")
        }
        .accessibilityLabel(Text("Show \(issueLocation(issue)) in editor", bundle: .module))
        if case .pageCountOutOfRange(let actual, let min, _) = issue.kind, actual < min {
            Button(String(localized: "Add \(min - actual) blank pages", bundle: .module)) {
                editor.padToMinimumPages()
                model.begin(model.target)
            }
            .help(Text("Append blank pages to meet the minimum page count", bundle: .module))
        }
    }

    // MARK: 2 — destination

    private var destinationStep: some View {
        stepLayout(title: String(localized: "Choose export type", bundle: .module)) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ExportModel.ExportTarget.allCases, id: \.self) { target in
                    Button {
                        model.selectTarget(target)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: model.target == target ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(model.target == target ? Color.accentColor : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(targetTitle(target)).font(.headline)
                                Text(targetDescription(target))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.target == target ? [.isSelected] : [])
                    .accessibilityIdentifier("export-type-\(target.rawValue)")
                }
                if model.target == .blurb {
                    Text("Blurb needs two files. Pick a folder; PhotoBooks writes \u{201C}\(ExportFilenames.interior(title: model.book.title))\u{201D} and \u{201C}\(ExportFilenames.cover(title: model.book.title))\u{201D} into it.", bundle: .module)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            cancelButton
            if model.target == .blurb {
                Button(String(localized: "Choose Folder…", bundle: .module)) { showFolderPicker = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("export-choose-folder")
            } else {
                Button(String(localized: "Export…", bundle: .module)) { model.exportSingleFileToTemporary() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("export-single-file")
            }
        }
    }

    // MARK: 3 — progress

    private func progressStep(_ value: Double) -> some View {
        stepLayout(title: targetTitle) {
            VStack(alignment: .leading, spacing: 16) {
                if model.renderedDocument != nil {
                    Label(String(localized: "PDF ready. Choose where to save it.", bundle: .module), systemImage: "doc.badge.checkmark")
                } else {
                    ProgressView(value: value) {
                        Text(value < 0.5 ? String(localized: "Fetching photos…", bundle: .module) : String(localized: "Rendering pages…", bundle: .module))
                    } currentValueLabel: {
                        Text(value, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .progressViewStyle(.linear)
                    .accessibilityIdentifier("export-progress")
                }
                Text(model.target == .blurb
                     ? String(localized: "Next: open your saved PDFs.", bundle: .module)
                     : String(localized: "Next: choose where to save your PDF.", bundle: .module))
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button(String(localized: "Cancel", bundle: .module)) { model.cancelExport() }
                .keyboardShortcut(.cancelAction)
                .help(Text("Stop the export in progress", bundle: .module))
                .accessibilityIdentifier("export-cancel")
        }
    }

    // MARK: 4 — failure (success lives in ThankYouView)

    private func failureStep(message: String, retryIDs: [PhotoID]) -> some View {
        stepLayout(title: String(localized: "Export failed", bundle: .module)) {
            Label(message, systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.secondary)
        } actions: {
            Button(String(localized: "Close", bundle: .module)) { model.dismissFlow() }
                .keyboardShortcut(.cancelAction)
            Button(retryIDs.isEmpty ? String(localized: "Try Again", bundle: .module) : String(localized: "Retry Failed Photos", bundle: .module)) { model.retry() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("export-retry")
        }
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
            Button(String(localized: "Export…", bundle: .module)) {
                exportModel?.begin()
            }
            .disabled(exportModel == nil)
        }
    }
}
