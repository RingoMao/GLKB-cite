import Foundation
import XCTest

enum TestFixtures {
    static func data(named name: String, extension fileExtension: String = "json") throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: fileExtension),
            "Missing test fixture \(name).\(fileExtension)"
        )
        return try Data(contentsOf: url)
    }
}
