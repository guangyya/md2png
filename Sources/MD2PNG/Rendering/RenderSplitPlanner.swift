import Foundation

struct RenderSplitGeometry: Equatable, Sendable {
    static let maximumContentHeight = 1_000_000

    let contentHeight: Int
    let preferredBreakOffsets: [Int]
    let protectedRanges: [Range<Int>]

    init?(
        contentHeight: Int,
        preferredBreakOffsets: [Int],
        protectedRanges: [Range<Int>]
    ) {
        guard (1 ... Self.maximumContentHeight).contains(contentHeight),
              preferredBreakOffsets.allSatisfy({ (1 ..< contentHeight).contains($0) }),
              protectedRanges.allSatisfy({ range in
                  range.lowerBound >= 0
                    && range.lowerBound < range.upperBound
                    && range.upperBound <= contentHeight
              }) else {
            return nil
        }

        let normalizedRanges = Self.merge(protectedRanges)
        let normalizedBreaks = Array(Set(preferredBreakOffsets)).sorted()
        guard normalizedBreaks.allSatisfy({ offset in
            !normalizedRanges.contains(where: { range in
                range.lowerBound < offset && offset < range.upperBound
            })
        }) else {
            return nil
        }

        self.contentHeight = contentHeight
        self.preferredBreakOffsets = normalizedBreaks
        self.protectedRanges = normalizedRanges
    }

    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.sorted {
            if $0.lowerBound == $1.lowerBound {
                return $0.upperBound < $1.upperBound
            }
            return $0.lowerBound < $1.lowerBound
        }
        var merged: [Range<Int>] = []
        for range in sorted {
            guard let previous = merged.last,
                  range.lowerBound < previous.upperBound else {
                merged.append(range)
                continue
            }
            merged[merged.count - 1] = previous.lowerBound ..< max(
                previous.upperBound,
                range.upperBound
            )
        }
        return merged
    }
}

struct RenderSnapshotSlice: Equatable, Sendable {
    enum Ending: Equatable, Sendable {
        case preferredBoundary
        case forcedLimit
        case contentEnd
    }

    let range: Range<Int>
    let ending: Ending

    var y: Int { range.lowerBound }
    var height: Int { range.count }
}

enum RenderSplitPlanner {
    static func slices(
        for geometry: RenderSplitGeometry,
        maximumSliceHeight: Int
    ) -> [RenderSnapshotSlice] {
        guard maximumSliceHeight > 0 else { return [] }

        var result: [RenderSnapshotSlice] = []
        var start = 0
        while start < geometry.contentHeight {
            let remainingHeight = geometry.contentHeight - start
            guard remainingHeight > maximumSliceHeight else {
                result.append(RenderSnapshotSlice(
                    range: start ..< geometry.contentHeight,
                    ending: .contentEnd
                ))
                break
            }

            let hardLimit = start + maximumSliceHeight
            let end: Int
            let ending: RenderSnapshotSlice.Ending
            if let protectedRange = geometry.protectedRanges.first(where: {
                $0.lowerBound < hardLimit && hardLimit < $0.upperBound
            }) {
                if protectedRange.count <= maximumSliceHeight,
                   protectedRange.lowerBound > start {
                    end = protectedRange.lowerBound
                    ending = .preferredBoundary
                } else {
                    end = hardLimit
                    ending = .forcedLimit
                }
            } else if let preferredBreak = geometry.preferredBreakOffsets.last(where: {
                start < $0 && $0 <= hardLimit
            }) {
                end = preferredBreak
                ending = .preferredBoundary
            } else {
                end = hardLimit
                ending = .forcedLimit
            }

            result.append(RenderSnapshotSlice(
                range: start ..< end,
                ending: ending
            ))
            start = end
        }
        return result
    }
}
