import Foundation

/// Runs the most recently scheduled action once `delay` has passed without another `schedule`.
@MainActor
public final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?
    private var pending: (@MainActor () -> Void)?

    public init(delay: Duration) {
        self.delay = delay
    }

    public func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        pending = action
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.fire()
        }
    }

    /// Runs the pending action immediately, if any.
    public func flush() {
        task?.cancel()
        fire()
    }

    public func cancel() {
        task?.cancel()
        task = nil
        pending = nil
    }

    private func fire() {
        task = nil
        guard let action = pending else { return }
        pending = nil
        action()
    }
}
