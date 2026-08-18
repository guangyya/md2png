import CoreFoundation
import Foundation

struct RendererSplitGeometryResponse: Equatable, Sendable {
    let geometry: RenderSplitGeometry

    init?(_ value: Any?) {
        guard let dictionary = value as? [String: Any],
              Set(dictionary.keys) == Set([
                  "contentHeight",
                  "preferredBreakOffsets",
                  "protectedRanges"
              ]),
              let rawContentHeight = dictionary["contentHeight"],
              let contentHeight = Self.integer(rawContentHeight, allowsZero: false),
              let rawBreakOffsets = dictionary["preferredBreakOffsets"] as? [Any],
              rawBreakOffsets.count <= 100_000,
              let rawProtectedRanges = dictionary["protectedRanges"] as? [Any],
              rawProtectedRanges.count <= 100_000 else {
            return nil
        }

        var breakOffsets: [Int] = []
        breakOffsets.reserveCapacity(rawBreakOffsets.count)
        for rawOffset in rawBreakOffsets {
            guard let offset = Self.integer(rawOffset, allowsZero: false) else {
                return nil
            }
            breakOffsets.append(offset)
        }

        var protectedRanges: [Range<Int>] = []
        protectedRanges.reserveCapacity(rawProtectedRanges.count)
        for rawRange in rawProtectedRanges {
            guard let bounds = rawRange as? [Any],
                  bounds.count == 2,
                  let lowerBound = Self.integer(bounds[0], allowsZero: true),
                  let upperBound = Self.integer(bounds[1], allowsZero: false) else {
                return nil
            }
            protectedRanges.append(lowerBound ..< upperBound)
        }

        guard let geometry = RenderSplitGeometry(
            contentHeight: contentHeight,
            preferredBreakOffsets: breakOffsets,
            protectedRanges: protectedRanges
        ) else {
            return nil
        }
        self.geometry = geometry
    }

    private static func integer(_ value: Any, allowsZero: Bool) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let doubleValue = number.doubleValue
        let minimum = allowsZero ? 0.0 : 1.0
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= minimum,
              doubleValue <= Double(RenderSplitGeometry.maximumContentHeight) else {
            return nil
        }
        return Int(doubleValue)
    }
}
