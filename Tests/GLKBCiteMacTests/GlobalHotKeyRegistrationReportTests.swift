import XCTest
import GLKBCiteMac

final class GlobalHotKeyRegistrationReportTests: XCTestCase {
    func testCitationShortcutAvailabilityIsReported() {
        XCTAssertEqual(
            GlobalHotKeyRegistrationReport(availability: .registered).availability,
            .registered
        )
        XCTAssertEqual(
            GlobalHotKeyRegistrationReport(
                availability: .unavailable(status: -9876)
            ).availability,
            .unavailable(status: -9876)
        )
    }
}
