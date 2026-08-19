import AppKit

enum RenderCornerStyle: String, Equatable {
    case square
    case rounded
}

struct RenderCornerPreference {
    static let defaultsKey = "Render.cornerStyle.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedStyle: RenderCornerStyle {
        guard let rawValue = defaults.string(forKey: Self.defaultsKey) else {
            return .square
        }
        return RenderCornerStyle(rawValue: rawValue) ?? .square
    }

    func select(_ style: RenderCornerStyle) {
        defaults.set(style.rawValue, forKey: Self.defaultsKey)
    }
}

enum RenderedImageStyler {
    static let roundedCornerRadius: CGFloat = 16

    @MainActor
    static func apply(
        _ style: RenderCornerStyle,
        to image: NSImage
    ) throws -> NSImage {
        guard style == .rounded else { return image }
        let pixelSize = RenderedImageExport.pixelSize(of: image)
        let pixelsWide = Int(pixelSize.width.rounded())
        let pixelsHigh = Int(pixelSize.height.rounded())
        guard pixelsWide > 0,
              pixelsHigh > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelsWide,
                  pixelsHigh: pixelsHigh,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw AppError.pngEncodingFailed
        }

        let bounds = NSRect(
            x: 0,
            y: 0,
            width: pixelsWide,
            height: pixelsHigh
        )
        let radius = min(
            roundedCornerRadius,
            min(bounds.width, bounds.height) / 2
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(bounds)
        NSBezierPath(
            roundedRect: bounds,
            xRadius: radius,
            yRadius: radius
        ).addClip()
        image.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        bitmap.size = image.size
        let styledImage = NSImage(size: image.size)
        styledImage.addRepresentation(bitmap)
        return styledImage
    }
}
