import XCTest
@testable import MeetOverlayCore

final class MeetingNotificationComposerTests: XCTestCase {
    func testTitleIsMeetingTitleAndBodyIsCountdown() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let content = MeetingNotificationComposer.content(
            meetingTitle: "Planning",
            startDate: now.addingTimeInterval(15 * 60),
            roomName: nil,
            now: now
        )

        XCTAssertEqual(content.title, "Planning")
        XCTAssertEqual(content.body, "Starts in 15m")
    }

    func testBodyAppendsRoomNameWhenPresent() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let content = MeetingNotificationComposer.content(
            meetingTitle: "Planning",
            startDate: now.addingTimeInterval(5 * 60),
            roomName: "MTL-5F-Boardroom",
            now: now
        )

        XCTAssertEqual(content.body, "Starts in 5m · MTL-5F-Boardroom")
    }

    func testBodyForMeetingThatAlreadyStarted() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let content = MeetingNotificationComposer.content(
            meetingTitle: "Planning",
            startDate: now.addingTimeInterval(-5 * 60),
            roomName: "MTL-5F-Boardroom",
            now: now
        )

        XCTAssertEqual(content.body, "Started 5m ago · MTL-5F-Boardroom")
    }

    func testEmptyRoomNameIsNotAppended() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let content = MeetingNotificationComposer.content(
            meetingTitle: "Planning",
            startDate: now.addingTimeInterval(60),
            roomName: nil,
            now: now
        )

        XCTAssertFalse(content.body.contains("·"))
    }
}
