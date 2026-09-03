import Foundation
import XCTest
import GLKBCiteMac

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testMissingCachePreferenceDefaultsToFifteenMinutes() throws {
        let suiteName = "org.glkb.cite.tests.missing-cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let duration = AppSettings(defaults: defaults).cacheDurationMinutes

        XCTAssertEqual(duration, 15)
    }

    @MainActor
    func testExplicitlyDisabledCacheRemainsDisabled() throws {
        let suiteName = "org.glkb.cite.tests.disabled-cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0, forKey: "literature.cacheDurationMinutes")

        let duration = AppSettings(defaults: defaults).cacheDurationMinutes

        XCTAssertEqual(duration, 0)
    }
}
