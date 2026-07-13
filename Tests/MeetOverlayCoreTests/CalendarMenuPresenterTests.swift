import XCTest
@testable import MeetOverlayCore

final class CalendarMenuPresenterTests: XCTestCase {
    func testBuildsTodayAndTomorrowSectionsWithMeetIndicators() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let todayMeet = makeEvent(
            id: "today-meet",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )
        let tomorrowNoMeet = makeEvent(
            id: "tomorrow-no-meet",
            title: "Admin day",
            startDate: date(year: 2026, month: 6, day: 4, hour: 9, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 4, hour: 17, minute: 0, calendar: calendar),
            isAllDay: true
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [tomorrowNoMeet, todayMeet])

        XCTAssertEqual(sections.map(\.title), ["Today's Events", "Tomorrow's Events"])
        XCTAssertEqual(sections[0].rows[0].title, "Planning")
        XCTAssertEqual(sections[0].rows[0].timeText, "17:00")
        XCTAssertEqual(sections[0].rows[0].phase, .upcoming)
        XCTAssertEqual(sections[0].rows[0].durationText, "1h")
        XCTAssertTrue(sections[0].rows[0].hasMeetLink)
        XCTAssertEqual(sections[0].rows[0].meetURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(sections[0].rows[0].platform, .googleMeet)
        XCTAssertEqual(sections[0].rows[0].meetLinks.map(\.absoluteString), ["https://meet.google.com/abc-defg-hij"])
        XCTAssertEqual(sections[1].rows[0].title, "Admin day")
        XCTAssertEqual(sections[1].rows[0].timeText, "All-day")
        XCTAssertEqual(sections[1].rows[0].phase, .allDay)
        XCTAssertNil(sections[1].rows[0].durationText, "All-day events show no duration")
        XCTAssertFalse(sections[1].rows[0].hasMeetLink)
        XCTAssertNil(sections[1].rows[0].meetURL)
        XCTAssertNil(sections[1].rows[0].platform)
        XCTAssertEqual(sections[1].rows[0].meetLinks, [])
    }

    func testBuildsRowsWithMultipleUniqueMeetLinks() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "multi-meet",
            title: "Planning https://meet.google.com/title-room-abc",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar),
            url: URL(string: "https://meet.google.com/url-room-abc"),
            notes: "Notes https://meet.google.com/notes-room-abc duplicate https://meet.google.com/url-room-abc",
            location: "Room https://meet.google.com/location-room-abc"
        )

        let row = try XCTUnwrap(CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [event])
            .first?
            .rows
            .first)

        XCTAssertEqual(row.meetURL?.absoluteString, "https://meet.google.com/url-room-abc")
        XCTAssertEqual(row.meetLinks.map(\.absoluteString), [
            "https://meet.google.com/url-room-abc",
            "https://meet.google.com/notes-room-abc",
            "https://meet.google.com/location-room-abc",
            "https://meet.google.com/title-room-abc"
        ])
    }

    func testRowDurationCoversPartialHours() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Sprint planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 30, calendar: calendar)
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [event])

        XCTAssertEqual(sections[0].rows[0].durationText, "1h 30m")
    }

    func testRowsDetectNonMeetPlatforms() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let zoomEvent = makeEvent(
            id: "zoom-event",
            title: "Zoom sync",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar),
            notes: "https://company.zoom.us/j/987654321"
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [zoomEvent])

        XCTAssertTrue(sections[0].rows[0].hasMeetLink)
        XCTAssertEqual(sections[0].rows[0].platform, .zoom)
    }

    func testRowsCarryAttendeesWithRoomResolutionDisabledByDefault() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar),
            attendees: ["Alice", "MTL-5F-Boardroom"]
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [event])

        XCTAssertEqual(sections[0].rows[0].attendees, ["Alice", "MTL-5F-Boardroom"])
        XCTAssertNil(sections[0].rows[0].roomName)
    }

    func testRowsResolveRoomWhenConfigEnabled() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar),
            attendees: ["Alice", "MTL-5F-Boardroom"]
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(
                now: now,
                events: [event],
                roomConfig: MeetingRoomConfig(isEnabled: true, isRoomInAttendees: true, pattern: "MTL-*")
            )

        XCTAssertEqual(sections[0].rows[0].roomName, "MTL-5F-Boardroom")
        XCTAssertEqual(sections[0].rows[0].attendees, ["Alice"])
    }

    func testMenuBarTitleUsesNextUpcomingTodayEvent() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 20, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [event])

        XCTAssertEqual(title, "Planning 20m")
    }

    func testMenuBarTitlePrefersUpcomingMeetEventOverCurrentNonMeetEvent() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 13, minute: 0, calendar: calendar)
        let currentNonMeetEvent = makeEvent(
            id: "prep",
            title: "[PREP] Sprint R&R",
            startDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 30, calendar: calendar)
        )
        let upcomingMeetEvent = makeEvent(
            id: "test-event",
            title: "Test event",
            startDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 10, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 30, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [currentNonMeetEvent, upcomingMeetEvent])

        XCTAssertEqual(title, "Test event 10m")
    }

    func testMenuBarTitleKeepsInProgressMeetAheadOfFutureMeet() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 13, minute: 9, calendar: calendar)
        let inProgressMeetEvent = makeEvent(
            id: "old-meet",
            title: "Old Meet",
            startDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 30, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )
        let upcomingMeetEvent = makeEvent(
            id: "next-meet",
            title: "Next Meet",
            startDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 10, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 13, minute: 30, calendar: calendar),
            notes: "https://meet.google.com/xyz-abcd-efg"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [inProgressMeetEvent, upcomingMeetEvent])

        XCTAssertEqual(title, "Old Meet now")
    }

    func testMenuBarPresentationUsesUpcomingStateOutsideUrgentWindow() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 20, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let presentation = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarPresentation(now: now, events: [event])

        XCTAssertEqual(presentation, CalendarMenuBarPresentation(title: "Planning 20m", urgency: .upcoming))
    }

    func testMenuBarPresentationUsesUrgentStateNearStart() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 4, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let presentation = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarPresentation(now: now, events: [event])

        XCTAssertEqual(presentation, CalendarMenuBarPresentation(title: "Planning 4m", urgency: .urgent))
    }

    func testMenuBarPresentationUsesUrgentNowStateForInProgressMeetEvent() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 1, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let presentation = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarPresentation(now: now, events: [event])

        XCTAssertEqual(presentation, CalendarMenuBarPresentation(title: "Planning now", urgency: .urgent))
    }

    func testMenuBarPresentationUsesIdleStateWithoutUpcomingTodayEvent() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)

        let presentation = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarPresentation(now: now, events: [])

        XCTAssertEqual(presentation, CalendarMenuBarPresentation(title: "Meet", urgency: .idle))
    }

    func testSectionsHighlightHappeningNowAndNextUpWhenMeetIsInProgress() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 14, minute: 5, calendar: calendar)
        let activeMeet = makeEvent(
            id: "active-meet",
            title: "[ALL] Sprint R&R",
            startDate: date(year: 2026, month: 6, day: 3, hour: 14, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 14, minute: 30, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )
        let nextMeet = makeEvent(
            id: "next-meet",
            title: "[DEV] Sprint R&R",
            startDate: date(year: 2026, month: 6, day: 3, hour: 15, minute: 5, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 15, minute: 30, calendar: calendar),
            notes: "https://meet.google.com/xyz-abcd-efg"
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [activeMeet, nextMeet])

        XCTAssertEqual(sections.map(\.title), ["Happening Now", "Next Up"])
        XCTAssertEqual(sections[0].rows[0].title, "[ALL] Sprint R&R")
        XCTAssertEqual(sections[0].rows[0].statusText, "now")
        XCTAssertEqual(sections[0].rows[0].phase, .inProgress)
        XCTAssertEqual(sections[1].rows[0].title, "[DEV] Sprint R&R")
        XCTAssertEqual(sections[1].rows[0].statusText, "in 1h")
        XCTAssertEqual(sections[1].rows[0].phase, .upcoming)
    }

    func testMenuBarTitleShowsHoursAndRemainingMinutesWhenStartIsOverOneHourAway() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Planning",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 52, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 30, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [event])

        XCTAssertEqual(title, "Planning 1h 52m")
    }

    func testMenuBarTitleIgnoresAllDayEventsAndUsesNextTimedEvent() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 30, calendar: calendar)
        let allDayEvent = makeEvent(
            id: "birthday",
            title: "Leona rođendan",
            startDate: date(year: 2026, month: 6, day: 3, hour: 0, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 4, hour: 0, minute: 0, calendar: calendar),
            isAllDay: true
        )
        let timedEvent = makeEvent(
            id: "dinner",
            title: "Leona večera",
            startDate: date(year: 2026, month: 6, day: 3, hour: 19, minute: 30, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 22, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [allDayEvent, timedEvent])

        XCTAssertEqual(title, "Leona večera 3h")
    }

    func testMenuBarTitleIgnoresTomorrowEvents() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "Tomorrow planning",
            startDate: date(year: 2026, month: 6, day: 4, hour: 10, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 4, hour: 11, minute: 0, calendar: calendar)
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [event])

        XCTAssertEqual(title, "Meet")
    }

    func testMenuBarTitleShortensLongEventTitles() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let event = makeEvent(
            id: "event-1",
            title: "1234567890123456789012345",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 20, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [event])

        XCTAssertEqual(title, "123456789012345678901... 20m")
    }

    func testHidesFinishedEventsFromSectionsWhenEnabled() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let finishedEvent = makeEvent(
            id: "finished",
            title: "Finished",
            startDate: date(year: 2026, month: 6, day: 3, hour: 14, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 15, minute: 0, calendar: calendar)
        )
        let upcomingEvent = makeEvent(
            id: "upcoming",
            title: "Upcoming",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar)
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [finishedEvent, upcomingEvent], hideFinishedEvents: true)

        XCTAssertEqual(sections[0].rows.map(\.title), ["Upcoming"])
    }

    func testShowsFinishedEventsFromSectionsWhenDisabled() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let finishedEvent = makeEvent(
            id: "finished",
            title: "Finished",
            startDate: date(year: 2026, month: 6, day: 3, hour: 14, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 15, minute: 0, calendar: calendar)
        )
        let upcomingEvent = makeEvent(
            id: "upcoming",
            title: "Upcoming",
            startDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 18, minute: 0, calendar: calendar)
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [finishedEvent, upcomingEvent], hideFinishedEvents: false)

        XCTAssertEqual(sections[0].rows.map(\.title), ["Finished", "Upcoming"])
        XCTAssertEqual(sections[0].rows.map(\.phase), [.ended, .upcoming])
    }

    func testMenuBarTitleSkipsDeclinedMeetAndUsesNextAcceptedMeet() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let declinedMeet = makeEvent(
            id: "declined",
            title: "Declined",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 10, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 40, calendar: calendar),
            participationStatus: .declined,
            notes: "https://meet.google.com/abc-defg-hij"
        )
        let acceptedMeet = makeEvent(
            id: "accepted",
            title: "Accepted",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 40, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 17, minute: 10, calendar: calendar),
            notes: "https://meet.google.com/xyz-abcd-efg"
        )

        let title = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarTitle(now: now, events: [declinedMeet, acceptedMeet])

        XCTAssertEqual(title, "Accepted 40m")
    }

    func testMenuBarPresentationSkipsDeclinedInProgressMeet() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 5, calendar: calendar)
        let declinedInProgress = makeEvent(
            id: "declined",
            title: "Declined",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 30, calendar: calendar),
            participationStatus: .declined,
            notes: "https://meet.google.com/abc-defg-hij"
        )
        let acceptedUpcoming = makeEvent(
            id: "accepted",
            title: "Accepted",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 20, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 50, calendar: calendar),
            notes: "https://meet.google.com/xyz-abcd-efg"
        )

        let presentation = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarPresentation(now: now, events: [declinedInProgress, acceptedUpcoming])

        XCTAssertEqual(presentation, CalendarMenuBarPresentation(title: "Accepted 15m", urgency: .upcoming))
    }

    func testMenuBarPresentationIsIdleWhenOnlyDeclinedMeetRemains() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 16, minute: 0, calendar: calendar)
        let declinedMeet = makeEvent(
            id: "declined",
            title: "Declined",
            startDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 10, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 16, minute: 40, calendar: calendar),
            participationStatus: .declined,
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let presentation = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .menuBarPresentation(now: now, events: [declinedMeet])

        XCTAssertEqual(presentation, CalendarMenuBarPresentation(title: "Meet", urgency: .idle))
    }

    func testDeclinedActiveMeetIsNotHighlightedButStaysInTimeline() throws {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 14, minute: 5, calendar: calendar)
        let declinedActiveMeet = makeEvent(
            id: "declined",
            title: "Declined",
            startDate: date(year: 2026, month: 6, day: 3, hour: 14, minute: 0, calendar: calendar),
            endDate: date(year: 2026, month: 6, day: 3, hour: 14, minute: 30, calendar: calendar),
            participationStatus: .declined,
            notes: "https://meet.google.com/abc-defg-hij"
        )

        let sections = CalendarMenuPresenter(calendar: calendar, locale: Locale(identifier: "en_GB"))
            .sections(now: now, events: [declinedActiveMeet])

        XCTAssertEqual(sections.map(\.title), ["Today's Events"])
        XCTAssertEqual(sections[0].rows.map(\.title), ["Declined"])
    }

    private func makeEvent(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        participationStatus: EventParticipationStatus = .accepted,
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil,
        attendees: [String] = []
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            participationStatus: participationStatus,
            url: url,
            notes: notes,
            location: location,
            attendees: attendees
        )
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
