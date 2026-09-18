import XCTest
@testable import GLKBCiteMac

final class GestureClassificationTests: XCTestCase {
    func testCompatibilityEligibilityRejectsOrdinaryCaretClick() {
        XCTAssertFalse(gesture().isLikelySelection)
    }

    func testCompatibilityEligibilityAcceptsSelectionGestures() {
        XCTAssertTrue(gesture(endX: 12).isLikelySelection)
        XCTAssertTrue(gesture(clickCount: 2).isLikelySelection)
        XCTAssertTrue(gesture(shift: true).isLikelySelection)
        XCTAssertTrue(gesture(dragged: true).isLikelySelection)
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

    func testDeliberateSelectionRequiresRealDragOrMultiClick() {
        XCTAssertFalse(gesture().isDeliberateSelection)
        XCTAssertFalse(gesture(shift: true).isDeliberateSelection, "shift-click alone selects list rows, not text")
        XCTAssertFalse(gesture(endX: 5, dragged: true).isDeliberateSelection, "a 5pt jitter is not a drag")
        XCTAssertFalse(gesture(endX: 12).isDeliberateSelection, "distance without observed drag events")
        XCTAssertTrue(gesture(endX: 12, dragged: true).isDeliberateSelection)
        XCTAssertTrue(gesture(clickCount: 2).isDeliberateSelection)
    }
}
