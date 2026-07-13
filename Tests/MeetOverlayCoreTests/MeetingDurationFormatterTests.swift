import XCTest
@testable import MeetOverlayCore

final class MeetingDurationFormatterTests: XCTestCase {
    private let base = Date(timeIntervalSinceReferenceDate: 1_000)

    func testSubHourDurationsUseMinutes() throws {
        XCTAssertEqual(duration(minutes: 30), "30 min")
        XCTAssertEqual(duration(minutes: 45), "45 min")
        XCTAssertEqual(duration(minutes: 1), "1 min")
    }

    func testWholeHoursUseCompactHourForm() throws {
        XCTAssertEqual(duration(minutes: 60), "1h")
        XCTAssertEqual(duration(minutes: 120), "2h")
    }

    func testMixedDurationsCombineHoursAndMinutes() throws {
        XCTAssertEqual(duration(minutes: 90), "1h 30m")
        XCTAssertEqual(duration(minutes: 135), "2h 15m")
    }

    func testZeroOrNegativeDurationsReturnNil() throws {
        XCTAssertNil(duration(minutes: 0))
        XCTAssertNil(duration(minutes: -15))
    }

    func testSubMinuteDurationsRoundToNearestMinute() throws {
        XCTAssertEqual(
            MeetingDurationFormatter.text(startDate: base, endDate: base.addingTimeInterval(90)),
            "2 min"
        )
        XCTAssertNil(
            MeetingDurationFormatter.text(startDate: base, endDate: base.addingTimeInterval(20)),
            "Durations rounding to zero minutes show nothing"
        )
    }

    private func duration(minutes: Int) -> String? {
        MeetingDurationFormatter.text(startDate: base, endDate: base.addingTimeInterval(TimeInterval(minutes * 60)))
    }
}
