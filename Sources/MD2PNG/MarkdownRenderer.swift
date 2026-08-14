import AppKit
import WebKit

@MainActor
final class MarkdownRenderer: NSObject, WKNavigationDelegate {
    typealias Completion = (Result<NSImage, Error>) -> Void

    private struct Request {
        let id: UUID
        let markdown: String
        let completion: Completion
    }

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private let pageURL: URL?
    private var requests: [UUID: Request] = [:]
    private var recoveryState: RendererRecoveryState
    private var currentNavigation: WKNavigation?

    init(pageURL: URL? = RendererResources.pageURL) {
        self.pageURL = pageURL
        recoveryState = RendererRecoveryState(hasRendererPage: pageURL != nil)
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            configuration: configuration
        )
        hostWindow = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1200, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        hostWindow.contentView = webView
        hostWindow.orderBack(nil)
        webView.navigationDelegate = self

        if pageURL != nil {
            loadRendererPage()
        }
    }

    func render(_ markdown: String, completion: @escaping Completion) {
        let request = Request(id: UUID(), markdown: markdown, completion: completion)
        requests[request.id] = request
        perform(recoveryState.enqueue(request.id))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isCurrentNavigation(navigation) else { return }
        currentNavigation = nil
        perform(recoveryState.rendererDidLoad())
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        rendererLoadFailed(navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        rendererLoadFailed(navigation)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        currentNavigation = nil
        perform(recoveryState.contentProcessTerminated())
    }

#if DEBUG
    func simulateContentProcessTerminationForTesting() {
        webViewWebContentProcessDidTerminate(webView)
    }
#endif

    private func start(_ execution: RendererRecoveryState.Execution) {
        guard let request = requests[execution.requestID] else {
            finish(execution, with: .failure(AppError.rendererUnavailable))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await self.webView.callAsyncJavaScript(
                    "return await window.renderMarkdown(markdown)",
                    arguments: ["markdown": request.markdown],
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
                self.finish(execution, with: .failure(error))
            }
        }
    }

    private func takeSnapshot(
        for execution: RendererRecoveryState.Execution,
        width: Int,
        height: Int
    ) {
        guard recoveryState.isCurrent(execution) else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: width, height: height)

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let error {
                    self.finish(execution, with: .failure(error))
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
        requests.removeValue(forKey: requestID)?.completion(result)
        perform(transition.actions)
    }

    private func loadRendererPage() {
        guard let pageURL else {
            perform(recoveryState.rendererLoadFailed())
            return
        }
        currentNavigation = webView.loadFileURL(
            pageURL,
            allowingReadAccessTo: pageURL.deletingLastPathComponent()
        )
        if currentNavigation == nil {
            perform(recoveryState.rendererLoadFailed())
        }
    }

    private func rendererLoadFailed(_ navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        currentNavigation = nil
        perform(recoveryState.rendererLoadFailed())
    }

    private func isCurrentNavigation(_ navigation: WKNavigation?) -> Bool {
        guard let navigation, let currentNavigation else { return false }
        return navigation === currentNavigation
    }

    private func perform(_ actions: [RendererRecoveryState.Action]) {
        for action in actions {
            switch action {
            case .loadRenderer:
                loadRendererPage()
            case let .start(execution):
                start(execution)
            case let .fail(requestIDs, failure):
                let error: AppError = switch failure {
                case .rendererUnavailable:
                    .rendererUnavailable
                case .recoveryFailed:
                    .rendererRecoveryFailed
                }
                for requestID in requestIDs {
                    requests.removeValue(forKey: requestID)?.completion(.failure(error))
                }
            }
        }
    }
}
