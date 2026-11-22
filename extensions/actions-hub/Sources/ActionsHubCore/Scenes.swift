import Foundation

public protocol ActionExecutor: Sendable {
    func run(_ step: Step) async throws
}

public struct StepFailure: Sendable, Equatable {
    public let step: Step
    public let message: String
}

public enum SceneRunner {
    /// Runs the steps in order. A failing step is recorded and the scene carries on, so one
    /// missing Shortcut doesn't stop the rest. Cancelling the task stops it between steps.
    public static func run(
        _ scene: ActionScene,
        executor: some ActionExecutor,
        progress: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> [StepFailure] {
        var failures: [StepFailure] = []
        progress(0, scene.steps.count)
        for (index, step) in scene.steps.enumerated() {
            if Task.isCancelled { break }
            do { try await executor.run(step) }
            catch { failures.append(StepFailure(step: step, message: error.localizedDescription)) }
            progress(index + 1, scene.steps.count)
        }
        return failures
    }
}
