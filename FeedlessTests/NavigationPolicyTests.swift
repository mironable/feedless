import XCTest
@testable import Feedless

final class NavigationPolicyTests: XCTestCase {
    private var policy: NavigationPolicy!

    override func setUpWithError() throws {
        policy = NavigationPolicy(rules: try RuleLoader(platform: "instagram").loadRules())
    }

    private func rewrite(_ string: String, feed: String = "following") -> String? {
        policy.rewrittenHomeURL(for: URL(string: string)!, preferredFeedID: feed)?.absoluteString
    }

    func testRootBecomesFollowing() {
        XCTAssertEqual(rewrite("https://www.instagram.com/"), "https://www.instagram.com/?variant=following")
        XCTAssertEqual(rewrite("https://www.instagram.com"), "https://www.instagram.com/?variant=following")
    }

    func testHomeVariantBecomesFollowing() {
        XCTAssertEqual(rewrite("https://www.instagram.com/?variant=home"), "https://www.instagram.com/?variant=following")
        XCTAssertEqual(rewrite("https://www.instagram.com/?variant=foryou"), "https://www.instagram.com/?variant=following")
    }

    func testPreferredFeedIsUsed() {
        XCTAssertEqual(rewrite("https://www.instagram.com/", feed: "favorites"), "https://www.instagram.com/?variant=favorites")
    }

    func testKnownFeedVariantsAreKept() {
        XCTAssertNil(rewrite("https://www.instagram.com/?variant=following"))
        XCTAssertNil(rewrite("https://www.instagram.com/?variant=favorites", feed: "following"))
    }

    func testHostIsPreserved() {
        XCTAssertEqual(rewrite("https://instagram.com/"), "https://instagram.com/?variant=following")
    }

    func testOtherPathsAreUntouched() {
        XCTAssertNil(rewrite("https://www.instagram.com/direct/inbox/"))
        XCTAssertNil(rewrite("https://www.instagram.com/direct/t/1234567890/"))
        XCTAssertNil(rewrite("https://www.instagram.com/someuser/"))
        XCTAssertNil(rewrite("https://www.instagram.com/p/ABC123/"))
        XCTAssertNil(rewrite("https://www.instagram.com/accounts/login/?next=%2F"))
    }

    func testExternalHostsAreNotRewritten() {
        XCTAssertNil(rewrite("https://example.com/"))
        XCTAssertNil(rewrite("https://www.facebook.com/?variant=home"))
    }

    func testInternalHosts() {
        XCTAssertTrue(policy.isInternal(URL(string: "https://www.instagram.com/")!))
        XCTAssertTrue(policy.isInternal(URL(string: "https://scontent-fra3-1.cdninstagram.com/x.jpg")!))
        XCTAssertFalse(policy.isInternal(URL(string: "https://notinstagram.com/")!))
        XCTAssertFalse(policy.isInternal(URL(string: "https://example.com/instagram.com")!))
    }

    func testThreadID() {
        XCTAssertEqual(NavigationPolicy.threadID(from: URL(string: "https://www.instagram.com/direct/t/1234567890/")!), "1234567890")
        XCTAssertEqual(NavigationPolicy.threadID(from: URL(string: "https://www.instagram.com/direct/t/1234567890")!), "1234567890")
        XCTAssertNil(NavigationPolicy.threadID(from: URL(string: "https://www.instagram.com/direct/inbox/")!))
        XCTAssertNil(NavigationPolicy.threadID(from: URL(string: "https://www.instagram.com/")!))
        XCTAssertEqual(NavigationPolicy.deepLink(threadID: "42").absoluteString, "instagram://direct/t/42")
    }
}
