import XCTest
@testable import MeetOverlayCore

final class JoinableMeetingTests: XCTestCase {
    func testFromBuildsMeetingForAcceptedTimedEventWithMeetLink() throws {
        let event = makeEvent(notes: "Join https://meet.google.com/abc-defg-hij")

        let meeting = try XCTUnwrap(JoinableMeeting.from(event))

        XCTAssertEqual(meeting.eventID, "event")
        XCTAssertEqual(meeting.title, "Standup")
        XCTAssertEqual(meeting.startDate, event.startDate)
        XCTAssertEqual(meeting.endDate, event.endDate)
        XCTAssertEqual(meeting.meetURL.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(meeting.meetLinks.map(\.absoluteString), ["https://meet.google.com/abc-defg-hij"])
    }

    func testFromReturnsNilForDeclinedEvent() {
        let event = makeEvent(
            participationStatus: .declined,
            notes: "https://meet.google.com/abc-defg-hij"
        )

        XCTAssertNil(JoinableMeeting.from(event))
    }

    func testFromReturnsNilForAllDayEvent() {
        let event = makeEvent(
            isAllDay: true,
            notes: "https://meet.google.com/abc-defg-hij"
        )

        XCTAssertNil(JoinableMeeting.from(event))
    }

    func testFromReturnsNilWhenNoMeetLink() {
        let event = makeEvent(notes: "No video link here")

        XCTAssertNil(JoinableMeeting.from(event))
    }

    func testFromKeepsTentativeAndUnknownParticipation() {
        let tentative = makeEvent(
            participationStatus: .tentative,
            notes: "https://meet.google.com/abc-defg-hij"
        )
        let unknown = makeEvent(
            participationStatus: .unknown,
            notes: "https://meet.google.com/abc-defg-hij"
        )

        XCTAssertNotNil(JoinableMeeting.from(tentative))
        XCTAssertNotNil(JoinableMeeting.from(unknown))
    }

    func testMeetLinksDeduplicateRoomsAcrossEventFields() {
        let event = makeEvent(
            title: "Standup https://meet.google.com/title-room-abc",
            url: URL(string: "https://meet.google.com/url-room-abc"),
            notes: "Notes https://meet.google.com/notes-room-abc and https://meet.google.com/url-room-abc",
            location: "Room https://meet.google.com/location-room-abc"
        )

        XCTAssertEqual(event.meetLinks.map(\.absoluteString), [
            "https://meet.google.com/url-room-abc",
            "https://meet.google.com/notes-room-abc",
            "https://meet.google.com/location-room-abc",
            "https://meet.google.com/title-room-abc"
        ])
    }

    func testMeetLinksIgnoreNonMeetURLs() {
        let event = makeEvent(notes: "https://zoom.us/j/123 and https://example.com")

        XCTAssertEqual(event.meetLinks, [])
    }

    func testFromBuildsMeetingForNonGooglePlatforms() throws {
        let cases: [(String, VideoCallPlatform)] = [
            ("https://company.zoom.us/j/987654321", .zoom),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting", .microsoftTeams),
            ("https://acme.webex.com/meet/standup", .webex)
        ]

        for (link, expectedPlatform) in cases {
            let meeting = try XCTUnwrap(JoinableMeeting.from(makeEvent(notes: "Join \(link)")))
            XCTAssertEqual(meeting.platform, expectedPlatform, "for \(link)")
            XCTAssertEqual(meeting.meetURL.absoluteString, link, "for \(link)")
            // Non-Google platforms have no Google "rooms", so meetLinks falls back
            // to the single detected link (drives the single-link join path).
            XCTAssertEqual(meeting.meetLinks.map(\.absoluteString), [link], "for \(link)")
        }
    }

    func testFromPropagatesAttendeesAndLocation() throws {
        let event = makeEvent(
            notes: "https://meet.google.com/abc-defg-hij",
            location: "MTL-5F-Boardroom",
            attendees: ["Alice", "Bob"]
        )

        let meeting = try XCTUnwrap(JoinableMeeting.from(event))

        XCTAssertEqual(meeting.platform, .googleMeet)
        XCTAssertEqual(meeting.attendees, ["Alice", "Bob"])
        XCTAssertEqual(meeting.location, "MTL-5F-Boardroom")
    }

    func testFromKeepsAllGoogleRoomsForMultiRoomEvent() throws {
        let event = makeEvent(
            title: "Standup https://meet.google.com/title-room-abc",
            url: URL(string: "https://meet.google.com/url-room-abc"),
            notes: "Notes https://meet.google.com/notes-room-abc",
            location: "Room https://meet.google.com/location-room-abc"
        )

        let meeting = try XCTUnwrap(JoinableMeeting.from(event))

        XCTAssertEqual(meeting.platform, .googleMeet)
        XCTAssertEqual(meeting.meetURL.absoluteString, "https://meet.google.com/url-room-abc")
        XCTAssertEqual(meeting.meetLinks.map(\.absoluteString), [
            "https://meet.google.com/url-room-abc",
            "https://meet.google.com/notes-room-abc",
            "https://meet.google.com/location-room-abc",
            "https://meet.google.com/title-room-abc"
        ])
    }

    private func makeEvent(
        isAllDay: Bool = false,
        participationStatus: EventParticipationStatus = .accepted,
        title: String = "Standup",
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil,
        attendees: [String] = []
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: "event",
            title: title,
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            endDate: Date(timeIntervalSinceReferenceDate: 1800),
            isAllDay: isAllDay,
            participationStatus: participationStatus,
            url: url,
            notes: notes,
            location: location,
            attendees: attendees
        )
    }
}
