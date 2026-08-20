import AppKit
import XCTest
@testable import MD2PNG

final class ApplicationTerminationCoordinatorTests: XCTestCase {
    @MainActor
    func testPendingUpdateInstallTerminatesWithoutCancellingPreparedInstall() {
        var cancellationCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            dependencies: .init(
                isUpdateInstallPending: { true },
                cancelPreparedInstallation: { _ in
                    cancellationCount += 1
                    return true
                }
            )
        )

        let reply = coordinator.shouldTerminate {
            XCTFail("An accepted update install must not defer termination")
        }

        XCTAssertEqual(reply, .terminateNow)
        XCTAssertEqual(cancellationCount, 0)
    }

    @MainActor
    func testSynchronousCancellationTerminatesWithoutADeferredReply() {
        let coordinator = ApplicationTerminationCoordinator(
            dependencies: .init(
                isUpdateInstallPending: { false },
                cancelPreparedInstallation: { _ in false }
            )
        )

        let reply = coordinator.shouldTerminate {
            XCTFail("A synchronous cancellation must not send a deferred reply")
        }

        XCTAssertEqual(reply, .terminateNow)
    }

    @MainActor
    func testPreparedInstallDefersOneTerminationRequestUntilCancellationFinishes() async {
        var cancellationCount = 0
        var cancellationCompletion: (@MainActor () -> Void)?
        let coordinator = ApplicationTerminationCoordinator(
            dependencies: .init(
                isUpdateInstallPending: { false },
                cancelPreparedInstallation: { completion in
                    cancellationCount += 1
                    cancellationCompletion = completion
                    return true
                }
            )
        )
        let replied = expectation(description: "deferred termination replied")

        XCTAssertEqual(coordinator.shouldTerminate { replied.fulfill() }, .terminateLater)
        XCTAssertEqual(coordinator.shouldTerminate {
            XCTFail("A repeated request must share the existing deferral")
        }, .terminateLater)
        XCTAssertEqual(cancellationCount, 1)

        cancellationCompletion?()
        await fulfillment(of: [replied], timeout: 1)
    }
}
