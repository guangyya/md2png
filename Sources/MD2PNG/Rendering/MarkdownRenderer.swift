import AppKit
import WebKit

@MainActor
final class MarkdownRenderer: NSObject, WKNavigationDelegate {
    typealias Completion = (Result<NSImage, Error>) -> Void
    typealias SplitCompletion = (Result<SplitRenderResult, Error>) -> Void

    static let maximumSnapshotWidth = 1_600
    static let maximumSnapshotHeight = 16_000
    static let minimumSplitSnapshotHeight = 256
    static let maximumSplitSnapshotArea = 64_000_000

    private enum RequestMode {
        case singleImage
        case splitImages(maximumSliceHeight: Int)
    }

    private enum Output {
        case singleImage(NSImage)
        case splitImages(SplitRenderResult)
    }

    private struct Request {
        let id: UUID
        let operationID: DiagnosticOperationID
        let markdown: String
        let widthPreset: RenderWidthPreset
        let theme: RenderTheme
        let mode: RequestMode
        let startedAt: UInt64
        let completion: (Result<Output, Error>) -> Void
    }

    private struct NavigationAttempt {
        let navigation: WKNavigation
        let loadAttempt: RendererRecoveryState.LoadAttempt
    }

    private var webView: WKWebView
    private var webViewGenerationID: UUID?
    private let hostWindow: NSWindow
    private let pageURL: URL?
    private let watchdogTimeout: TimeInterval
    private let diagnosticLogger: DiagnosticLogger
    private var requests: [UUID: Request] = [:]
    private var recoveryState: RendererRecoveryState
    private var currentNavigation: NavigationAttempt?
    private var watchdogAttempt: RendererRecoveryState.Attempt?
    private var watchdogWorkItem: DispatchWorkItem?

    init(
        pageURL: URL? = RendererResources.pageURL,
        watchdogTimeout: TimeInterval = 15,
        diagnosticLogger: DiagnosticLogger = .disabled
    ) {
        self.pageURL = pageURL
        self.watchdogTimeout = max(watchdogTimeout, 0)
        self.diagnosticLogger = diagnosticLogger
        let recoveryState = RendererRecoveryState(hasRendererPage: pageURL != nil)
        self.recoveryState = recoveryState
        webViewGenerationID = recoveryState.currentRendererGenerationID
        webView = Self.makeWebView()
        hostWindow = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1200, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        diagnosticLogger.record(
            category: .resource,
            stage: .rendererPageLookup,
            result: pageURL == nil ? .unavailable : .available,
            level: pageURL == nil ? .error : .info
        )
        hostWindow.contentView = webView
        hostWindow.orderBack(nil)
        webView.navigationDelegate = self
        perform(recoveryState.initialActions)
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            configuration: configuration
        )
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func render(
        _ markdown: String,
        widthPreset: RenderWidthPreset = .standard,
        theme: RenderTheme = .cleanLight,
        operationID: DiagnosticOperationID = DiagnosticOperationID(),
        completion: @escaping Completion
    ) {
        enqueue(
            markdown,
            widthPreset: widthPreset,
            theme: theme,
            operationID: operationID,
            mode: .singleImage
        ) { result in
            completion(result.flatMap { output in
                guard case let .singleImage(image) = output else {
                    return .failure(AppError.invalidRendererResponse)
                }
                return .success(image)
            })
        }
    }

    func renderSplit(
        _ markdown: String,
        widthPreset: RenderWidthPreset = .standard,
        theme: RenderTheme = .cleanLight,
        maximumSliceHeight: Int = MarkdownRenderer.maximumSnapshotHeight,
        operationID: DiagnosticOperationID = DiagnosticOperationID(),
        completion: @escaping SplitCompletion
    ) {
        let boundedSliceHeight = min(
            max(maximumSliceHeight, Self.minimumSplitSnapshotHeight),
            Self.maximumSnapshotHeight
        )
        enqueue(
            markdown,
            widthPreset: widthPreset,
            theme: theme,
            operationID: operationID,
            mode: .splitImages(maximumSliceHeight: boundedSliceHeight)
        ) { result in
            completion(result.flatMap { output in
                guard case let .splitImages(splitResult) = output else {
                    return .failure(AppError.invalidRendererResponse)
                }
                return .success(splitResult)
            })
        }
    }

    private func enqueue(
        _ markdown: String,
        widthPreset: RenderWidthPreset,
        theme: RenderTheme,
        operationID: DiagnosticOperationID,
        mode: RequestMode,
        completion: @escaping (Result<Output, Error>) -> Void
    ) {
        let request = Request(
            id: UUID(),
            operationID: operationID,
            markdown: markdown,
            widthPreset: widthPreset,
            theme: theme,
            mode: mode,
            startedAt: DispatchTime.now().uptimeNanoseconds,
            completion: completion
        )
        requests[request.id] = request
        diagnosticLogger.record(
            category: .renderer,
            stage: .renderRequest,
            result: .queued,
            level: .verbose,
            operationID: operationID
        )
        perform(recoveryState.enqueue(request.id))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        guard let loadAttempt = loadAttempt(for: navigation) else { return }
        currentNavigation = nil
        cancelWatchdog(for: .load(loadAttempt))
        diagnosticLogger.record(
            category: .renderer,
            stage: .rendererLoad,
            result: .succeeded,
            operationID: activeOperationID
        )
        if loadAttempt.kind == .recovery {
            diagnosticLogger.record(
                category: .webKitRecovery,
                stage: .rendererRecovery,
                result: .succeeded,
                operationID: activeOperationID
            )
        }
        perform(recoveryState.rendererDidLoad(loadAttempt))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        rendererLoadFailed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        rendererLoadFailed(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, let webViewGenerationID else { return }
        handleContentProcessTermination(
            from: .delegate(rendererGenerationID: webViewGenerationID)
        )
    }

#if DEBUG
    var rendererGenerationIDForTesting: UUID? {
        webViewGenerationID
    }

    var webViewIdentityForTesting: ObjectIdentifier {
        ObjectIdentifier(webView)
    }

    func simulateContentProcessTerminationForTesting() {
        webViewWebContentProcessDidTerminate(webView)
    }

    func simulateWatchdogTimeoutForTesting() {
        guard let watchdogAttempt else { return }
        watchdogDidFire(for: watchdogAttempt)
    }
#endif

    private func start(_ execution: RendererRecoveryState.Execution) {
        guard recoveryState.isCurrent(execution),
              webViewGenerationID == execution.rendererGenerationID else { return }
        guard let request = requests[execution.requestID] else {
            finish(execution, with: .failure(AppError.rendererUnavailable))
            return
        }
        let javaScriptStartedAt = DispatchTime.now().uptimeNanoseconds
        diagnosticLogger.record(
            category: .renderer,
            stage: .renderJavaScript,
            result: .started,
            level: .verbose,
            operationID: request.operationID
        )
        armWatchdog(for: .render(execution))

        Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await self.webView.callAsyncJavaScript(
                    """
                    document.getElementById("card").style.maxWidth = maximumWidth + "px"
                    return await window.renderMarkdown(markdown, renderTheme)
                    """,
                    arguments: [
                        "markdown": request.markdown,
                        "maximumWidth": request.widthPreset.cardMaximumWidth,
                        "renderTheme": request.theme.rawValue
                    ],
                    in: nil,
                    contentWorld: .page
                )
                guard self.recoveryState.isCurrent(execution) else { return }
                guard let response = RendererJavaScriptResponse(value) else {
                    self.finish(execution, with: .failure(AppError.invalidRendererResponse))
                    return
                }

                guard case let .success(rawWidth, rawHeight) = response else {
                    if case let .failure(failure) = response {
                        self.finish(execution, with: .failure(failure))
                    }
                    return
                }

                let measuredHeight = Int(ceil(rawHeight))
                let width = max(520, Int(ceil(rawWidth)))
                let height = max(80, measuredHeight)
                guard width <= Self.maximumSnapshotWidth else {
                    self.finish(
                        execution,
                        with: .failure(AppError.contentTooLarge(width: width, height: height))
                    )
                    return
                }

                let slices: [RenderSnapshotSlice]
                let splitGeometry: RenderSplitGeometry?
                switch request.mode {
                case .singleImage:
                    guard height <= Self.maximumSnapshotHeight else {
                        self.finish(
                            execution,
                            with: .failure(AppError.contentTooLarge(
                                width: width,
                                height: height
                            ))
                        )
                        return
                    }
                    slices = [RenderSnapshotSlice(
                        range: 0 ..< height,
                        ending: .contentEnd
                    )]
                    splitGeometry = nil
                case let .splitImages(maximumSliceHeight):
                    guard height <= Self.maximumSplitSnapshotArea / width else {
                        self.finish(
                            execution,
                            with: .failure(AppError.contentTooLarge(
                                width: width,
                                height: height
                            ))
                        )
                        return
                    }
                    let geometryValue = try await self.webView.callAsyncJavaScript(
                        "return window.measureRenderedContentForSplitting()",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                    guard self.recoveryState.isCurrent(execution) else { return }
                    guard let geometryResponse = RendererSplitGeometryResponse(
                        geometryValue
                    ), geometryResponse.geometry.contentHeight == measuredHeight,
                    let geometry = RenderSplitGeometry(
                        contentHeight: height,
                        preferredBreakOffsets: geometryResponse
                            .geometry.preferredBreakOffsets,
                        protectedRanges: geometryResponse.geometry.protectedRanges
                    ) else {
                        self.finish(
                            execution,
                            with: .failure(AppError.invalidRendererResponse)
                        )
                        return
                    }
                    slices = RenderSplitPlanner.slices(
                        for: geometry,
                        maximumSliceHeight: maximumSliceHeight
                    )
                    splitGeometry = geometry
                    guard !slices.isEmpty else {
                        self.finish(
                            execution,
                            with: .failure(AppError.invalidRendererResponse)
                        )
                        return
                    }
                }

                self.diagnosticLogger.record(
                    category: .renderer,
                    stage: .renderJavaScript,
                    result: .succeeded,
                    level: .verbose,
                    operationID: request.operationID,
                    durationMilliseconds: DiagnosticDuration.milliseconds(
                        since: javaScriptStartedAt
                    ),
                    dimensions: DiagnosticDimensions(width: width, height: height),
                    itemCount: slices.count
                )

                self.webView.setFrameSize(NSSize(width: width, height: height))
                self.hostWindow.setContentSize(NSSize(width: width, height: height))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.takeSnapshots(
                        for: execution,
                        width: width,
                        contentHeight: height,
                        slices: slices,
                        splitGeometry: splitGeometry
                    )
                }
            } catch {
                self.handle(error, for: execution)
            }
        }
    }

    private func takeSnapshots(
        for execution: RendererRecoveryState.Execution,
        width: Int,
        contentHeight: Int,
        slices: [RenderSnapshotSlice],
        splitGeometry: RenderSplitGeometry?
    ) {
        guard recoveryState.renderDidStartSnapshot(execution) else { return }
        diagnosticLogger.record(
            category: .renderer,
            stage: .renderSnapshot,
            result: .started,
            level: .verbose,
            operationID: requests[execution.requestID]?.operationID,
            dimensions: DiagnosticDimensions(width: width, height: contentHeight),
            itemCount: slices.count
        )
        takeSnapshot(
            for: execution,
            width: width,
            contentHeight: contentHeight,
            slices: slices,
            splitGeometry: splitGeometry,
            index: 0,
            parts: []
        )
    }

    private func takeSnapshot(
        for execution: RendererRecoveryState.Execution,
        width: Int,
        contentHeight: Int,
        slices: [RenderSnapshotSlice],
        splitGeometry: RenderSplitGeometry?,
        index: Int,
        parts: [SplitRenderResult.Part]
    ) {
        guard recoveryState.isCurrent(execution), slices.indices.contains(index) else {
            return
        }
        armWatchdog(for: .render(execution))
        let slice = slices[index]
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(
            x: 0,
            y: slice.y,
            width: width,
            height: slice.height
        )

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let error {
                    self.handle(error, for: execution)
                } else if let image {
                    guard abs(image.size.width - CGFloat(width)) <= 1,
                          abs(image.size.height - CGFloat(slice.height)) <= 1 else {
                        self.finish(
                            execution,
                            with: .failure(AppError.rendererPNGEncodingFailed)
                        )
                        return
                    }
                    var nextParts = parts
                    nextParts.append(SplitRenderResult.Part(
                        image: image,
                        slice: slice
                    ))
                    let nextIndex = index + 1
                    if slices.indices.contains(nextIndex) {
                        self.takeSnapshot(
                            for: execution,
                            width: width,
                            contentHeight: contentHeight,
                            slices: slices,
                            splitGeometry: splitGeometry,
                            index: nextIndex,
                            parts: nextParts
                        )
                    } else {
                        self.finishSnapshots(
                            for: execution,
                            width: width,
                            contentHeight: contentHeight,
                            splitGeometry: splitGeometry,
                            parts: nextParts
                        )
                    }
                } else {
                    self.finish(
                        execution,
                        with: .failure(AppError.rendererPNGEncodingFailed)
                    )
                }
            }
        }
    }

    private func finishSnapshots(
        for execution: RendererRecoveryState.Execution,
        width: Int,
        contentHeight: Int,
        splitGeometry: RenderSplitGeometry?,
        parts: [SplitRenderResult.Part]
    ) {
        guard let request = requests[execution.requestID] else {
            finish(execution, with: .failure(AppError.rendererUnavailable))
            return
        }
        switch request.mode {
        case .singleImage:
            guard parts.count == 1, let image = parts.first?.image else {
                finish(execution, with: .failure(AppError.rendererPNGEncodingFailed))
                return
            }
            finish(execution, with: .success(.singleImage(image)))
        case .splitImages:
            guard let splitGeometry else {
                finish(execution, with: .failure(AppError.invalidRendererResponse))
                return
            }
            finish(execution, with: .success(.splitImages(SplitRenderResult(
                contentSize: NSSize(width: width, height: contentHeight),
                geometry: splitGeometry,
                parts: parts
            ))))
        }
    }

    private func finish(
        _ execution: RendererRecoveryState.Execution,
        with result: Result<Output, Error>
    ) {
        let transition = recoveryState.finish(execution)
        guard let requestID = transition.completedRequestID else { return }
        cancelWatchdog(for: .render(execution))
        if let request = requests.removeValue(forKey: requestID) {
            switch result {
            case let .success(output):
                let dimensions: DiagnosticDimensions
                let itemCount: Int
                switch output {
                case let .singleImage(image):
                    dimensions = Self.pixelDimensions(for: image)
                    itemCount = 1
                case let .splitImages(splitResult):
                    dimensions = DiagnosticDimensions(
                        width: Int(splitResult.contentSize.width.rounded()),
                        height: Int(splitResult.contentSize.height.rounded())
                    )
                    itemCount = splitResult.parts.count
                }
                diagnosticLogger.record(
                    category: .renderer,
                    stage: .rendererExecution,
                    result: .succeeded,
                    operationID: request.operationID,
                    durationMilliseconds: DiagnosticDuration.milliseconds(
                        since: request.startedAt
                    ),
                    dimensions: dimensions,
                    itemCount: itemCount
                )
            case let .failure(error):
                diagnosticLogger.record(
                    category: .renderer,
                    stage: .rendererExecution,
                    result: .failed,
                    level: .error,
                    operationID: request.operationID,
                    durationMilliseconds: DiagnosticDuration.milliseconds(
                        since: request.startedAt
                    ),
                    error: error
                )
            }
            request.completion(result)
        }
        perform(transition.actions)
    }

    private func handle(
        _ error: Error,
        for execution: RendererRecoveryState.Execution
    ) {
        guard recoveryState.isCurrent(execution) else { return }
        if Self.isContentProcessTermination(error) {
            handleContentProcessTermination(from: .executionError(execution))
        } else {
            finish(execution, with: .failure(AppError.rendererFailed))
        }
    }

    nonisolated static func isContentProcessTermination(_ error: Error) -> Bool {
        (error as? WKError)?.code == .webContentProcessTerminated
    }

    private func handleContentProcessTermination(
        from signal: RendererRecoveryState.TerminationSignal
    ) {
        let operationID: DiagnosticOperationID? = switch signal {
        case let .executionError(execution):
            requests[execution.requestID]?.operationID
        case .delegate:
            activeOperationID
        }
        switch recoveryState.contentProcessTerminated(from: signal) {
        case .ignored:
            diagnosticLogger.record(
                category: .webKitRecovery,
                stage: .contentProcessTermination,
                result: .ignored,
                level: .verbose,
                operationID: operationID
            )
            return
        case let .handled(actions):
            diagnosticLogger.record(
                category: .webKitRecovery,
                stage: .contentProcessTermination,
                result: .accepted,
                operationID: operationID
            )
            if actions.contains(where: { action in
                if case .loadRenderer = action { return true }
                return false
            }) {
                diagnosticLogger.record(
                    category: .webKitRecovery,
                    stage: .rendererRecovery,
                    result: .started,
                    operationID: operationID
                )
            }
            cancelWatchdog()
            currentNavigation = nil
            perform(actions)
        }
    }

    private func loadRendererPage(_ attempt: RendererRecoveryState.LoadAttempt) {
        guard recoveryState.isCurrent(.load(attempt)) else { return }
        diagnosticLogger.record(
            category: .renderer,
            stage: .rendererLoad,
            result: .started,
            level: attempt.kind == .initial ? .verbose : .info,
            operationID: activeOperationID
        )
        guard let pageURL else {
            diagnosticLogger.record(
                category: .renderer,
                stage: .rendererLoad,
                result: .failed,
                level: .error,
                operationID: activeOperationID,
                error: AppError.rendererUnavailable
            )
            perform(recoveryState.rendererLoadFailed(attempt))
            return
        }
        installWebView(for: attempt)
        armWatchdog(for: .load(attempt))
        guard let navigation = webView.loadFileURL(
            pageURL,
            allowingReadAccessTo: pageURL.deletingLastPathComponent()
        ) else {
            cancelWatchdog(for: .load(attempt))
            diagnosticLogger.record(
                category: .renderer,
                stage: .rendererLoad,
                result: .failed,
                level: .error,
                operationID: activeOperationID,
                error: AppError.rendererUnavailable
            )
            perform(recoveryState.rendererLoadFailed(attempt))
            return
        }
        currentNavigation = NavigationAttempt(
            navigation: navigation,
            loadAttempt: attempt
        )
    }

    private func installWebView(for attempt: RendererRecoveryState.LoadAttempt) {
        guard webViewGenerationID != attempt.id else { return }
        let nextWebView = Self.makeWebView()
        nextWebView.navigationDelegate = self
        hostWindow.contentView = nextWebView
        webView = nextWebView
        webViewGenerationID = attempt.id
    }

    private func rendererLoadFailed(
        _ navigation: WKNavigation?,
        error: (any Error)? = nil
    ) {
        guard let loadAttempt = loadAttempt(for: navigation) else { return }
        currentNavigation = nil
        cancelWatchdog(for: .load(loadAttempt))
        diagnosticLogger.record(
            category: .renderer,
            stage: .rendererLoad,
            result: .failed,
            level: .error,
            operationID: activeOperationID,
            error: error ?? AppError.rendererUnavailable
        )
        perform(recoveryState.rendererLoadFailed(loadAttempt))
    }

    private func loadAttempt(
        for navigation: WKNavigation?
    ) -> RendererRecoveryState.LoadAttempt? {
        guard let navigation, let currentNavigation,
              navigation === currentNavigation.navigation else { return nil }
        return currentNavigation.loadAttempt
    }

    private func armWatchdog(for attempt: RendererRecoveryState.Attempt) {
        cancelWatchdog()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.watchdogDidFire(for: attempt)
            }
        }
        watchdogAttempt = attempt
        watchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + watchdogTimeout,
            execute: workItem
        )
    }

    private func cancelWatchdog(for attempt: RendererRecoveryState.Attempt? = nil) {
        if let attempt, watchdogAttempt != attempt { return }
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        watchdogAttempt = nil
    }

    private func watchdogDidFire(for attempt: RendererRecoveryState.Attempt) {
        guard watchdogAttempt == attempt else { return }
        let operationID: DiagnosticOperationID? = switch attempt {
        case let .render(execution):
            requests[execution.requestID]?.operationID
        case .load:
            activeOperationID
        }
        diagnosticLogger.record(
            category: .webKitRecovery,
            stage: .watchdogTimeout,
            result: .failed,
            level: .error,
            operationID: operationID,
            error: AppError.rendererTimedOut
        )
        watchdogWorkItem = nil
        watchdogAttempt = nil

        if case let .load(loadAttempt) = attempt,
           currentNavigation?.loadAttempt == loadAttempt {
            currentNavigation = nil
        }
        perform(recoveryState.timedOut(attempt))
    }

    private func perform(_ actions: [RendererRecoveryState.Action]) {
        for action in actions {
            switch action {
            case let .loadRenderer(attempt):
                loadRendererPage(attempt)
            case let .start(execution):
                start(execution)
            case let .fail(requestIDs, failure):
                let error: AppError = switch failure {
                case .rendererUnavailable:
                    .rendererUnavailable
                case .recoveryFailed:
                    .rendererRecoveryFailed
                case .timedOut:
                    .rendererTimedOut
                }
                for requestID in requestIDs {
                    if let request = requests.removeValue(forKey: requestID) {
                        diagnosticLogger.record(
                            category: failure == .recoveryFailed
                                ? .webKitRecovery
                                : .renderer,
                            stage: failure == .recoveryFailed
                                ? .rendererRecovery
                                : .rendererExecution,
                            result: .failed,
                            level: .error,
                            operationID: request.operationID,
                            durationMilliseconds: DiagnosticDuration.milliseconds(
                                since: request.startedAt
                            ),
                            error: error
                        )
                        request.completion(.failure(error))
                    }
                }
            }
        }
    }

    private var activeOperationID: DiagnosticOperationID? {
        recoveryState.activeRequestID.flatMap { requests[$0]?.operationID }
    }

    private static func pixelDimensions(for image: NSImage) -> DiagnosticDimensions {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in
                lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
            }) {
            return DiagnosticDimensions(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        return DiagnosticDimensions(
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded())
        )
    }
}
