import XCTest
@testable import MeetOverlayCore

final class MeetingRoomResolverTests: XCTestCase {

    // MARK: - firstMatch wildcard semantics

    func testPrefixWildcardMatchesRoom() {
        let match = MeetingRoomResolver.firstMatch(
            in: ["Alice", "MTL-5F-Boardroom", "Bob"],
            pattern: "MTL-*"
        )

        XCTAssertEqual(match, "MTL-5F-Boardroom")
    }

    func testMatchingIsCaseInsensitive() {
        let match = MeetingRoomResolver.firstMatch(
            in: ["mtl-5f-boardroom"],
            pattern: "MTL-*"
        )

        XCTAssertEqual(match, "mtl-5f-boardroom")
    }

    func testFirstMatchInListOrderWins() {
        let match = MeetingRoomResolver.firstMatch(
            in: ["MTL-2F-Huddle", "MTL-5F-Boardroom"],
            pattern: "MTL-*"
        )

        XCTAssertEqual(match, "MTL-2F-Huddle")
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        XCTAssertEqual(
            MeetingRoomResolver.firstMatch(in: ["Room-A"], pattern: "Room-?"),
            "Room-A"
        )
        XCTAssertNil(
            MeetingRoomResolver.firstMatch(in: ["Room-AB"], pattern: "Room-?")
        )
    }

    func testPatternWithoutWildcardRequiresWholeNameMatch() {
        XCTAssertEqual(
            MeetingRoomResolver.firstMatch(in: ["Boardroom"], pattern: "boardroom"),
            "Boardroom"
        )
        XCTAssertNil(
            MeetingRoomResolver.firstMatch(in: ["Boardroom 5F"], pattern: "Boardroom")
        )
    }

    func testEmptyPatternMatchesNothing() {
        XCTAssertNil(MeetingRoomResolver.firstMatch(in: ["Alice"], pattern: ""))
        XCTAssertNil(MeetingRoomResolver.firstMatch(in: ["Alice"], pattern: "   "))
    }

    // MARK: - resolve

    func testDisabledConfigPassesAttendeesThroughUnchanged() {
        let presentation = MeetingRoomResolver.resolve(
            attendees: ["Alice", "MTL-5F-Boardroom"],
            location: "MTL-5F-Boardroom",
            config: .disabled
        )

        XCTAssertNil(presentation.roomName)
        XCTAssertEqual(presentation.attendees, ["Alice", "MTL-5F-Boardroom"])
    }

    func testMatchedRoomIsCalledOutAndRemovedFromAttendees() {
        let presentation = MeetingRoomResolver.resolve(
            attendees: ["Alice", "MTL-5F-Boardroom", "Bob"],
            location: nil,
            config: MeetingRoomConfig(isEnabled: true, isRoomInAttendees: true, pattern: "MTL-*")
        )

        XCTAssertEqual(presentation.roomName, "MTL-5F-Boardroom")
        XCTAssertEqual(presentation.attendees, ["Alice", "Bob"])
    }

    func testNoMatchLeavesAttendeesUnchanged() {
        let presentation = MeetingRoomResolver.resolve(
            attendees: ["Alice", "Bob"],
            location: nil,
            config: MeetingRoomConfig(isEnabled: true, isRoomInAttendees: true, pattern: "MTL-*")
        )

        XCTAssertNil(presentation.roomName)
        XCTAssertEqual(presentation.attendees, ["Alice", "Bob"])
    }

    func testRoomNotInAttendeesUsesLocation() {
        let presentation = MeetingRoomResolver.resolve(
            attendees: ["Alice", "Bob"],
            location: "5th Floor Boardroom",
            config: MeetingRoomConfig(isEnabled: true, isRoomInAttendees: false, pattern: "MTL-*")
        )

        XCTAssertEqual(presentation.roomName, "5th Floor Boardroom")
        XCTAssertEqual(presentation.attendees, ["Alice", "Bob"])
    }

    func testLocationModeTrimsWhitespace() {
        let presentation = MeetingRoomResolver.resolve(
            attendees: [],
            location: "  5th Floor Boardroom \n",
            config: MeetingRoomConfig(isEnabled: true, isRoomInAttendees: false, pattern: "")
        )

        XCTAssertEqual(presentation.roomName, "5th Floor Boardroom")
    }

    func testLocationModeWithNilOrEmptyLocationHasNoRoom() {
        let config = MeetingRoomConfig(isEnabled: true, isRoomInAttendees: false, pattern: "")

        XCTAssertNil(MeetingRoomResolver.resolve(attendees: [], location: nil, config: config).roomName)
        XCTAssertNil(MeetingRoomResolver.resolve(attendees: [], location: "", config: config).roomName)
        XCTAssertNil(MeetingRoomResolver.resolve(attendees: [], location: "   ", config: config).roomName)
    }

    func testOnlyFirstMatchingOccurrenceIsRemoved() {
        let presentation = MeetingRoomResolver.resolve(
            attendees: ["MTL-2F-Huddle", "Alice", "MTL-5F-Boardroom"],
            location: nil,
            config: MeetingRoomConfig(isEnabled: true, isRoomInAttendees: true, pattern: "MTL-*")
        )

        XCTAssertEqual(presentation.roomName, "MTL-2F-Huddle")
        XCTAssertEqual(presentation.attendees, ["Alice", "MTL-5F-Boardroom"])
    }
}
