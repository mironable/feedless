import XCTest
@testable import Feedless

final class InboxParserTests: XCTestCase {
    private let json = """
    {
      "viewer": { "pk": 111, "username": "me" },
      "inbox": {
        "unseen_count": 2,
        "threads": [
          {
            "thread_id": "340282366841710300949128",
            "thread_title": "alice",
            "users": [ { "pk": "222", "username": "alice" } ],
            "items": [
              { "item_id": "3", "user_id": 222, "timestamp": 1730700000000003, "item_type": "text", "text": "hey" },
              { "item_id": "2", "user_id": 111, "timestamp": 1730700000000002, "item_type": "text", "text": "mine" },
              { "item_id": "1", "user_id": 222, "timestamp": 1730700000000001, "item_type": "media" }
            ]
          },
          {
            "thread_id": "9999",
            "thread_title": "",
            "users": [ { "pk": 333, "username": "bob" }, { "pk": 444, "username": "carol" } ],
            "items": [
              { "item_id": "9", "user_id": "444", "timestamp": "1730600000000000", "item_type": "voice_media" }
            ]
          }
        ]
      },
      "status": "ok"
    }
    """

    func testParsesViewerThreadsAndSkipsOwnMessages() throws {
        let snapshot = try InboxParser.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.viewerID, "111")
        XCTAssertEqual(snapshot.unseenCount, 2)
        XCTAssertEqual(snapshot.messages.count, 3)
        XCTAssertEqual(snapshot.messages[0].body, "hey")
        XCTAssertEqual(snapshot.messages[0].senderName, "alice")
        XCTAssertEqual(snapshot.messages[1].body, "Sent a photo")
        XCTAssertEqual(snapshot.messages[2].threadTitle, "bob, carol")
        XCTAssertEqual(snapshot.messages[2].senderName, "carol")
        XCTAssertEqual(snapshot.messages[2].body, "Sent a voice message")
        XCTAssertEqual(snapshot.newestTimestamp, 1730700000000003)
    }

    func testNewMessagesAreNewerThanBaselineAndOnePerThread() throws {
        let snapshot = try InboxParser.parse(Data(json.utf8))
        let fresh = InboxParser.newMessages(in: snapshot, after: 1730650000000000)
        XCTAssertEqual(fresh.map(\.body), ["hey"])
        let all = InboxParser.newMessages(in: snapshot, after: 0)
        XCTAssertEqual(all.map(\.threadID), ["9999", "340282366841710300949128"])
        XCTAssertEqual(all[1].body, "hey")
        XCTAssertTrue(InboxParser.newMessages(in: snapshot, after: snapshot.newestTimestamp).isEmpty)
    }

    func testRejectsNonObjectJSON() {
        XCTAssertThrowsError(try InboxParser.parse(Data("[]".utf8)))
    }
}
