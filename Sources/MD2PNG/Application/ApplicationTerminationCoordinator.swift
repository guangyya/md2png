import AppKit

@MainActor
final class ApplicationTerminationCoordinator {
    struct Dependencies {
        let isUpdateInstallPending: () -> Bool
        let cancelPreparedInstallation: (@escaping @MainActor () -> Void) -> Bool
    }

    private let dependencies: Dependencies
    private let diagnosticLogger: DiagnosticLogger
    private var isWaitingForUpdateDeferral = false

    init(
        dependencies: Dependencies,
        diagnosticLogger: DiagnosticLogger = .disabled
    ) {
        self.dependencies = dependencies
        self.diagnosticLogger = diagnosticLogger
    }

    func shouldTerminate(
        replyWhenReady: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        if dependencies.isUpdateInstallPending() {
            recordAccepted()
            return .terminateNow
        }
        if isWaitingForUpdateDeferral {
            diagnosticLogger.record(
                category: .appLifecycle,
                stage: .applicationTermination,
                result: .deferred,
                level: .verbose
            )
            return .terminateLater
        }

        isWaitingForUpdateDeferral = true
        let waitsForDeferral = dependencies.cancelPreparedInstallation { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isWaitingForUpdateDeferral else { return }
                self.isWaitingForUpdateDeferral = false
                self.recordAccepted()
                replyWhenReady()
            }
        }
        if waitsForDeferral {
            diagnosticLogger.record(
                category: .appLifecycle,
                stage: .applicationTermination,
                result: .deferred
            )
            return .terminateLater
        }
        isWaitingForUpdateDeferral = false
        recordAccepted()
        return .terminateNow
    }

    private func recordAccepted() {
        diagnosticLogger.record(
            category: .appLifecycle,
            stage: .applicationTermination,
            result: .accepted
        )
    }
}
