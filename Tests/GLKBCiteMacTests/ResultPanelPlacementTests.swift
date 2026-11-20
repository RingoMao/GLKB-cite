import AppKit
import XCTest
@testable import GLKBCiteMac

final class ResultPanelPlacementTests: XCTestCase {
    @MainActor
    func testFirstPanelRemainsCenteredAsResultsArriveOnSecondaryScreen() {
        let screen = CGRect(x: -1440, y: 25, width: 1440, height: 850)
        for height in [180, 560] {
            let size = CGSize(width: 380, height: height)
            let origin = ResultPanelController.constrainedOrigin(topLeft: .zero, size: size, visible: screen, centered: true)
            let frame = CGRect(origin: origin, size: size)
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertEqual(frame.midY, screen.midY)
            XCTAssertTrue(screen.contains(frame))
        }
    }

    @MainActor
    func testLaterPlacementClampsBothAxes() {
        let screen = CGRect(x: 900, y: -600, width: 800, height: 600)
        let size = CGSize(width: 380, height: 560)
        for point in [CGPoint(x: -100, y: 2000), CGPoint(x: 3000, y: -2000)] {
            let origin = ResultPanelController.constrainedOrigin(topLeft: point, size: size, visible: screen, centered: false)
            XCTAssertTrue(screen.insetBy(dx: 16, dy: 16).contains(CGRect(origin: origin, size: size)))
        }
    }
}
