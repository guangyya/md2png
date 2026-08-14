import Foundation

struct RendererRecoveryState {
    struct Execution: Equatable {
        let requestID: UUID
        let attemptID: UUID
    }

    enum Failure: Equatable {
        case rendererUnavailable
        case recoveryFailed
    }

    enum Action: Equatable {
        case loadRenderer
        case start(Execution)
        case fail(requestIDs: [UUID], failure: Failure)
    }

    enum TerminationSignal: Equatable {
        case delegate
        case executionError(Execution)
    }

    enum TerminationTransition: Equatable {
        case ignored
        case handled([Action])
    }

    enum Phase: Equatable {
        case initialLoad
        case recoveryLoad
        case ready
        case rendering(Execution)
        case needsReload
        case unavailable
    }

    struct FinishTransition {
        let completedRequestID: UUID?
        let actions: [Action]
    }

    private struct ActiveRequest {
        let id: UUID
        var recoveryAttempts: Int
    }

    private(set) var phase: Phase
    private var activeRequest: ActiveRequest?
    private var queuedRequestIDs: [UUID] = []
    private var pendingTerminationDelegateCount = 0

    init(hasRendererPage: Bool = true) {
        phase = hasRendererPage
            ? .initialLoad
            : .unavailable
    }

    // Internal observability for the pure state-machine tests.
    var activeRequestID: UUID? {
        activeRequest?.id
    }

    // Internal observability for the pure state-machine tests.
    var pendingRequestIDs: [UUID] {
        queuedRequestIDs
    }

    func isCurrent(_ execution: Execution) -> Bool {
        phase == .rendering(execution)
    }

    mutating func enqueue(_ requestID: UUID) -> [Action] {
        if phase == .unavailable {
            return [.fail(requestIDs: [requestID], failure: .rendererUnavailable)]
        }

        queuedRequestIDs.append(requestID)
        if phase == .needsReload {
            phase = .recoveryLoad
            return [.loadRenderer]
        }

        return startNextIfPossible()
    }

    mutating func rendererDidLoad() -> [Action] {
        guard phase == .initialLoad || phase == .recoveryLoad else { return [] }
        phase = .ready
        return startNextIfPossible()
    }

    mutating func rendererLoadFailed() -> [Action] {
        switch phase {
        case .initialLoad:
            return failAllRequests(
                with: .rendererUnavailable,
                nextPhase: .unavailable
            )
        case .recoveryLoad:
            return failAllRequests(
                with: .recoveryFailed,
                nextPhase: .needsReload
            )
        case .ready, .rendering, .needsReload, .unavailable:
            return []
        }
    }

    mutating func contentProcessTerminated(
        from signal: TerminationSignal = .delegate
    ) -> TerminationTransition {
        switch signal {
        case .delegate where pendingTerminationDelegateCount > 0:
            pendingTerminationDelegateCount -= 1
            return .ignored
        case .delegate:
            break
        case let .executionError(execution):
            guard isCurrent(execution) else { return .ignored }
            pendingTerminationDelegateCount += 1
        }

        let actions: [Action]
        switch phase {
        case .initialLoad, .ready:
            phase = .recoveryLoad
            actions = [.loadRenderer]
        case .recoveryLoad:
            actions = failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
        case .rendering:
            guard var activeRequest else {
                return .handled(
                    failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
                )
            }
            guard activeRequest.recoveryAttempts == 0 else {
                return .handled(
                    failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
                )
            }
            activeRequest.recoveryAttempts += 1
            self.activeRequest = activeRequest
            phase = .recoveryLoad
            actions = [.loadRenderer]
        case .needsReload, .unavailable:
            actions = []
        }
        return .handled(actions)
    }

    mutating func finish(_ execution: Execution) -> FinishTransition {
        guard case let .rendering(currentExecution) = phase,
              currentExecution == execution,
              activeRequest?.id == execution.requestID else {
            return FinishTransition(completedRequestID: nil, actions: [])
        }

        let completedRequestID = execution.requestID
        activeRequest = nil
        phase = .ready
        return FinishTransition(
            completedRequestID: completedRequestID,
            actions: startNextIfPossible()
        )
    }

    private mutating func startNextIfPossible() -> [Action] {
        guard phase == .ready else { return [] }

        if activeRequest == nil, !queuedRequestIDs.isEmpty {
            activeRequest = ActiveRequest(
                id: queuedRequestIDs.removeFirst(),
                recoveryAttempts: 0
            )
        }
        guard let activeRequest else { return [] }

        let execution = Execution(
            requestID: activeRequest.id,
            attemptID: UUID()
        )
        phase = .rendering(execution)
        return [.start(execution)]
    }

    private mutating func failAllRequests(
        with failure: Failure,
        nextPhase: Phase
    ) -> [Action] {
        var requestIDs: [UUID] = []
        if let activeRequest {
            requestIDs.append(activeRequest.id)
        }
        requestIDs.append(contentsOf: queuedRequestIDs)

        activeRequest = nil
        queuedRequestIDs.removeAll()
        phase = nextPhase
        guard !requestIDs.isEmpty else { return [] }
        return [.fail(requestIDs: requestIDs, failure: failure)]
    }
}
