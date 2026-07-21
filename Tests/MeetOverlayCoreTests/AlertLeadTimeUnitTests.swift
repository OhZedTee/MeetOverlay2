import XCTest
@testable import MeetOverlayCore

final class AlertLeadTimeUnitTests: XCTestCase {

    // MARK: - toSeconds

    func testMinutesToSecondsConvertsCorrectly() {
        XCTAssertEqual(AlertLeadTimeUnit.minutes.toSeconds(15), 900)
    }

    func testMinutesToSecondsWithFractionalValue() {
        XCTAssertEqual(AlertLeadTimeUnit.minutes.toSeconds(1.5), 90)
    }

    func testSecondsToSecondsIsIdentity() {
        XCTAssertEqual(AlertLeadTimeUnit.seconds.toSeconds(300), 300)
    }

    func testMinutesToSecondsWithZero() {
        XCTAssertEqual(AlertLeadTimeUnit.minutes.toSeconds(0), 0)
    }

    // MARK: - fromSeconds

    func testFromSecondsToMinutesConvertsCorrectly() {
        XCTAssertEqual(AlertLeadTimeUnit.minutes.fromSeconds(900), 15)
    }

    func testFromSecondsToSecondsIsIdentity() {
        XCTAssertEqual(AlertLeadTimeUnit.seconds.fromSeconds(300), 300)
    }

    func testFromSecondsToMinutesWithNonWholeMinutes() {
        XCTAssertEqual(AlertLeadTimeUnit.minutes.fromSeconds(90), 1.5)
    }

    // MARK: - Round-trip

    func testMinutesRoundTrip() {
        let original: Double = 20
        let roundTripped = AlertLeadTimeUnit.minutes.fromSeconds(
            AlertLeadTimeUnit.minutes.toSeconds(original)
        )
        XCTAssertEqual(roundTripped, original)
    }

    func testSecondsRoundTrip() {
        let original: Double = 450
        let roundTripped = AlertLeadTimeUnit.seconds.fromSeconds(
            AlertLeadTimeUnit.seconds.toSeconds(original)
        )
        XCTAssertEqual(roundTripped, original)
    }

    // MARK: - Unit switching preserves underlying seconds value

    func testSwitchingUnitDoesNotChangeRepresentedDuration() {
        let leadTimeInSeconds: TimeInterval = 900

        let asMinutes = AlertLeadTimeUnit.minutes.fromSeconds(leadTimeInSeconds)
        let backToSeconds = AlertLeadTimeUnit.minutes.toSeconds(asMinutes)

        XCTAssertEqual(backToSeconds, leadTimeInSeconds,
            "Converting 900s → minutes → seconds should still be 900s")
    }
}
