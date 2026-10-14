import XCTest

@testable import DescriberCore

final class DescriberCoreTests: XCTestCase {
    func testSchemaVersionIsOne() {
        XCTAssertEqual(DescriberCore.schemaVersion, 1)
    }
}
