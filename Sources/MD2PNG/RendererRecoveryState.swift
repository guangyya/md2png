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

    enum Phase: Equatable {
        case initialLoad
        case recoveryLoad
        case ready
        case rendering(Execution)
        case needsReload
        case unavailable(Failure)
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

    init(hasRendererPage: Bool = true) {
        phase = hasRendererPage
            ? .initialLoad
            : .unavailable(.rendererUnavailable)
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
        if case let .unavailable(failure) = phase {
            return [.fail(requestIDs: [requestID], failure: failure)]
        }

        if phase == .needsReload {
            queuedRequestIDs.append(requestID)
            phase = .recoveryLoad
            return [.loadRenderer]
        }

        queuedRequestIDs.append(requestID)
        return startNextIfPossible()
    }

    mutating func rendererDidLoad() -> [Action] {
        guard phase == .initialLoad || phase == .recoveryLoad else { return [] }
        phase = .ready
        return startNextIfPossible()
    }

    mutating func rendererLoadFailed() -> [Action] {
        let failure: Failure
        switch phase {
        case .initialLoad:
            failure = .rendererUnavailable
        case .recoveryLoad:
            failure = .recoveryFailed
        case .ready, .rendering, .needsReload, .unavailable:
            return []
        }
        return failAllRequests(
            with: failure,
            nextPhase: failure == .recoveryFailed
                ? .needsReload
                : .unavailable(failure)
        )
    }

    mutating func contentProcessTerminated() -> [Action] {
        switch phase {
        case .initialLoad, .ready:
            phase = .recoveryLoad
            return [.loadRenderer]
        case .recoveryLoad:
            return failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
        case .rendering:
            guard var activeRequest else {
                return failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
            }
            guard activeRequest.recoveryAttempts == 0 else {
                return failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
            }
            activeRequest.recoveryAttempts += 1
            self.activeRequest = activeRequest
            phase = .recoveryLoad
            return [.loadRenderer]
        case .needsReload, .unavailable:
            return []
        }
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
