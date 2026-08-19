import AppKit
import WebKit

@MainActor
final class RendererWebViewLifecycle: NSObject, WKNavigationDelegate {
    enum Event {
        case loaded(RendererRecoveryState.LoadAttempt)
        case loadFailed(RendererRecoveryState.LoadAttempt, Error)
        case contentProcessTerminated(rendererGenerationID: UUID)
    }

    private struct NavigationAttempt {
        let navigation: WKNavigation
        let loadAttempt: RendererRecoveryState.LoadAttempt
    }

    private let pageURL: URL?
    private let hostWindow: NSWindow
    private let onEvent: (Event) -> Void
    private var currentNavigation: NavigationAttempt?
    private(set) var webView: WKWebView
    private(set) var rendererGenerationID: UUID?

    init(
        pageURL: URL?,
        initialRendererGenerationID: UUID?,
        onEvent: @escaping (Event) -> Void
    ) {
        self.pageURL = pageURL
        self.onEvent = onEvent
        rendererGenerationID = initialRendererGenerationID
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
    }

    isolated deinit {
        webView.navigationDelegate = nil
        hostWindow.orderOut(nil)
    }

    func prepareRenderer(for attempt: RendererRecoveryState.LoadAttempt) -> Bool {
        guard pageURL != nil else { return false }
        installWebView(for: attempt)
        return true
    }

    func loadRendererPage(for attempt: RendererRecoveryState.LoadAttempt) -> Bool {
        guard let pageURL, rendererGenerationID == attempt.id else { return false }
        guard let navigation = webView.loadFileURL(
            pageURL,
            allowingReadAccessTo: pageURL.deletingLastPathComponent()
        ) else {
            return false
        }
        currentNavigation = NavigationAttempt(
            navigation: navigation,
            loadAttempt: attempt
        )
        return true
    }

    func cancelLoad(_ attempt: RendererRecoveryState.LoadAttempt) {
        guard currentNavigation?.loadAttempt == attempt else { return }
        currentNavigation = nil
    }

    func setContentSize(_ size: NSSize) {
        webView.setFrameSize(size)
        hostWindow.setContentSize(size)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView,
              let loadAttempt = loadAttempt(for: navigation) else {
            return
        }
        currentNavigation = nil
        onEvent(.loaded(loadAttempt))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        loadFailed(in: webView, navigation: navigation, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadFailed(in: webView, navigation: navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, let rendererGenerationID else { return }
        currentNavigation = nil
        onEvent(.contentProcessTerminated(
            rendererGenerationID: rendererGenerationID
        ))
    }

#if DEBUG
    var webViewIdentityForTesting: ObjectIdentifier {
        ObjectIdentifier(webView)
    }

    func simulateContentProcessTerminationForTesting() {
        webViewWebContentProcessDidTerminate(webView)
    }
#endif

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

    private func installWebView(for attempt: RendererRecoveryState.LoadAttempt) {
        guard rendererGenerationID != attempt.id else { return }
        currentNavigation = nil
        webView.navigationDelegate = nil
        let nextWebView = Self.makeWebView()
        nextWebView.navigationDelegate = self
        hostWindow.contentView = nextWebView
        webView = nextWebView
        rendererGenerationID = attempt.id
    }

    private func loadFailed(
        in webView: WKWebView,
        navigation: WKNavigation?,
        error: Error
    ) {
        guard webView === self.webView,
              let loadAttempt = loadAttempt(for: navigation) else {
            return
        }
        currentNavigation = nil
        onEvent(.loadFailed(loadAttempt, error))
    }

    private func loadAttempt(
        for navigation: WKNavigation?
    ) -> RendererRecoveryState.LoadAttempt? {
        guard let navigation, let currentNavigation,
              navigation === currentNavigation.navigation else {
            return nil
        }
        return currentNavigation.loadAttempt
    }
}
