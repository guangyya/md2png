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
    private static let minimumRoundedCornerRadius: CGFloat = 24
    private static let maximumRoundedCornerRadius: CGFloat = 48
    private static let roundedCornerWidthRatio: CGFloat = 0.03

    static func roundedCornerRadius(for pixelSize: NSSize) -> CGFloat {
        let proportionalRadius = pixelSize.width * roundedCornerWidthRatio
        let preferredRadius = min(
            max(proportionalRadius, minimumRoundedCornerRadius),
            maximumRoundedCornerRadius
        )
        return min(
            preferredRadius,
            min(pixelSize.width, pixelSize.height) / 2
        )
    }

    @MainActor
    static func hasTransparentCorners(_ image: NSImage) -> Bool {
        guard let bitmap = highestBitmapRepresentation(of: image),
              bitmap.hasAlpha,
              !bitmap.isPlanar,
              bitmap.samplesPerPixel > 1 else { return false }
        let alphaIndex = bitmap.bitmapFormat.contains(.alphaFirst)
            ? 0
            : bitmap.samplesPerPixel - 1
        var samples = [Int](repeating: 0, count: bitmap.samplesPerPixel)
        let corners = [
            (0, 0),
            (bitmap.pixelsWide - 1, 0),
            (0, bitmap.pixelsHigh - 1),
            (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)
        ]
        return corners.allSatisfy { x, y in
            bitmap.getPixel(&samples, atX: x, y: y)
            return samples[alphaIndex] == 0
        }
    }

    @MainActor
    static func apply(
        _ style: RenderCornerStyle,
        to image: NSImage
    ) throws -> NSImage {
        guard style == .rounded else { return image }
        guard let bitmap = mutableBitmapPreservingPixels(from: image),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            throw AppError.pngEncodingFailed
        }

        let radius = roundedCornerRadius(for: NSSize(
            width: bitmap.pixelsWide,
            height: bitmap.pixelsHigh
        ))
        applyRoundedAlphaMask(to: bitmap, radius: radius)

        bitmap.size = image.size
        let styledImage = NSImage(size: image.size)
        styledImage.addRepresentation(bitmap)
        return styledImage
    }

    private static func mutableBitmapPreservingPixels(
        from image: NSImage
    ) -> NSBitmapImageRep? {
        let source = highestBitmapRepresentation(of: image)
        if let source,
           source.hasAlpha,
           !source.isPlanar,
           let copy = source.copy() as? NSBitmapImageRep {
            return copy
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let sourceImage = source?.cgImage
            ?? image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            ) else { return nil }
        let colorSpace = sourceImage.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: sourceImage.width,
            height: sourceImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        )
        guard let copiedImage = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: copiedImage)
    }

    private static func highestBitmapRepresentation(
        of image: NSImage
    ) -> NSBitmapImageRep? {
        image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: {
                $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
            })
    }

    private static func applyRoundedAlphaMask(
        to bitmap: NSBitmapImageRep,
        radius: CGFloat
    ) {
        let cornerExtent = Int(ceil(radius))
        let alphaIndex = bitmap.bitmapFormat.contains(.alphaFirst)
            ? 0
            : bitmap.samplesPerPixel - 1
        let maximumSample = (1 << bitmap.bitsPerSample) - 1
        var samples = [Int](repeating: 0, count: bitmap.samplesPerPixel)

        for yOffset in 0 ..< cornerExtent {
            for xOffset in 0 ..< cornerExtent {
                let distance = hypot(
                    radius - CGFloat(xOffset) - 0.5,
                    radius - CGFloat(yOffset) - 0.5
                )
                let coverage = min(max(radius + 0.5 - distance, 0), 1)
                guard coverage < 1 else { continue }

                let coordinates = [
                    (xOffset, yOffset),
                    (bitmap.pixelsWide - 1 - xOffset, yOffset),
                    (xOffset, bitmap.pixelsHigh - 1 - yOffset),
                    (bitmap.pixelsWide - 1 - xOffset, bitmap.pixelsHigh - 1 - yOffset)
                ]
                for (x, y) in coordinates {
                    bitmap.getPixel(&samples, atX: x, y: y)
                    if !bitmap.bitmapFormat.contains(.alphaNonpremultiplied) {
                        for index in samples.indices where index != alphaIndex {
                            samples[index] = Int(
                                (CGFloat(samples[index]) * coverage).rounded()
                            )
                        }
                    }
                    let existingAlpha = min(max(samples[alphaIndex], 0), maximumSample)
                    samples[alphaIndex] = Int(
                        (CGFloat(existingAlpha) * coverage).rounded()
                    )
                    bitmap.setPixel(&samples, atX: x, y: y)
                }
            }
        }
    }
}
