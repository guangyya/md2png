import AppKit
import WebKit

@MainActor
final class MarkdownRenderer: NSObject, WKNavigationDelegate {
    typealias Completion = (Result<NSImage, Error>) -> Void

    private struct Request {
        let markdown: String
        let completion: Completion
    }

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var isReady = false
    private var isRendering = false
    private var requests: [Request] = []
    private var initializationError: Error?

    override init() {
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

        guard let pageURL = RendererResources.pageURL else {
            initializationError = AppError.rendererUnavailable
            return
        }
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    func render(_ markdown: String, completion: @escaping Completion) {
        if let initializationError {
            completion(.failure(initializationError))
            return
        }
        requests.append(Request(markdown: markdown, completion: completion))
        processNextIfPossible()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        processNextIfPossible()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failPendingRequests(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failPendingRequests(with: error)
    }

    private func processNextIfPossible() {
        guard isReady, !isRendering, !requests.isEmpty else { return }
        isRendering = true
        let request = requests.removeFirst()

        Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await self.webView.callAsyncJavaScript(
                    "return await window.renderMarkdown(markdown)",
                    arguments: ["markdown": request.markdown],
                    in: nil,
                    contentWorld: .page
                )
                guard let measurement = value as? [String: Any],
                      let rawWidth = measurement["width"] as? NSNumber,
                      let rawHeight = measurement["height"] as? NSNumber else {
                    self.finish(request, with: .failure(AppError.invalidRendererResponse))
                    return
                }

                let width = max(520, Int(ceil(rawWidth.doubleValue)))
                let height = max(80, Int(ceil(rawHeight.doubleValue)))
                guard width <= 1600, height <= 16_000 else {
                    self.finish(request, with: .failure(AppError.contentTooLarge(width: width, height: height)))
                    return
                }

                self.webView.setFrameSize(NSSize(width: width, height: height))
                self.hostWindow.setContentSize(NSSize(width: width, height: height))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.takeSnapshot(for: request, width: width, height: height)
                }
            } catch {
                self.finish(request, with: .failure(error))
            }
        }
    }

    private func takeSnapshot(for request: Request, width: Int, height: Int) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: width, height: height)

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let error {
                    self.finish(request, with: .failure(error))
                } else if let image {
                    self.finish(request, with: .success(image))
                } else {
                    self.finish(request, with: .failure(AppError.pngEncodingFailed))
                }
            }
        }
    }

    private func finish(_ request: Request, with result: Result<NSImage, Error>) {
        isRendering = false
        request.completion(result)
        processNextIfPossible()
    }

    private func failPendingRequests(with error: Error) {
        isReady = false
        isRendering = false
        let pending = requests
        requests.removeAll()
        pending.forEach { $0.completion(.failure(error)) }
    }
}
