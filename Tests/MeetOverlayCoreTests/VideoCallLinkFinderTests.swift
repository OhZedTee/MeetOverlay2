import XCTest
@testable import MeetOverlayCore

final class VideoCallLinkFinderTests: XCTestCase {
    func testFindsGoogleMeetLinkInEventText() throws {
        let text = "Join with Google Meet: https://meet.google.com/abc-defg-hij"

        let link = VideoCallLinkFinder.firstLink(in: [text])

        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(link?.platform, .googleMeet)
    }

    func testFindsZoomLinkOnBareAndSubdomainHosts() throws {
        let bare = VideoCallLinkFinder.firstLink(in: ["https://zoom.us/j/123456789"])
        let subdomain = VideoCallLinkFinder.firstLink(in: ["Join: https://us02web.zoom.us/j/123456789?pwd=abc"])

        XCTAssertEqual(bare?.platform, .zoom)
        XCTAssertEqual(subdomain?.platform, .zoom)
        XCTAssertEqual(subdomain?.url.host, "us02web.zoom.us")
    }

    func testFindsMicrosoftTeamsLink() throws {
        let work = VideoCallLinkFinder.firstLink(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting"])
        let consumer = VideoCallLinkFinder.firstLink(in: ["https://teams.live.com/meet/123"])

        XCTAssertEqual(work?.platform, .microsoftTeams)
        XCTAssertEqual(consumer?.platform, .microsoftTeams)
    }

    func testFindsWebexLink() throws {
        let link = VideoCallLinkFinder.firstLink(in: ["https://company.webex.com/meet/ori"])

        XCTAssertEqual(link?.platform, .webex)
    }

    func testIgnoresNonVideoCallLinks() throws {
        let link = VideoCallLinkFinder.firstLink(in: ["Agenda: https://example.com/doc and notes"])

        XCTAssertNil(link)
    }

    func testIgnoresLookalikeHosts() throws {
        XCTAssertNil(VideoCallLinkFinder.firstLink(in: ["https://xzoom.us/j/1"]))
        XCTAssertNil(VideoCallLinkFinder.firstLink(in: ["https://meet.google.com.evil.example/abc"]))
        XCTAssertNil(VideoCallLinkFinder.firstLink(in: ["https://fakewebex.com/meet/x"]))
    }

    func testFirstCandidateWithVideoLinkWins() throws {
        let link = VideoCallLinkFinder.firstLink(in: [
            "No links here",
            "https://us02web.zoom.us/j/111",
            "https://meet.google.com/abc-defg-hij"
        ])

        XCTAssertEqual(link?.platform, .zoom)
    }

    func testPlatformRequiresHTTPScheme() throws {
        let url = try XCTUnwrap(URL(string: "ftp://zoom.us/j/1"))

        XCTAssertNil(VideoCallLinkFinder.platform(for: url))
    }
}
