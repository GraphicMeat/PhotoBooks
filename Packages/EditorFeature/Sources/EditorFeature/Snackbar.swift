import SwiftUI

/// Configuration for a transient bottom-center snackbar. Decoupled from any
/// specific editor state so it can be reused for future transient messages.
public struct SnackbarConfig {
    public let message: String
    public let actionTitle: String?
    public var isPresented: Binding<Bool>
    public let action: (() -> Void)?

    public init(message: String, actionTitle: String? = nil,
                isPresented: Binding<Bool>, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.isPresented = isPresented
        self.action = action
    }

    /// Runs the action (if any) and dismisses.
    public func performAction() {
        action?()
        isPresented.wrappedValue = false
    }
}

/// The snackbar's visual row.
struct SnackbarView: View {
    let config: SnackbarConfig

    var body: some View {
        HStack(spacing: 12) {
            Text(config.message)
                .foregroundStyle(.white)
            if let title = config.actionTitle {
                Button(title) { config.performAction() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("snackbar-action")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.85), in: Capsule())
        .shadow(radius: 8, y: 2)
        .accessibilityIdentifier("snackbar")
    }
}

public extension View {
    /// Presents a bottom-center snackbar over this view while `config.isPresented`.
    func snackbar(_ config: SnackbarConfig?) -> some View {
        overlay(alignment: .bottom) {
            if let config, config.isPresented.wrappedValue {
                SnackbarView(config: config)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: config?.isPresented.wrappedValue)
    }
}
