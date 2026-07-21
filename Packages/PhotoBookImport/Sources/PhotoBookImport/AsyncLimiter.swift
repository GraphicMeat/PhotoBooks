import Foundation

/// Caps how many operations run concurrently. Unbounded fan-out of ImageIO
/// decodes/metadata reads from large photo grids saturates CPU and disk and
/// janks the UI; a FIFO gate keeps parallelism at a useful width instead.
actor AsyncLimiter {

    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Waits for a free slot. A released slot is handed directly to the
    /// oldest waiter (`running` never dips), so admission is FIFO.
    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
