import Foundation

struct RendererRecoveryState {
    struct LoadAttempt: Equatable {
        enum Kind: Equatable {
            case initial
            case recovery
        }

        let id: UUID
        let kind: Kind

        init(id: UUID = UUID(), kind: Kind) {
            self.id = id
            self.kind = kind
        }
    }

    struct Execution: Equatable {
        let requestID: UUID
        let attemptID: UUID
        let rendererGenerationID: UUID
    }

    enum Attempt: Equatable {
        case load(LoadAttempt)
        case render(Execution)
    }

    enum RenderStage: Equatable {
        case javaScript
        case snapshot
    }

    enum Failure: Equatable {
        case rendererUnavailable
        case recoveryFailed
        case timedOut
    }

    enum Action: Equatable {
        case loadRenderer(LoadAttempt)
        case start(Execution)
        case fail(requestIDs: [UUID], failure: Failure)
    }

    enum TerminationSignal: Equatable {
        case delegate(rendererGenerationID: UUID)
        case executionError(Execution)
    }

    enum TerminationTransition: Equatable {
        case ignored
        case handled([Action])
    }

    enum Phase: Equatable {
        case initialLoad(LoadAttempt)
        case recoveryLoad(LoadAttempt)
        case ready
        case rendering(Execution, stage: RenderStage)
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
    private(set) var currentRendererGenerationID: UUID?

    init(hasRendererPage: Bool = true) {
        if hasRendererPage {
            let attempt = LoadAttempt(kind: .initial)
            phase = .initialLoad(attempt)
            currentRendererGenerationID = attempt.id
        } else {
            phase = .unavailable
            currentRendererGenerationID = nil
        }
    }

    var initialActions: [Action] {
        guard case let .initialLoad(attempt) = phase else { return [] }
        return [.loadRenderer(attempt)]
    }

    // Internal observability for the pure state-machine tests.
    var activeRequestID: UUID? {
        activeRequest?.id
    }

    // Internal observability for the pure state-machine tests.
    var pendingRequestIDs: [UUID] {
        queuedRequestIDs
    }

    var currentLoadAttempt: LoadAttempt? {
        switch phase {
        case let .initialLoad(attempt), let .recoveryLoad(attempt):
            attempt
        case .ready, .rendering, .needsReload, .unavailable:
            nil
        }
    }

    func isCurrent(_ execution: Execution) -> Bool {
        guard case let .rendering(currentExecution, _) = phase else { return false }
        return currentExecution == execution
    }

    func isCurrent(_ attempt: Attempt) -> Bool {
        switch attempt {
        case let .load(loadAttempt):
            currentLoadAttempt == loadAttempt
        case let .render(execution):
            isCurrent(execution)
        }
    }

    mutating func enqueue(_ requestID: UUID) -> [Action] {
        if phase == .unavailable {
            return [.fail(requestIDs: [requestID], failure: .rendererUnavailable)]
        }

        queuedRequestIDs.append(requestID)
        if phase == .needsReload {
            return beginRecoveryLoad()
        }

        return startNextIfPossible()
    }

    mutating func rendererDidLoad(_ attempt: LoadAttempt) -> [Action] {
        guard currentLoadAttempt == attempt else { return [] }
        currentRendererGenerationID = attempt.id
        phase = .ready
        return startNextIfPossible()
    }

    mutating func rendererLoadFailed(_ attempt: LoadAttempt) -> [Action] {
        guard currentLoadAttempt == attempt else { return [] }
        switch attempt.kind {
        case .initial:
            return failAllRequests(
                with: .rendererUnavailable,
                nextPhase: .unavailable
            )
        case .recovery:
            return failAllRequests(
                with: .recoveryFailed,
                nextPhase: .needsReload
            )
        }
    }

    mutating func renderDidStartSnapshot(_ execution: Execution) -> Bool {
        guard isCurrent(execution) else { return false }
        phase = .rendering(execution, stage: .snapshot)
        return true
    }

    mutating func timedOut(_ attempt: Attempt) -> [Action] {
        guard isCurrent(attempt) else { return [] }
        return failAllRequests(with: .timedOut, nextPhase: .needsReload)
    }

    mutating func contentProcessTerminated(
        from signal: TerminationSignal
    ) -> TerminationTransition {
        let terminatedGenerationID: UUID
        switch signal {
        case let .delegate(rendererGenerationID):
            terminatedGenerationID = rendererGenerationID
        case let .executionError(execution):
            guard isCurrent(execution) else { return .ignored }
            terminatedGenerationID = execution.rendererGenerationID
        }
        guard terminatedGenerationID == currentRendererGenerationID else {
            return .ignored
        }

        let actions: [Action]
        switch phase {
        case .initialLoad, .ready:
            actions = beginRecoveryLoad()
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
            actions = beginRecoveryLoad()
        case .needsReload, .unavailable:
            actions = []
        }
        return .handled(actions)
    }

    mutating func finish(_ execution: Execution) -> FinishTransition {
        guard case let .rendering(currentExecution, _) = phase,
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

    private mutating func beginRecoveryLoad() -> [Action] {
        let attempt = LoadAttempt(kind: .recovery)
        currentRendererGenerationID = attempt.id
        phase = .recoveryLoad(attempt)
        return [.loadRenderer(attempt)]
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
        guard let currentRendererGenerationID else {
            return failAllRequests(with: .recoveryFailed, nextPhase: .needsReload)
        }

        let execution = Execution(
            requestID: activeRequest.id,
            attemptID: UUID(),
            rendererGenerationID: currentRendererGenerationID
        )
        phase = .rendering(execution, stage: .javaScript)
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
        currentRendererGenerationID = nil
        phase = nextPhase
        guard !requestIDs.isEmpty else { return [] }
        return [.fail(requestIDs: requestIDs, failure: failure)]
    }
}
