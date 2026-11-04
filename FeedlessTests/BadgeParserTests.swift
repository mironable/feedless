import XCTest
@testable import Feedless

final class BadgeParserTests: XCTestCase {
    func testFlatBadgeCount() throws {
        XCTAssertEqual(try BadgeParser.unreadCount(in: Data(#"{"data":{"xdt_direct_badge":{"badge_count":3}}}"#.utf8)), 3)
    }

    func testNestedTotalCount() throws {
        let json = #"{"data":{"xdt_notification_badge":{"badge_count":{"total_count":2,"activity_badge_counts":{"likes":null}}}}}"#
        XCTAssertEqual(try BadgeParser.unreadCount(in: Data(json.utf8)), 2)
    }

    func testStringNumberAndArrays() throws {
        XCTAssertEqual(try BadgeParser.unreadCount(in: Data(#"{"data":[{"x":{"unseen_count":"4"}}]}"#.utf8)), 4)
    }

    func testMissingCountThrows() {
        XCTAssertThrowsError(try BadgeParser.unreadCount(in: Data(#"{"data":{"status":"ok"}}"#.utf8)))
    }
}
