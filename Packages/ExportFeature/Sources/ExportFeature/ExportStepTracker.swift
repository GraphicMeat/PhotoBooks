import SwiftUI

/// Names the sequence without implying that later steps can be opened early.
struct ExportStepTracker: View {
    let titles: [String]
    let current: Int
    var failed = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(titles.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(index == current && failed ? Color.red
                              : index <= current ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 3)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if index < current {
                            Image(systemName: "checkmark")
                        } else if index == current && failed {
                            Image(systemName: "exclamationmark.circle")
                        } else {
                            Text("\(index + 1)").monospacedDigit()
                        }
                        Text(titles[index])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption.weight(index == current ? .semibold : .regular))
                    .foregroundStyle(index == current ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current + 1) of \(titles.count): \(titles[current])", bundle: .module))
        .accessibilityValue(Text(titles.joined(separator: " → ")))
        .accessibilityIdentifier("export-step-tracker")
    }
}
