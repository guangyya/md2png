import AppKit
import Foundation

enum PackagedRenderSelfTestResources {
    static let markdownFileName = "renderer-self-test.md"

    static func markdownURL(resourcesURL: URL?) -> URL? {
        guard let resourcesURL else { return nil }
        let url = resourcesURL
            .appendingPathComponent("Examples", isDirectory: true)
            .appendingPathComponent(markdownFileName)
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    static func validate(markdown: String) -> Bool {
        let requiredFragments = [
            "# Packaged renderer self-test",
            "| Capability | Result |",
            "```swift",
            "```mermaid",
            "flowchart LR"
        ]
        return requiredFragments.allSatisfy(markdown.contains)
    }
}

struct PackagedRenderSelfTestReport: Equatable {
    let width: Int
    let height: Int
    let pngByteCount: Int
}

enum PackagedRenderSelfTestFailure: Error, Equatable {
    case notPackagedApplication
    case rendererResourcesUnavailable
    case markdownResourceUnavailable
    case invalidMarkdownResource
    case renderingFailed
    case invalidImage
    case timedOut

    var exitCode: Int32 {
        switch self {
        case .notPackagedApplication, .rendererResourcesUnavailable,
             .markdownResourceUnavailable:
            return 2
        case .invalidMarkdownResource:
            return 3
        case .renderingFailed:
            return 4
        case .invalidImage:
            return 5
        case .timedOut:
            return 6
        }
    }

    var summary: String {
        switch self {
        case .notPackagedApplication:
            return "executable is not running from an app bundle"
        case .rendererResourcesUnavailable:
            return "packaged renderer resources are unavailable"
        case .markdownResourceUnavailable:
            return "packaged self-test Markdown is unavailable"
        case .invalidMarkdownResource:
            return "packaged self-test Markdown is incomplete"
        case .renderingFailed:
            return "packaged renderer failed"
        case .invalidImage:
            return "renderer produced an invalid or empty image"
        case .timedOut:
            return "packaged renderer timed out"
        }
    }
}

enum PackagedRenderSelfTestImageValidator {
    static func validate(_ image: NSImage) -> PackagedRenderSelfTestReport? {
        let pointWidth = Int(image.size.width.rounded())
        let pointHeight = Int(image.size.height.rounded())
        guard (520...1_600).contains(pointWidth),
              (180...16_000).contains(pointHeight),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide >= pointWidth,
              bitmap.pixelsHigh >= pointHeight,
              let png = bitmap.representation(using: .png, properties: [:]),
              png.count >= 1_024,
              containsVisibleContent(bitmap) else {
            return nil
        }

        return PackagedRenderSelfTestReport(
            width: bitmap.pixelsWide,
            height: bitmap.pixelsHigh,
            pngByteCount: png.count
        )
    }

    private static func containsVisibleContent(_ bitmap: NSBitmapImageRep) -> Bool {
        var nonWhiteSamples = 0
        let xStride = max(1, bitmap.pixelsWide / 160)
        let yStride = max(1, bitmap.pixelsHigh / 160)

        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStride) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStride) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.alphaComponent > 0.1,
                   color.redComponent < 0.96 ||
                   color.greenComponent < 0.96 ||
                   color.blueComponent < 0.96 {
                    nonWhiteSamples += 1
                    if nonWhiteSamples >= 20 { return true }
                }
            }
        }
        return false
    }
}

@MainActor
final class PackagedRenderSelfTest {
    typealias Completion = (Result<PackagedRenderSelfTestReport, PackagedRenderSelfTestFailure>) -> Void

    private var renderer: MarkdownRenderer?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didFinish = false

    func run(
        bundle: Bundle = .main,
        timeout: TimeInterval = 20,
        completion: @escaping Completion
    ) {
        guard bundle.bundleURL.pathExtension == "app" else {
            completion(.failure(.notPackagedApplication))
            return
        }
        guard let pageURL = RendererResources.packagedPageURL(
            resourcesURL: bundle.resourceURL
        ) else {
            completion(.failure(.rendererResourcesUnavailable))
            return
        }
        guard let markdownURL = PackagedRenderSelfTestResources.markdownURL(
            resourcesURL: bundle.resourceURL
        ), let markdown = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            completion(.failure(.markdownResourceUnavailable))
            return
        }
        guard PackagedRenderSelfTestResources.validate(markdown: markdown) else {
            completion(.failure(.invalidMarkdownResource))
            return
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(.timedOut), completion: completion)
        }
        self.timeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        let renderer = MarkdownRenderer(pageURL: pageURL)
        self.renderer = renderer
        renderer.render(markdown) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(image):
                guard let report = PackagedRenderSelfTestImageValidator.validate(image) else {
                    self.finish(.failure(.invalidImage), completion: completion)
                    return
                }
                self.finish(.success(report), completion: completion)
            case .failure:
                self.finish(.failure(.renderingFailed), completion: completion)
            }
        }
    }

    private func finish(
        _ result: Result<PackagedRenderSelfTestReport, PackagedRenderSelfTestFailure>,
        completion: Completion
    ) {
        guard !didFinish else { return }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        renderer = nil
        completion(result)
    }
}

@MainActor
final class PackagedRenderSelfTestApplicationDelegate: NSObject, NSApplicationDelegate {
    private let selfTest = PackagedRenderSelfTest()
    private(set) var exitCode: Int32 = 70

    func applicationDidFinishLaunching(_ notification: Notification) {
        selfTest.run { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(report):
                print(
                    "Packaged renderer self-test passed " +
                    "(\(report.width)x\(report.height), \(report.pngByteCount) PNG bytes)"
                )
                self.exitCode = 0
            case let .failure(failure):
                FileHandle.standardError.write(
                    Data("Packaged renderer self-test failed: \(failure.summary)\n".utf8)
                )
                self.exitCode = failure.exitCode
            }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
}
