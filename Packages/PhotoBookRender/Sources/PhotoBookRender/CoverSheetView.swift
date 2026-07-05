import PhotoBookCore
import SwiftUI

/// The full cover sheet as seen in the editor: back cover | spine (title) |
/// front cover, sized in true proportion via `CoverSheetGeometry`. The front
/// is injected (so it stays the editable `PageView`); the back and spine are
/// read-only previews that mirror the exported PDF.
public struct CoverSheetView<Front: View>: View {
    let backPage: Page?
    let title: String
    let book: Book
    let preset: PrintPreset
    let imageStore: any ImageStore
    @ViewBuilder let front: () -> Front

    public init(backPage: Page?, title: String, book: Book, preset: PrintPreset,
                imageStore: any ImageStore, @ViewBuilder front: @escaping () -> Front) {
        self.backPage = backPage
        self.title = title
        self.book = book
        self.preset = preset
        self.imageStore = imageStore
        self.front = front
    }

    private var standardPageCount: Int {
        book.pages.count(where: { $0.role == .standard })
    }

    /// Same spine-width contract the PDF exporter uses, so the on-screen spine
    /// matches the printed one exactly (single source of truth).
    private var spineInches: Double {
        ExportPlan.spineWidthInches(preset: preset, standardPageCount: standardPageCount)
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = CoverSheetGeometry.layout(available: proxy.size,
                                                   trimSize: preset.trimSize,
                                                   spineInches: spineInches)
            HStack(spacing: 0) {
                backPanel
                    .frame(width: layout.back.width, height: layout.back.height)
                spineBar(width: layout.spine.width, height: layout.spine.height)
                front()
                    .frame(width: layout.front.width, height: layout.front.height)
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("cover-sheet")
    }

    @ViewBuilder
    private var backPanel: some View {
        if let backPage {
            PageView(page: backPage, book: book, preset: preset,
                     imageStore: imageStore, highlightedSlotID: nil)
                .accessibilityIdentifier("cover-back")
        } else {
            Color(hex: book.style.backgroundColorHex)
                .aspectRatio(preset.trimSize.aspectRatio, contentMode: .fit)
                .accessibilityIdentifier("cover-back")
        }
    }

    private func spineBar(width: CGFloat, height: CGFloat) -> some View {
        let colorHex = PDFExporter.contrastingTextColorHex(forBackground: book.style.backgroundColorHex)
        let fontSize = max(1, width * 0.6)   // match PDF: title = 60% of spine width
        return ZStack {
            Color(hex: book.style.backgroundColorHex)
            Text(title)
                .font(.system(size: fontSize))
                .foregroundStyle(Color(hex: colorHex))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(90))          // top-to-bottom (US spine convention)
                .frame(width: height, height: width)   // pre-rotation frame spans the spine length
                .accessibilityIdentifier("cover-spine-title")
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
