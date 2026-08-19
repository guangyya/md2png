import AppKit

enum PreviewZoomMode: Equatable {
    case fit
    case actualSize
    case custom(CGFloat)
}

struct PreviewLayout {
    let canvasSize: NSSize
    let imageFrame: NSRect
    let zoomFactor: CGFloat

    static let minimumZoomFactor: CGFloat = 0.25
    static let maximumZoomFactor: CGFloat = 4

    static func calculate(
        imagePixelSize: NSSize,
        backingScaleFactor: CGFloat,
        viewportSize: NSSize,
        zoomMode: PreviewZoomMode,
        padding: CGFloat = 24
    ) -> PreviewLayout {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return PreviewLayout(canvasSize: viewportSize, imageFrame: .zero, zoomFactor: 1)
        }

        let safeBackingScale = max(1, backingScaleFactor)
        let actualSize = NSSize(
            width: imagePixelSize.width / safeBackingScale,
            height: imagePixelSize.height / safeBackingScale
        )
        let availableWidth = max(1, viewportSize.width - padding * 2)
        let fitFactor = min(maximumZoomFactor, availableWidth / actualSize.width)
        let zoomFactor = switch zoomMode {
        case .fit:
            fitFactor
        case .actualSize:
            CGFloat(1)
        case let .custom(factor):
            min(max(factor, minimumZoomFactor), maximumZoomFactor)
        }
        let displayedSize = NSSize(
            width: actualSize.width * zoomFactor,
            height: actualSize.height * zoomFactor
        )
        let canvasSize = NSSize(
            width: max(viewportSize.width, displayedSize.width + padding * 2),
            height: max(viewportSize.height, displayedSize.height + padding * 2)
        )
        let imageOrigin = NSPoint(
            x: canvasSize.width > viewportSize.width
                ? padding
                : (canvasSize.width - displayedSize.width) / 2,
            y: canvasSize.height > viewportSize.height
                ? padding
                : (canvasSize.height - displayedSize.height) / 2
        )
        return PreviewLayout(
            canvasSize: canvasSize,
            imageFrame: NSRect(origin: imageOrigin, size: displayedSize),
            zoomFactor: zoomFactor
        )
    }

    static func calculate(
        imageSize: NSSize,
        viewportSize: NSSize,
        padding: CGFloat = 24
    ) -> PreviewLayout {
        calculate(
            imagePixelSize: imageSize,
            backingScaleFactor: 1,
            viewportSize: viewportSize,
            zoomMode: .fit,
            padding: padding
        )
    }
}

struct PreviewWindowLayout {
    let contentSize: NSSize

    static func calculate(
        imageSize: NSSize,
        visibleScreenSize: NSSize,
        horizontalImagePadding: CGFloat = 48,
        horizontalScreenMargin: CGFloat = 80,
        verticalScreenMargin: CGFloat = 120,
        minimumContentWidth: CGFloat = 520,
        preferredContentHeight: CGFloat = 640
    ) -> PreviewWindowLayout {
        let maximumContentWidth = max(
            1,
            visibleScreenSize.width - horizontalScreenMargin
        )
        let minimumWidth = min(minimumContentWidth, maximumContentWidth)
        let desiredWidth = max(
            minimumWidth,
            imageSize.width + horizontalImagePadding
        )
        let maximumContentHeight = max(
            1,
            visibleScreenSize.height - verticalScreenMargin
        )
        return PreviewWindowLayout(contentSize: NSSize(
            width: min(desiredWidth, maximumContentWidth),
            height: min(preferredContentHeight, maximumContentHeight)
        ))
    }
}
