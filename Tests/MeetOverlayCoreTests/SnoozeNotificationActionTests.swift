import XCTest
@testable import MeetOverlayCore

final class ReminderTimeLimitsTests: XCTestCase {
    func testValuesInsideRangePassThrough() throws {
        XCTAssertEqual(ReminderTimeLimits.clamped(300), 300)
        XCTAssertEqual(ReminderTimeLimits.clamped(1), 1)
        XCTAssertEqual(ReminderTimeLimits.clamped(86_400), 86_400)
    }

    func testValuesOutsideRangeClampToBounds() throws {
        XCTAssertEqual(ReminderTimeLimits.clamped(0), 1)
        XCTAssertEqual(ReminderTimeLimits.clamped(-50), 1)
        XCTAssertEqual(ReminderTimeLimits.clamped(1e21), 86_400)
        XCTAssertEqual(ReminderTimeLimits.clamped(TimeInterval(Int.max) * 60), 86_400)
    }

    func testNonFiniteValuesClampToMinimum() throws {
        XCTAssertEqual(ReminderTimeLimits.clamped(.infinity), 1)
        XCTAssertEqual(ReminderTimeLimits.clamped(-.infinity), 1)
        XCTAssertEqual(ReminderTimeLimits.clamped(.nan), 1)
    }
}

final class SnoozeDurationFormatterTests: XCTestCase {
    func testWholeMinutesUseMinuteWording() throws {
        XCTAssertEqual(SnoozeDurationFormatter.label(300), "5 minutes")
        XCTAssertEqual(SnoozeDurationFormatter.label(60), "1 minute")
    }

    func testNonWholeMinutesFallBackToSeconds() throws {
        XCTAssertEqual(SnoozeDurationFormatter.label(90), "90 seconds")
        XCTAssertEqual(SnoozeDurationFormatter.label(30), "30 seconds")
        XCTAssertEqual(SnoozeDurationFormatter.label(1), "1 second")
    }

    func testAbsurdPersistedDurationsDoNotTrap() throws {
        // A poisoned preference (e.g. Int.max minutes entered before clamping
        // existed) must render instead of crashing Int() conversion.
        XCTAssertEqual(SnoozeDurationFormatter.label(TimeInterval(Int.max) * 60), "1440 minutes")
        XCTAssertEqual(SnoozeDurationFormatter.label(.nan), "1 second")
    }
}

final class SnoozeNotificationActionTests: XCTestCase {
    func testIdentifierRoundTripsDuration() throws {
        let identifier = SnoozeNotificationAction.identifier(for: 300)

        XCTAssertEqual(SnoozeNotificationAction.duration(fromIdentifier: identifier), 300)
    }

    func testIdentifierEncodesWholeSeconds() throws {
        XCTAssertEqual(SnoozeNotificationAction.identifier(for: 90), "SNOOZE_ACTION:90")
    }

    func testIdentifierClampsAbsurdDurationsInsteadOfTrapping() throws {
        XCTAssertEqual(SnoozeNotificationAction.identifier(for: TimeInterval(Int.max) * 60), "SNOOZE_ACTION:86400")
        XCTAssertEqual(SnoozeNotificationAction.identifier(for: .infinity), "SNOOZE_ACTION:1")
    }

    func testNonSnoozeIdentifiersDecodeToNil() throws {
        XCTAssertNil(SnoozeNotificationAction.duration(fromIdentifier: "JOIN_MEETING"))
        XCTAssertNil(SnoozeNotificationAction.duration(fromIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"))
    }

    func testMalformedDurationsDecodeToNil() throws {
        XCTAssertNil(SnoozeNotificationAction.duration(fromIdentifier: "SNOOZE_ACTION:"))
        XCTAssertNil(SnoozeNotificationAction.duration(fromIdentifier: "SNOOZE_ACTION:abc"))
        XCTAssertNil(SnoozeNotificationAction.duration(fromIdentifier: "SNOOZE_ACTION:-5"))
        XCTAssertNil(SnoozeNotificationAction.duration(fromIdentifier: "SNOOZE_ACTION:0"))
    }
}
