import AppKit
import WebKit

@MainActor
final class MarkdownRenderer: NSObject, WKNavigationDelegate {
    typealias Completion = (Result<NSImage, Error>) -> Void

    private struct Request {
        let id: UUID
        let markdown: String
        let widthPreset: RenderWidthPreset
        let completion: Completion
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
    private var requests: [UUID: Request] = [:]
    private var recoveryState: RendererRecoveryState
    private var currentNavigation: NavigationAttempt?
    private var watchdogAttempt: RendererRecoveryState.Attempt?
    private var watchdogWorkItem: DispatchWorkItem?

    init(
        pageURL: URL? = RendererResources.pageURL,
        watchdogTimeout: TimeInterval = 15
    ) {
        self.pageURL = pageURL
        self.watchdogTimeout = max(watchdogTimeout, 0)
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
        completion: @escaping Completion
    ) {
        let request = Request(
            id: UUID(),
            markdown: markdown,
            widthPreset: widthPreset,
            completion: completion
        )
        requests[request.id] = request
        perform(recoveryState.enqueue(request.id))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        guard let loadAttempt = loadAttempt(for: navigation) else { return }
        currentNavigation = nil
        cancelWatchdog(for: .load(loadAttempt))
        perform(recoveryState.rendererDidLoad(loadAttempt))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        rendererLoadFailed(navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        rendererLoadFailed(navigation)
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
        armWatchdog(for: .render(execution))

        Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await self.webView.callAsyncJavaScript(
                    """
                    document.getElementById("card").style.maxWidth = maximumWidth + "px"
                    return await window.renderMarkdown(markdown)
                    """,
                    arguments: [
                        "markdown": request.markdown,
                        "maximumWidth": request.widthPreset.cardMaximumWidth
                    ],
                    in: nil,
                    contentWorld: .page
                )
                guard self.recoveryState.isCurrent(execution) else { return }
                guard let measurement = value as? [String: Any],
                      let rawWidth = measurement["width"] as? NSNumber,
                      let rawHeight = measurement["height"] as? NSNumber else {
                    self.finish(execution, with: .failure(AppError.invalidRendererResponse))
                    return
                }

                let width = max(520, Int(ceil(rawWidth.doubleValue)))
                let height = max(80, Int(ceil(rawHeight.doubleValue)))
                guard width <= 1600, height <= 16_000 else {
                    self.finish(
                        execution,
                        with: .failure(AppError.contentTooLarge(width: width, height: height))
                    )
                    return
                }

                self.webView.setFrameSize(NSSize(width: width, height: height))
                self.hostWindow.setContentSize(NSSize(width: width, height: height))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.takeSnapshot(for: execution, width: width, height: height)
                }
            } catch {
                self.handle(error, for: execution)
            }
        }
    }

    private func takeSnapshot(
        for execution: RendererRecoveryState.Execution,
        width: Int,
        height: Int
    ) {
        guard recoveryState.renderDidStartSnapshot(execution) else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: width, height: height)

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let error {
                    self.handle(error, for: execution)
                } else if let image {
                    self.finish(execution, with: .success(image))
                } else {
                    self.finish(execution, with: .failure(AppError.pngEncodingFailed))
                }
            }
        }
    }

    private func finish(
        _ execution: RendererRecoveryState.Execution,
        with result: Result<NSImage, Error>
    ) {
        let transition = recoveryState.finish(execution)
        guard let requestID = transition.completedRequestID else { return }
        cancelWatchdog(for: .render(execution))
        requests.removeValue(forKey: requestID)?.completion(result)
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
            finish(execution, with: .failure(error))
        }
    }

    nonisolated static func isContentProcessTermination(_ error: Error) -> Bool {
        (error as? WKError)?.code == .webContentProcessTerminated
    }

    private func handleContentProcessTermination(
        from signal: RendererRecoveryState.TerminationSignal
    ) {
        switch recoveryState.contentProcessTerminated(from: signal) {
        case .ignored:
            return
        case let .handled(actions):
            cancelWatchdog()
            currentNavigation = nil
            perform(actions)
        }
    }

    private func loadRendererPage(_ attempt: RendererRecoveryState.LoadAttempt) {
        guard recoveryState.isCurrent(.load(attempt)) else { return }
        guard let pageURL else {
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

    private func rendererLoadFailed(_ navigation: WKNavigation?) {
        guard let loadAttempt = loadAttempt(for: navigation) else { return }
        currentNavigation = nil
        cancelWatchdog(for: .load(loadAttempt))
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
                    requests.removeValue(forKey: requestID)?.completion(.failure(error))
                }
            }
        }
    }
}
