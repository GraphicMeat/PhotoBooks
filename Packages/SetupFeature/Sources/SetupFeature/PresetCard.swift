import PhotoBookCore
import SwiftUI

/// Preset card shared by the new-book setup flow and the format switcher.
/// Shows the trim shape, the preset name, and the size in both inches and
/// centimetres. `isCurrent` draws the accent ring the format switcher uses
/// to mark the active preset.
struct PresetCard: View {
    let preset: PrintPreset
    var isCurrent: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(.secondary, lineWidth: 1.5)
                .aspectRatio(preset.trimSize.aspectRatio, contentMode: .fit)
                .frame(height: 56)
            Text(preset.displayName)
                .font(.caption)
                .multilineTextAlignment(.center)
            Text(preset.trimSize.inchLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(preset.trimSize.centimeterLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 150)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}
