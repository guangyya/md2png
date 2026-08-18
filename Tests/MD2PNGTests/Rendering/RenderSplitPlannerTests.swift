import XCTest
@testable import MD2PNG

final class RenderSplitPlannerTests: XCTestCase {
    func testContentWithinLimitProducesOneCompleteSlice() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 900,
            preferredBreakOffsets: [300, 700],
            protectedRanges: []
        ))

        XCTAssertEqual(
            RenderSplitPlanner.slices(for: geometry, maximumSliceHeight: 1_000),
            [RenderSnapshotSlice(range: 0 ..< 900, ending: .contentEnd)]
        )
    }

    func testPlannerUsesLatestBlockBoundaryAndCoversContentExactly() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 2_500,
            preferredBreakOffsets: [400, 900, 1_400, 1_800, 2_300],
            protectedRanges: []
        ))

        let slices = RenderSplitPlanner.slices(
            for: geometry,
            maximumSliceHeight: 1_000
        )

        XCTAssertEqual(slices, [
            RenderSnapshotSlice(range: 0 ..< 900, ending: .preferredBoundary),
            RenderSnapshotSlice(range: 900 ..< 1_800, ending: .preferredBoundary),
            RenderSnapshotSlice(range: 1_800 ..< 2_500, ending: .contentEnd)
        ])
        XCTAssertEqual(slices.flatMap(\.range), Array(0 ..< 2_500))
        XCTAssertTrue(slices.allSatisfy { $0.height <= 1_000 })
    }

    func testProtectedCodeOrDiagramMovesIntactToNextSlice() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 2_200,
            preferredBreakOffsets: [400, 700, 1_500, 1_900],
            protectedRanges: [700 ..< 1_500]
        ))

        XCTAssertEqual(
            RenderSplitPlanner.slices(for: geometry, maximumSliceHeight: 1_000),
            [
                RenderSnapshotSlice(range: 0 ..< 700, ending: .preferredBoundary),
                RenderSnapshotSlice(range: 700 ..< 1_500, ending: .preferredBoundary),
                RenderSnapshotSlice(range: 1_500 ..< 2_200, ending: .contentEnd)
            ]
        )
    }

    func testTableRowRangeIsNotCutWhenItFitsOnAFreshSlice() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 1_900,
            preferredBreakOffsets: [300, 800, 1_100, 1_500],
            protectedRanges: [800 ..< 1_100]
        ))

        XCTAssertEqual(
            RenderSplitPlanner.slices(for: geometry, maximumSliceHeight: 1_000),
            [
                RenderSnapshotSlice(range: 0 ..< 800, ending: .preferredBoundary),
                RenderSnapshotSlice(range: 800 ..< 1_500, ending: .preferredBoundary),
                RenderSnapshotSlice(range: 1_500 ..< 1_900, ending: .contentEnd)
            ]
        )
    }

    func testOversizedProtectedBlockUsesHardLimitsWithoutTinyLeadingSlice() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 2_600,
            preferredBreakOffsets: [100, 2_300],
            protectedRanges: [100 ..< 2_300]
        ))

        XCTAssertEqual(
            RenderSplitPlanner.slices(for: geometry, maximumSliceHeight: 1_000),
            [
                RenderSnapshotSlice(range: 0 ..< 1_000, ending: .forcedLimit),
                RenderSnapshotSlice(range: 1_000 ..< 2_000, ending: .forcedLimit),
                RenderSnapshotSlice(range: 2_000 ..< 2_600, ending: .contentEnd)
            ]
        )
    }

    func testPlannerFallsBackToExactMaximumWhenNoBoundaryIsAvailable() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 2_100,
            preferredBreakOffsets: [],
            protectedRanges: []
        ))

        XCTAssertEqual(
            RenderSplitPlanner.slices(for: geometry, maximumSliceHeight: 1_000),
            [
                RenderSnapshotSlice(range: 0 ..< 1_000, ending: .forcedLimit),
                RenderSnapshotSlice(range: 1_000 ..< 2_000, ending: .forcedLimit),
                RenderSnapshotSlice(range: 2_000 ..< 2_100, ending: .contentEnd)
            ]
        )
    }

    func testGeometryNormalizesDuplicateBreaksAndOverlappingProtection() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 2_000,
            preferredBreakOffsets: [1_600, 1_500, 400, 400],
            protectedRanges: [
                900 ..< 1_200,
                1_100 ..< 1_500,
                1_500 ..< 1_600,
                100 ..< 200
            ]
        ))

        XCTAssertEqual(geometry.preferredBreakOffsets, [400, 1_500, 1_600])
        XCTAssertEqual(geometry.protectedRanges, [
            100 ..< 200,
            900 ..< 1_500,
            1_500 ..< 1_600
        ])
    }

    func testGeometryRejectsUntrustedOrInternallyInconsistentMetrics() {
        XCTAssertNil(RenderSplitGeometry(
            contentHeight: 0,
            preferredBreakOffsets: [],
            protectedRanges: []
        ))
        XCTAssertNil(RenderSplitGeometry(
            contentHeight: RenderSplitGeometry.maximumContentHeight + 1,
            preferredBreakOffsets: [],
            protectedRanges: []
        ))
        XCTAssertNil(RenderSplitGeometry(
            contentHeight: 1_000,
            preferredBreakOffsets: [0],
            protectedRanges: []
        ))
        XCTAssertNil(RenderSplitGeometry(
            contentHeight: 1_000,
            preferredBreakOffsets: [],
            protectedRanges: [900 ..< 1_100]
        ))
        XCTAssertNil(RenderSplitGeometry(
            contentHeight: 1_000,
            preferredBreakOffsets: [500],
            protectedRanges: [400 ..< 600]
        ))
    }

    func testNonpositiveSliceLimitFailsClosed() throws {
        let geometry = try XCTUnwrap(RenderSplitGeometry(
            contentHeight: 100,
            preferredBreakOffsets: [],
            protectedRanges: []
        ))

        XCTAssertEqual(
            RenderSplitPlanner.slices(for: geometry, maximumSliceHeight: 0),
            []
        )
    }
}
