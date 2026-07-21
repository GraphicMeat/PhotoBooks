import Foundation
import Synchronization
import Testing
@testable import PhotoBookImport

@Suite struct AsyncLimiterTests {

    private struct Counts: Sendable {
        var running = 0
        var peak = 0
        var done = 0
    }

    private final class Tracker: Sendable {
        let state = Mutex(Counts())
    }

    @Test func neverExceedsLimitAndCompletesAll() async {
        let limiter = AsyncLimiter(limit: 4)
        let tracker = Tracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    await limiter.acquire()
                    tracker.state.withLock {
                        $0.running += 1
                        $0.peak = max($0.peak, $0.running)
                    }
                    try? await Task.sleep(for: .milliseconds(2))
                    tracker.state.withLock {
                        $0.running -= 1
                        $0.done += 1
                    }
                    await limiter.release()
                }
            }
        }

        let final = tracker.state.withLock { $0 }
        #expect(final.done == 40)
        #expect(final.peak <= 4)
        #expect(final.peak > 1)     // it actually ran concurrently
    }
}
