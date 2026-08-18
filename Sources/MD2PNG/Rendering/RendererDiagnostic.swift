import CoreFoundation
import Foundation

enum RendererFailureKind: String, Equatable, Sendable {
    case mermaidSyntax = "mermaid_syntax"
    case mermaidDiagramType = "mermaid_diagram_type"
    case rendererResources = "renderer_resources"
    case invalidResponse = "invalid_response"
    case sizeLimit = "size_limit"
    case webKitRecovery = "webkit_recovery"
    case timeout
    case pngCreation = "png_creation"
    case unknown
}

struct RendererFailure: LocalizedError, CustomNSError, Equatable, Sendable {
    static let errorDomain = "md2png.renderer"

    let kind: RendererFailureKind
    let diagramNumber: Int?
    let sourceLine: Int?
    let width: Int?
    let height: Int?

    init(
        kind: RendererFailureKind,
        diagramNumber: Int? = nil,
        sourceLine: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.kind = kind
        self.diagramNumber = diagramNumber.flatMap { $0 > 0 ? $0 : nil }
        self.sourceLine = sourceLine.flatMap { $0 > 0 ? $0 : nil }
        self.width = width.flatMap { $0 > 0 ? $0 : nil }
        self.height = height.flatMap { $0 > 0 ? $0 : nil }
    }

    var errorDescription: String? {
        summary()
    }

    var errorCode: Int {
        switch kind {
        case .mermaidSyntax: 1
        case .mermaidDiagramType: 2
        case .rendererResources: 3
        case .invalidResponse: 4
        case .sizeLimit: 5
        case .webKitRecovery: 6
        case .timeout: 7
        case .pngCreation: 8
        case .unknown: 9
        }
    }

    var errorUserInfo: [String: Any] { [:] }

    var supportsSplitExportRecovery: Bool {
        guard kind == .sizeLimit, let width, let height else { return false }
        return width <= MarkdownRenderer.maximumSnapshotWidth
            && height > MarkdownRenderer.maximumSnapshotHeight
    }

    func summary(localizationBundle: Bundle? = nil) -> String {
        switch kind {
        case .mermaidSyntax, .mermaidDiagramType:
            if let diagramNumber, let sourceLine {
                return L10n.format(
                    "renderer_error.mermaid_diagram_line",
                    defaultValue: "Couldn’t render Mermaid diagram %1$ld near Markdown line %2$ld.",
                    bundle: localizationBundle,
                    diagramNumber,
                    sourceLine
                )
            }
            if let diagramNumber {
                return L10n.format(
                    "renderer_error.mermaid_diagram",
                    defaultValue: "Couldn’t render Mermaid diagram %ld.",
                    bundle: localizationBundle,
                    diagramNumber
                )
            }
            return L10n.text(
                "renderer_error.mermaid",
                defaultValue: "Couldn’t render a Mermaid diagram.",
                bundle: localizationBundle
            )
        case .rendererResources:
            return L10n.text(
                "renderer_error.resources",
                defaultValue: "The bundled renderer resources are unavailable.",
                bundle: localizationBundle
            )
        case .invalidResponse:
            return L10n.text(
                "renderer_error.invalid_response",
                defaultValue: "The renderer returned an invalid response.",
                bundle: localizationBundle
            )
        case .sizeLimit:
            if let width, let height {
                return L10n.format(
                    "renderer_error.size_limit_dimensions",
                    defaultValue: "The rendered image would be %1$ld × %2$ld, which exceeds the supported size.",
                    bundle: localizationBundle,
                    width,
                    height
                )
            }
            return L10n.text(
                "renderer_error.size_limit",
                defaultValue: "The rendered image exceeds the supported size.",
                bundle: localizationBundle
            )
        case .webKitRecovery:
            return L10n.text(
                "renderer_error.webkit_recovery",
                defaultValue: "The renderer process stopped and couldn’t recover.",
                bundle: localizationBundle
            )
        case .timeout:
            return L10n.text(
                "renderer_error.timeout",
                defaultValue: "The renderer took too long to finish.",
                bundle: localizationBundle
            )
        case .pngCreation:
            return L10n.text(
                "renderer_error.png_creation",
                defaultValue: "The rendered page couldn’t be converted to a PNG.",
                bundle: localizationBundle
            )
        case .unknown:
            return L10n.text(
                "renderer_error.unknown",
                defaultValue: "The Markdown couldn’t be rendered.",
                bundle: localizationBundle
            )
        }
    }

    func suggestion(localizationBundle: Bundle? = nil) -> String {
        switch kind {
        case .mermaidDiagramType:
            return L10n.text(
                "renderer_error.hint_mermaid_type",
                defaultValue: "Check the first line inside the Mermaid fence. It should begin with a supported type such as flowchart or sequenceDiagram.",
                bundle: localizationBundle
            )
        case .mermaidSyntax:
            return L10n.text(
                "renderer_error.hint_mermaid_syntax",
                defaultValue: "Check arrows, brackets, and labels near the reported line, and make sure the Mermaid fence is closed.",
                bundle: localizationBundle
            )
        case .rendererResources:
            return L10n.text(
                "renderer_error.hint_resources",
                defaultValue: "Reopen md2png and run Renderer Self-Test from About. Reinstall the app if the self-test still fails.",
                bundle: localizationBundle
            )
        case .invalidResponse, .pngCreation:
            return L10n.text(
                "renderer_error.hint_retry",
                defaultValue: "Try rendering again. If it still fails, run Renderer Self-Test and save diagnostic logs from About.",
                bundle: localizationBundle
            )
        case .sizeLimit:
            guard supportsSplitExportRecovery else {
                return L10n.text(
                    "renderer_error.hint_size_limit_shorten",
                    defaultValue: "Choose a narrower Output Width, shorten wide tables or diagrams, then try again.",
                    bundle: localizationBundle
                )
            }
            return L10n.text(
                "renderer_error.hint_size_limit",
                defaultValue: "Save the result as split PNGs, or shorten the Markdown and try again.",
                bundle: localizationBundle
            )
        case .webKitRecovery:
            return L10n.text(
                "renderer_error.hint_webkit_recovery",
                defaultValue: "Try again. If it repeats, reopen md2png and run Renderer Self-Test from About.",
                bundle: localizationBundle
            )
        case .timeout:
            return L10n.text(
                "renderer_error.hint_timeout",
                defaultValue: "Shorten complex Mermaid diagrams or Markdown, then try again.",
                bundle: localizationBundle
            )
        case .unknown:
            return L10n.text(
                "renderer_error.hint_unknown",
                defaultValue: "Check the Markdown and try again. If it repeats, run Renderer Self-Test and save diagnostic logs from About.",
                bundle: localizationBundle
            )
        }
    }

    static func from(_ error: any Error) -> RendererFailure {
        if let failure = error as? RendererFailure {
            return failure
        }
        guard let appError = error as? AppError else {
            return RendererFailure(kind: .unknown)
        }
        switch appError {
        case .rendererUnavailable:
            return RendererFailure(kind: .rendererResources)
        case .rendererRecoveryFailed:
            return RendererFailure(kind: .webKitRecovery)
        case .rendererTimedOut:
            return RendererFailure(kind: .timeout)
        case .rendererFailed:
            return RendererFailure(kind: .unknown)
        case .invalidRendererResponse:
            return RendererFailure(kind: .invalidResponse)
        case let .contentTooLarge(width, height):
            return RendererFailure(kind: .sizeLimit, width: width, height: height)
        case .rendererPNGEncodingFailed:
            return RendererFailure(kind: .pngCreation)
        default:
            return RendererFailure(kind: .unknown)
        }
    }
}

struct RendererErrorReport: LocalizedError, Equatable, Sendable {
    let failure: RendererFailure
    let operationID: DiagnosticOperationID

    var errorDescription: String? {
        failure.summary()
    }

    func copiedDetails(
        application: DiagnosticApplicationInfo = .current(),
        system: DiagnosticSystemInfo = .current,
        localizationBundle: Bundle? = nil
    ) -> String {
        var lines = [
            "md2png renderer diagnostics",
            "Issue: \(failure.kind.rawValue)",
            "Summary: \(failure.summary(localizationBundle: localizationBundle))"
        ]
        if let diagramNumber = failure.diagramNumber {
            lines.append("Mermaid diagram: \(diagramNumber)")
        }
        if let sourceLine = failure.sourceLine {
            lines.append("Markdown line: \(sourceLine)")
        }
        if let width = failure.width, let height = failure.height {
            lines.append("Dimensions: \(width)x\(height)")
        }
        lines.append(contentsOf: [
            "Operation ID: \(operationID.rawValue)",
            "App: \(application.name) \(application.version) (\(application.build))"
        ])
        if let sourceCommit = application.sourceCommit {
            lines.append("Commit: \(sourceCommit)")
        }
        lines.append(contentsOf: [
            "Configuration: \(application.configuration)",
            "macOS: \(system.macOSVersion)",
            "Architecture: \(system.architecture)",
            "Markdown included: no",
            "Raw error included: no"
        ])
        return lines.joined(separator: "\n")
    }
}

enum RendererJavaScriptResponse: Equatable {
    case success(width: Double, height: Double)
    case failure(RendererFailure)

    init?(_ value: Any?) {
        guard let dictionary = value as? [String: Any],
              let rawOK = dictionary["ok"],
              let ok = Self.boolean(rawOK) else {
            return nil
        }
        if ok {
            guard Set(dictionary.keys) == Set(["ok", "width", "height"]),
                  let rawWidth = dictionary["width"],
                  let rawHeight = dictionary["height"],
                  let width = Self.boundedPositiveDouble(rawWidth),
                  let height = Self.boundedPositiveDouble(rawHeight) else {
                return nil
            }
            self = .success(width: width, height: height)
            return
        }

        let allowedKeys = Set(["ok", "kind", "diagramNumber", "sourceLine"])
        guard Set(dictionary.keys).isSubset(of: allowedKeys),
              let rawKind = dictionary["kind"] as? String,
              let kind = RendererFailureKind(rawValue: rawKind),
              kind == .mermaidSyntax || kind == .mermaidDiagramType,
              let rawDiagramNumber = dictionary["diagramNumber"],
              let diagramNumber = Self.positiveInteger(rawDiagramNumber) else {
            return nil
        }
        let sourceLine: Int?
        if let rawSourceLine = dictionary["sourceLine"] {
            guard let parsedSourceLine = Self.positiveInteger(rawSourceLine) else {
                return nil
            }
            sourceLine = parsedSourceLine
        } else {
            sourceLine = nil
        }
        self = .failure(RendererFailure(
            kind: kind,
            diagramNumber: diagramNumber,
            sourceLine: sourceLine
        ))
    }

    private static func positiveInteger(_ value: Any) -> Int? {
        guard let doubleValue = boundedPositiveDouble(value),
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= 1,
              doubleValue <= 1_000_000 else {
            return nil
        }
        return Int(doubleValue)
    }

    private static func boundedPositiveDouble(_ value: Any) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue > 0,
              doubleValue <= 1_000_000 else {
            return nil
        }
        return doubleValue
    }

    private static func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }
}
