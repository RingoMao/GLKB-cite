import XCTest
@testable import GLKBCiteMac

final class GestureClassificationTests: XCTestCase {
    func testCompatibilityEligibilityRejectsOrdinaryCaretClick() {
        XCTAssertFalse(gesture().isCompatibilityEligible)
    }

    func testCompatibilityEligibilityAcceptsSelectionGestures() {
        XCTAssertTrue(gesture(endX: 12).isCompatibilityEligible)
        XCTAssertTrue(gesture(clickCount: 2).isCompatibilityEligible)
        XCTAssertTrue(gesture(shift: true).isCompatibilityEligible)
        XCTAssertTrue(gesture(dragged: true).isCompatibilityEligible)
    }

    private func gesture(
        endX: Double = 0,
        clickCount: Int = 1,
        shift: Bool = false,
        dragged: Bool = false
    ) -> SelectionGesture {
        SelectionGesture(
            start: .init(x: 0, y: 0),
            end: .init(x: endX, y: 0),
            clickCount: clickCount,
            shiftPressed: shift,
            observedDrag: dragged
        )
    }
}
