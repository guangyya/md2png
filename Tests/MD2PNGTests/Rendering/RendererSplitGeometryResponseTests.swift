import XCTest
@testable import MD2PNG

final class RendererSplitGeometryResponseTests: XCTestCase {
    func testResponseAcceptsBoundedGeometryAndNormalizesOrdering() throws {
        let response = try XCTUnwrap(RendererSplitGeometryResponse([
            "contentHeight": 2_000,
            "preferredBreakOffsets": [1_600, 400, 400],
            "protectedRanges": [
                [900, 1_200],
                [1_100, 1_500]
            ]
        ]))

        XCTAssertEqual(response.geometry, RenderSplitGeometry(
            contentHeight: 2_000,
            preferredBreakOffsets: [400, 1_600],
            protectedRanges: [900 ..< 1_500]
        ))
    }

    func testResponseRejectsMalformedOrUntrustedGeometry() {
        XCTAssertNil(RendererSplitGeometryResponse(nil))
        XCTAssertNil(RendererSplitGeometryResponse([
            "contentHeight": 2_000,
            "preferredBreakOffsets": [],
            "protectedRanges": [],
            "message": "private renderer detail"
        ]))
        XCTAssertNil(RendererSplitGeometryResponse([
            "contentHeight": true,
            "preferredBreakOffsets": [],
            "protectedRanges": []
        ]))
        XCTAssertNil(RendererSplitGeometryResponse([
            "contentHeight": 2_000,
            "preferredBreakOffsets": [400.5],
            "protectedRanges": []
        ]))
        XCTAssertNil(RendererSplitGeometryResponse([
            "contentHeight": 2_000,
            "preferredBreakOffsets": [1_000],
            "protectedRanges": [[900, 1_100]]
        ]))
        XCTAssertNil(RendererSplitGeometryResponse([
            "contentHeight": 2_000,
            "preferredBreakOffsets": [],
            "protectedRanges": [[100], [300, 400]]
        ]))
        XCTAssertNil(RendererSplitGeometryResponse([
            "contentHeight": RenderSplitGeometry.maximumContentHeight + 1,
            "preferredBreakOffsets": [],
            "protectedRanges": []
        ]))
    }
}
