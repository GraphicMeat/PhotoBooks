import Foundation

/// Coalesces bursts of calls into one execution after a quiet interval —
/// the live preflight's pacing (D12). Main-actor-bound: both the schedule
/// sites (view callbacks) and the scheduled actions touch main-actor state.
/// The interval is injectable so tests run at 40 ms instead of 500.
@MainActor
public final class Debouncer {
    private let interval: Duration
    private var pending: Task<Void, Never>?

    public init(interval: Duration = .milliseconds(500)) {
        self.interval = interval
    }

    /// Schedules `action` after the quiet interval, cancelling any
    /// previously scheduled action — only the LAST call in a burst runs.
    public func schedule(_ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { [interval] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return      // superseded or cancelled
            }
            action()
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }
}
