import XCTest

final class SmokeTests: XCTestCase {
    func testBundleLoads() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
