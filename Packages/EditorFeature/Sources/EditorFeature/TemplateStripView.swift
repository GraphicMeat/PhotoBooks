import EditCore
import ModelLayer
import PhotoBookCore
import PhotoBookRender
import SwiftUI

/// Layout options for the selected page, grouped by photo count (high → low).
/// Each group shows that count's candidate wireframes; tapping one re-lays the
/// page at that count (reflowing the downstream run as needed).
struct TemplateStripView: View {
    let groups: [(count: Int, candidates: [LayoutCandidate])]
    let pageAspect: Double
    let onApply: @MainActor (Int, LayoutCandidate) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(groups, id: \.count) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(group.count) photo\(group.count == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            ForEach(Array(group.candidates.enumerated()), id: \.offset) { index, candidate in
                                Button {
                                    onApply(group.count, candidate)
                                } label: {
                                    LayoutWireframeView(candidate: candidate)
                                        .aspectRatio(pageAspect, contentMode: .fit)
                                        .frame(height: 60)
                                }
                                .buttonStyle(.plain)
                                .help("Use \(group.count)-photo layout \(index + 1)")
                                .accessibilityIdentifier("template-strip-\(group.count)-\(index)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
        .accessibilityIdentifier("template-strip")
    }
}

/// Spread template options for the selected spread (Task B5). Unlike
/// `TemplateStripView`, v1 offers only templates matching the spread's
/// CURRENT photo count, so there is no per-count grouping — a single flat
/// row of wireframes at 2× page aspect (the double-wide spread canvas).
struct SpreadTemplateStripView: View {
    let templates: [SpreadTemplateProvider.Template]
    let pageAspect: Double
    let onApply: @MainActor (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(templates, id: \.id) { template in
                    Button {
                        onApply(template.id)
                    } label: {
                        LayoutWireframeView(photoFrames: template.photoFrames,
                                            textFrames: template.textFrames)
                            .aspectRatio(pageAspect * 2, contentMode: .fit)
                            .frame(height: 60)
                    }
                    .buttonStyle(.plain)
                    .help("Use spread layout \(template.id)")
                    .accessibilityIdentifier("spread-template-strip-\(template.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
        .accessibilityIdentifier("spread-template-strip")
    }
}
