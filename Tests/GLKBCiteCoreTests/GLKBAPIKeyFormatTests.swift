import XCTest
@testable import GLKBCiteCore

final class GLKBAPIKeyFormatTests: XCTestCase {
    func testWellFormedKeysAreTrimmedAndKept() {
        XCTAssertEqual(GLKBAPIKeyFormat.normalize("glkb_abc-123_XYZ"), "glkb_abc-123_XYZ")
        XCTAssertEqual(GLKBAPIKeyFormat.normalize("  glkb_abc\n"), "glkb_abc")
        XCTAssertEqual(GLKBAPIKeyFormat.normalize("\tglkb_a\r\n"), "glkb_a")
    }

    func testKeysWithEmbeddedBreaksOrForeignCharactersAreRejected() {
        // A line break copied from a wrapped email would otherwise be sent as
        // an empty Authorization header and reported as "key rejected".
        XCTAssertNil(GLKBAPIKeyFormat.normalize("glkb_abc\ndef"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize("glkb_abc def"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize("glkb_abc\u{200B}def"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize("glkb_ab\u{0441}"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize("glkb_"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize("GLKB_abc"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize("Bearer glkb_abc"))
        XCTAssertNil(GLKBAPIKeyFormat.normalize(""))
    }
}
