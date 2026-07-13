import XCTest
@testable import MeetOverlayCore

final class MeetingAlertSelectorTests: XCTestCase {
    func testShowsUpcomingMeetEventInsideAlertWindow() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: now.addingTimeInterval(60),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertEqual(selectedMeeting?.eventID, "event-1")
        XCTAssertEqual(selectedMeeting?.meetURL.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(selectedMeeting?.platform, .googleMeet)
    }

    func testShowsZoomMeetingWithItsPlatform() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = CalendarEventSnapshot(
            id: "event-1",
            title: "Zoom planning",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(3_600),
            isAllDay: false,
            participationStatus: .accepted,
            url: nil,
            notes: "Join: https://us02web.zoom.us/j/123456789",
            location: nil
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertEqual(selectedMeeting?.meetURL.absoluteString, "https://us02web.zoom.us/j/123456789")
        XCTAssertEqual(selectedMeeting?.platform, .zoom)
    }

    func testDoesNotShowDeclinedEvent() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Declined planning",
            startDate: now.addingTimeInterval(60),
            now: now,
            participationStatus: .declined
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertNil(selectedMeeting)
    }

    func testDoesNotShowSuppressedEvent() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: now.addingTimeInterval(60),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: ["event-1"])

        XCTAssertNil(selectedMeeting)
    }

    func testDoesNotShowEventBeforeAlertWindow() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Later planning",
            startDate: now.addingTimeInterval(61),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertNil(selectedMeeting)
    }

    func testDoesNotShowEventThatStartedTooLongAgo() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Already started",
            startDate: now.addingTimeInterval(-25 * 60),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60, lateAlertGraceTime: 120)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertNil(selectedMeeting)
    }

    func testShowsEventThatJustStarted() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Just started",
            startDate: now.addingTimeInterval(-30),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60, lateAlertGraceTime: 120)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertEqual(selectedMeeting?.eventID, "event-1")
    }

    // MARK: - 15-minute lead time boundary

    func testShowsEventAt15MinLeadTime() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: now.addingTimeInterval(15 * 60),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 15 * 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertEqual(selectedMeeting?.eventID, "event-1")
    }

    func testDoesNotShowEventJustOutside15MinWindow() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Later planning",
            startDate: now.addingTimeInterval(15 * 60 + 1),
            now: now
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 15 * 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertNil(selectedMeeting)
    }

    // MARK: - Snooze re-appear behaviour

    func testSnoozedEventIsHiddenWhenInSuppressedIDs() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: now.addingTimeInterval(5 * 60),
            now: now
        )

        // Simulates snooze active: event ID is in the suppressed set
        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 15 * 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: ["event-1"])

        XCTAssertNil(selectedMeeting)
    }

    func testSnoozedEventReappearsAfterSnoozeExpiry() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: now.addingTimeInterval(5 * 60),
            now: now
        )

        // Simulates snooze expired: event ID is no longer in the suppressed set
        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 15 * 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertEqual(selectedMeeting?.eventID, "event-1")
    }

    // MARK: - Attendees and location passthrough

    func testPassesAttendeesAndLocationThroughToJoinableMeeting() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let event = CalendarEventSnapshot(
            id: "event-1",
            title: "Planning",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(3_600),
            isAllDay: false,
            participationStatus: .accepted,
            url: nil,
            notes: "https://meet.google.com/abc-defg-hij",
            location: "MTL-5F-Boardroom",
            attendees: ["Alice", "MTL-5F-Boardroom", "Bob"]
        )

        let selectedMeeting = MeetingAlertSelector(alertLeadTime: 60)
            .meetingToShow(now: now, events: [event], suppressedEventIDs: [])

        XCTAssertEqual(selectedMeeting?.attendees, ["Alice", "MTL-5F-Boardroom", "Bob"])
        XCTAssertEqual(selectedMeeting?.location, "MTL-5F-Boardroom")
    }

    private func makeEvent(
        id: String,
        title: String,
        startDate: Date,
        now: Date,
        participationStatus: EventParticipationStatus = .accepted
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            title: title,
            startDate: startDate,
            endDate: now.addingTimeInterval(3_600),
            isAllDay: false,
            participationStatus: participationStatus,
            url: nil,
            notes: "https://meet.google.com/abc-defg-hij",
            location: nil
        )
    }
}
