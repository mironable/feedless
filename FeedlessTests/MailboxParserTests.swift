import XCTest
@testable import Feedless

final class MailboxParserTests: XCTestCase {
    // Same shape as Instagram's IGDBadgeCountOffMsysQuery response, with made-up ids.
    private let json = """
    {"data":{"get_slide_mailbox_for_iris_subscription":{"iris_inactive_subscription_uq_seq_id":"1","threads_by_folder":{"edges":[
      {"node":{"as_ig_direct_thread":{"marked_as_unread":false,"last_activity_timestamp_ms":"1700000002000","slide_read_receipts":[
        {"participant_fbid":"2001","watermark_timestamp_ms":"1700000001000"},
        {"participant_fbid":"1001","watermark_timestamp_ms":"1700000002001"}],"is_muted":false,"id":"3001"},"id":"3001","__typename":"SlideThread"},"cursor":"a"},
      {"node":{"as_ig_direct_thread":{"marked_as_unread":false,"last_activity_timestamp_ms":"1700000005000","slide_read_receipts":[
        {"participant_fbid":"2002","watermark_timestamp_ms":"1700000005000"},
        {"participant_fbid":"1001","watermark_timestamp_ms":"1700000003000"}],"is_muted":false,"id":"3002"},"id":"3002","__typename":"SlideThread"},"cursor":"b"},
      {"node":{"as_ig_direct_thread":{"marked_as_unread":true,"last_activity_timestamp_ms":"1700000004000","slide_read_receipts":[
        {"participant_fbid":"2003","watermark_timestamp_ms":"1700000001000"},
        {"participant_fbid":"2004","watermark_timestamp_ms":"1700000001500"},
        {"participant_fbid":"1001","watermark_timestamp_ms":"1700000004000"}],"is_muted":true,"id":"3003"},"id":"3003","__typename":"SlideThread"},"cursor":"c"}
    ],"page_info":{"end_cursor":"x","has_next_page":true}},"id":"1001"}},"extensions":{"is_final":true}}
    """

    func testParsesViewerAndThreads() throws {
        let snapshot = try MailboxParser.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.viewerID, "1001")
        XCTAssertEqual(snapshot.threads.map(\.id), ["3001", "3002", "3003"])
        XCTAssertEqual(snapshot.threads[0].viewerWatermark, 1700000002001)
        XCTAssertFalse(snapshot.threads[0].isUnread)
        XCTAssertTrue(snapshot.threads[1].isUnread, "activity after the viewer's watermark")
        XCTAssertTrue(snapshot.threads[2].isUnread, "explicitly marked unread")
        XCTAssertTrue(snapshot.threads[2].muted)
        XCTAssertEqual(snapshot.unreadCount, 1, "muted threads do not count")
    }

    func testWebURLs() throws {
        let snapshot = try MailboxParser.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.threads[0].webURL(viewerID: snapshot.viewerID).absoluteString, "https://www.instagram.com/direct/t/2001/")
        XCTAssertEqual(snapshot.threads[2].webURL(viewerID: snapshot.viewerID).absoluteString, "https://www.instagram.com/direct/t/3003/")
    }

    func testRejectsOtherShapes() {
        XCTAssertThrowsError(try MailboxParser.parse(Data(#"{"data":{"status":"ok"}}"#.utf8)))
    }
}
