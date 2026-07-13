import Foundation

public enum AlertLeadTimeUnit: String, Codable, CaseIterable, Equatable {
    case minutes
    case seconds

    public func toSeconds(_ value: Double) -> TimeInterval {
        switch self {
        case .minutes: return value * 60
        case .seconds: return value
        }
    }

    public func fromSeconds(_ seconds: TimeInterval) -> Double {
        switch self {
        case .minutes: return seconds / 60
        case .seconds: return seconds
        }
    }
}

/// Bounds for user-entered reminder durations (alert lead time, snooze options).
/// Values outside the range — including non-finite ones — clamp into it, both at
/// the settings boundary and again before any Int conversion, since an absurd
/// persisted value would otherwise trap and crash-loop the app.
public enum ReminderTimeLimits {
    public static let minimum: TimeInterval = 1
    public static let maximum: TimeInterval = 86_400

    public static func clamped(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return minimum }
        return min(max(value, minimum), maximum)
    }
}

public enum SnoozeDurationFormatter {
    public static func label(_ duration: TimeInterval) -> String {
        let secs = Int(ReminderTimeLimits.clamped(duration))
        if secs >= 60, secs % 60 == 0 {
            let mins = secs / 60
            return "\(mins) \(mins == 1 ? "minute" : "minutes")"
        }
        return "\(secs) \(secs == 1 ? "second" : "seconds")"
    }
}

/// Encodes a snooze duration into a notification action identifier and back,
/// since per-action payloads can only ride the identifier string.
public enum SnoozeNotificationAction {
    public static let identifierPrefix = "SNOOZE_ACTION:"

    public static func identifier(for duration: TimeInterval) -> String {
        "\(identifierPrefix)\(Int(ReminderTimeLimits.clamped(duration).rounded()))"
    }

    public static func duration(fromIdentifier identifier: String) -> TimeInterval? {
        guard identifier.hasPrefix(identifierPrefix),
              let seconds = Int(identifier.dropFirst(identifierPrefix.count)),
              seconds > 0 else {
            return nil
        }

        return TimeInterval(seconds)
    }
}

public struct AppPreferences: Codable, Equatable {
    public var selectedCalendarIDs: Set<String>?
    public var isOverlayEnabled: Bool
    public var isSystemNotificationEnabled: Bool
    public var launchAtLogin: Bool
    public var hidesFinishedEvents: Bool
    public var alertLeadTime: TimeInterval
    public var alertLeadTimeUnit: AlertLeadTimeUnit
    public var isSnoozeEnabled: Bool
    public var snoozeOptions: [TimeInterval]
    public var isMeetingRoomCalloutEnabled: Bool
    public var isMeetingRoomInAttendees: Bool
    public var meetingRoomPattern: String
    /// Bundle identifier of the browser used to open meeting links.
    /// `nil` means the system default browser.
    public var preferredBrowserBundleID: String?

    public var meetingRoomConfig: MeetingRoomConfig {
        MeetingRoomConfig(
            isEnabled: isMeetingRoomCalloutEnabled,
            isRoomInAttendees: isMeetingRoomInAttendees,
            pattern: meetingRoomPattern
        )
    }

    public init(
        selectedCalendarIDs: Set<String>? = nil,
        isOverlayEnabled: Bool = true,
        isSystemNotificationEnabled: Bool = false,
        launchAtLogin: Bool = false,
        hidesFinishedEvents: Bool = true,
        alertLeadTime: TimeInterval = 900,
        alertLeadTimeUnit: AlertLeadTimeUnit = .minutes,
        isSnoozeEnabled: Bool = true,
        snoozeOptions: [TimeInterval] = [60, 120, 300, 600, 900],
        isMeetingRoomCalloutEnabled: Bool = false,
        isMeetingRoomInAttendees: Bool = true,
        meetingRoomPattern: String = "",
        preferredBrowserBundleID: String? = nil
    ) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.isOverlayEnabled = isOverlayEnabled
        self.isSystemNotificationEnabled = isSystemNotificationEnabled
        self.launchAtLogin = launchAtLogin
        self.hidesFinishedEvents = hidesFinishedEvents
        self.alertLeadTime = alertLeadTime
        self.alertLeadTimeUnit = alertLeadTimeUnit
        self.isSnoozeEnabled = isSnoozeEnabled
        self.snoozeOptions = snoozeOptions
        self.isMeetingRoomCalloutEnabled = isMeetingRoomCalloutEnabled
        self.isMeetingRoomInAttendees = isMeetingRoomInAttendees
        self.meetingRoomPattern = meetingRoomPattern
        self.preferredBrowserBundleID = preferredBrowserBundleID
    }

    private enum CodingKeys: String, CodingKey {
        case selectedCalendarIDs
        case isOverlayEnabled
        case isSystemNotificationEnabled
        case launchAtLogin
        case hidesFinishedEvents
        case alertLeadTime
        case alertLeadTimeUnit
        case isSnoozeEnabled
        case snoozeOptions
        case isMeetingRoomCalloutEnabled
        case isMeetingRoomInAttendees
        case meetingRoomPattern
        case preferredBrowserBundleID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedCalendarIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs)
        isOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .isOverlayEnabled) ?? true
        isSystemNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSystemNotificationEnabled) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hidesFinishedEvents = try container.decodeIfPresent(Bool.self, forKey: .hidesFinishedEvents) ?? true
        alertLeadTime = try container.decodeIfPresent(TimeInterval.self, forKey: .alertLeadTime) ?? 900
        alertLeadTimeUnit = try container.decodeIfPresent(AlertLeadTimeUnit.self, forKey: .alertLeadTimeUnit) ?? .minutes
        isSnoozeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSnoozeEnabled) ?? true
        snoozeOptions = try container.decodeIfPresent([TimeInterval].self, forKey: .snoozeOptions) ?? [60, 120, 300, 600, 900]
        isMeetingRoomCalloutEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMeetingRoomCalloutEnabled) ?? false
        isMeetingRoomInAttendees = try container.decodeIfPresent(Bool.self, forKey: .isMeetingRoomInAttendees) ?? true
        meetingRoomPattern = try container.decodeIfPresent(String.self, forKey: .meetingRoomPattern) ?? ""
        preferredBrowserBundleID = try container.decodeIfPresent(String.self, forKey: .preferredBrowserBundleID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try container.encode(isOverlayEnabled, forKey: .isOverlayEnabled)
        try container.encode(isSystemNotificationEnabled, forKey: .isSystemNotificationEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(hidesFinishedEvents, forKey: .hidesFinishedEvents)
        try container.encode(alertLeadTime, forKey: .alertLeadTime)
        try container.encode(alertLeadTimeUnit, forKey: .alertLeadTimeUnit)
        try container.encode(isSnoozeEnabled, forKey: .isSnoozeEnabled)
        try container.encode(snoozeOptions, forKey: .snoozeOptions)
        try container.encode(isMeetingRoomCalloutEnabled, forKey: .isMeetingRoomCalloutEnabled)
        try container.encode(isMeetingRoomInAttendees, forKey: .isMeetingRoomInAttendees)
        try container.encode(meetingRoomPattern, forKey: .meetingRoomPattern)
        try container.encodeIfPresent(preferredBrowserBundleID, forKey: .preferredBrowserBundleID)
    }
}

public struct MeetingRoomConfig: Equatable, Sendable {
    public let isEnabled: Bool
    public let isRoomInAttendees: Bool
    public let pattern: String

    public static let disabled = MeetingRoomConfig(isEnabled: false, isRoomInAttendees: true, pattern: "")

    public init(isEnabled: Bool, isRoomInAttendees: Bool, pattern: String) {
        self.isEnabled = isEnabled
        self.isRoomInAttendees = isRoomInAttendees
        self.pattern = pattern
    }
}

public struct MeetingRoomPresentation: Equatable {
    public let roomName: String?
    public let attendees: [String]

    public init(roomName: String?, attendees: [String]) {
        self.roomName = roomName
        self.attendees = attendees
    }
}

public enum MeetingRoomResolver {
    public static func resolve(
        attendees: [String],
        location: String?,
        config: MeetingRoomConfig
    ) -> MeetingRoomPresentation {
        guard config.isEnabled else {
            return MeetingRoomPresentation(roomName: nil, attendees: attendees)
        }

        guard config.isRoomInAttendees else {
            let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomName = (trimmedLocation?.isEmpty ?? true) ? nil : trimmedLocation
            return MeetingRoomPresentation(roomName: roomName, attendees: attendees)
        }

        guard let roomName = firstMatch(in: attendees, pattern: config.pattern),
              let roomIndex = attendees.firstIndex(of: roomName) else {
            return MeetingRoomPresentation(roomName: nil, attendees: attendees)
        }

        var remainingAttendees = attendees
        remainingAttendees.remove(at: roomIndex)
        return MeetingRoomPresentation(roomName: roomName, attendees: remainingAttendees)
    }

    public static func firstMatch(in attendees: [String], pattern: String) -> String? {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmedPattern.isEmpty else { return nil }

        let predicate = NSPredicate(format: "SELF LIKE[c] %@", trimmedPattern)
        return attendees.first { predicate.evaluate(with: $0) }
    }
}

public final class AppPreferencesStore {
    private let defaults: UserDefaults
    private let key = "appPreferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key) else {
            return AppPreferences()
        }

        return (try? JSONDecoder().decode(AppPreferences.self, from: data)) ?? AppPreferences()
    }

    public func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum EventParticipationStatus: Equatable {
    case unknown
    case accepted
    case tentative
    case declined
}

public struct CalendarEventSnapshot: Equatable {
    public let id: String
    public let calendarID: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let participationStatus: EventParticipationStatus
    public let url: URL?
    public let notes: String?
    public let location: String?
    public let attendees: [String]

    public init(
        id: String,
        calendarID: String = "",
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        participationStatus: EventParticipationStatus,
        url: URL?,
        notes: String?,
        location: String?,
        attendees: [String] = []
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.participationStatus = participationStatus
        self.url = url
        self.notes = notes
        self.location = location
        self.attendees = attendees
    }
}

public enum CalendarEventFilter {
    public static func events(
        _ events: [CalendarEventSnapshot],
        selectedCalendarIDs: Set<String>?
    ) -> [CalendarEventSnapshot] {
        guard let selectedCalendarIDs else {
            return events
        }

        return events.filter { selectedCalendarIDs.contains($0.calendarID) }
    }
}

public struct CalendarSnapshot: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let sourceTitle: String?

    public var displayTitle: String {
        guard let sourceTitle, !sourceTitle.isEmpty else {
            return title
        }

        return "\(title) - \(sourceTitle)"
    }

    public init(id: String, title: String, sourceTitle: String? = nil) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

public enum CalendarSelectionUpdater {
    public static func updatedSelection(
        currentSelection: Set<String>?,
        allCalendarIDs: Set<String>,
        calendarID: String,
        isSelected: Bool
    ) -> Set<String>? {
        var selection = currentSelection ?? allCalendarIDs

        if isSelected {
            selection.insert(calendarID)
        } else {
            selection.remove(calendarID)
        }

        return selection == allCalendarIDs ? nil : selection
    }
}

public struct JoinableMeeting: Equatable {
    public let eventID: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let meetURL: URL
    public let platform: VideoCallPlatform
    public let attendees: [String]
    public let location: String?
}

public struct MeetingAlertSelector {
    private let alertLeadTime: TimeInterval
    private let lateAlertGraceTime: TimeInterval

    public init(alertLeadTime: TimeInterval, lateAlertGraceTime: TimeInterval = 120) {
        self.alertLeadTime = alertLeadTime
        self.lateAlertGraceTime = lateAlertGraceTime
    }

    public func meetingToShow(
        now: Date,
        events: [CalendarEventSnapshot],
        suppressedEventIDs: Set<String>
    ) -> JoinableMeeting? {
        events
            .sorted { $0.startDate < $1.startDate }
            .compactMap { event -> JoinableMeeting? in
                guard event.endDate > now else { return nil }
                guard event.startDate <= now.addingTimeInterval(alertLeadTime) else { return nil }
                guard event.startDate >= now.addingTimeInterval(-lateAlertGraceTime) else { return nil }
                guard !event.isAllDay else { return nil }
                guard event.participationStatus != .declined else { return nil }
                guard !suppressedEventIDs.contains(event.id) else { return nil }

                let candidates = [event.url?.absoluteString, event.notes, event.location, event.title].compactMap { $0 }
                guard let link = VideoCallLinkFinder.firstLink(in: candidates) else { return nil }

                return JoinableMeeting(
                    eventID: event.id,
                    title: event.title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    meetURL: link.url,
                    platform: link.platform,
                    attendees: event.attendees,
                    location: event.location
                )
            }
            .first
    }
}

public struct CalendarMenuSection: Equatable {
    public let title: String
    public let rows: [CalendarMenuRow]
}

public struct CalendarMenuRow: Equatable {
    public let eventID: String
    public let title: String
    public let timeText: String
    public let durationText: String?
    public let hasMeetLink: Bool
    public let meetURL: URL?
    public let platform: VideoCallPlatform?
    public let attendees: [String]
    public let roomName: String?
}

public struct CalendarMenuPresenter {
    private let calendar: Calendar
    private let timeFormatter: DateFormatter
    private let menuBarTitleLimit = 24

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        self.timeFormatter = timeFormatter
    }

    public func sections(
        now: Date,
        events: [CalendarEventSnapshot],
        hideFinishedEvents: Bool = true,
        roomConfig: MeetingRoomConfig = .disabled
    ) -> [CalendarMenuSection] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let visibleEvents = hideFinishedEvents ? events.filter { $0.endDate > now } : events

        return [
            section(title: "Today's Events", day: now, events: visibleEvents, roomConfig: roomConfig),
            section(title: "Tomorrow's Events", day: tomorrow, events: visibleEvents, roomConfig: roomConfig)
        ].compactMap { section in
            section.rows.isEmpty ? nil : section
        }
    }

    public func menuBarTitle(now: Date, events: [CalendarEventSnapshot]) -> String {
        guard let event = events
            .filter({ calendar.isDate($0.startDate, inSameDayAs: now) })
            .filter({ !$0.isAllDay })
            .filter({ $0.endDate > now })
            .sorted(by: { $0.startDate < $1.startDate })
            .first else {
            return "Meet"
        }

        let secondsUntilStart = Int(event.startDate.timeIntervalSince(now).rounded(.up))

        if secondsUntilStart <= 0 {
            return "\(shortTitle(event.title)) now"
        }

        let minutesUntilStart = max(1, Int(ceil(Double(secondsUntilStart) / 60)))
        if minutesUntilStart >= 120 {
            let hoursUntilStart = minutesUntilStart / 60
            return "\(shortTitle(event.title)) in \(hoursUntilStart) hours"
        }

        return "\(shortTitle(event.title)) in \(minutesUntilStart) \(minutesUntilStart == 1 ? "minute" : "minutes")"
    }

    private func shortTitle(_ title: String) -> String {
        guard title.count > menuBarTitleLimit else {
            return title
        }

        return "\(title.prefix(menuBarTitleLimit - 3))..."
    }

    private func section(title: String, day: Date, events: [CalendarEventSnapshot], roomConfig: MeetingRoomConfig) -> CalendarMenuSection {
        let rows = events
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
            .map { row(for: $0, roomConfig: roomConfig) }

        return CalendarMenuSection(title: title, rows: rows)
    }

    private func row(for event: CalendarEventSnapshot, roomConfig: MeetingRoomConfig) -> CalendarMenuRow {
        let link = VideoCallLinkFinder.firstLink(in: [event.url?.absoluteString, event.notes, event.location, event.title].compactMap { $0 })
        let roomPresentation = MeetingRoomResolver.resolve(
            attendees: event.attendees,
            location: event.location,
            config: roomConfig
        )

        return CalendarMenuRow(
            eventID: event.id,
            title: event.title,
            timeText: event.isAllDay ? "All-day" : timeFormatter.string(from: event.startDate),
            durationText: event.isAllDay ? nil : MeetingDurationFormatter.text(startDate: event.startDate, endDate: event.endDate),
            hasMeetLink: link != nil,
            meetURL: link?.url,
            platform: link?.platform,
            attendees: roomPresentation.attendees,
            roomName: roomPresentation.roomName
        )
    }
}

public enum MeetingCountdownFormatter {
    public static func text(now: Date, startDate: Date) -> String {
        let seconds = Int(startDate.timeIntervalSince(now).rounded(.up))

        if seconds < 0 {
            let elapsedSeconds = abs(seconds)

            if elapsedSeconds < 60 {
                return "Started just now"
            }

            let elapsedMinutes = Int(ceil(Double(elapsedSeconds) / 60))
            return "Started \(elapsedMinutes) \(elapsedMinutes == 1 ? "minute" : "minutes") ago"
        }

        if seconds == 0 {
            return "Starts now"
        }

        if seconds < 60 {
            return "Starts in \(seconds) seconds"
        }

        let minutes = Int(ceil(Double(seconds) / 60))
        return "Starts in \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}

public enum MeetingDurationFormatter {
    public static func text(startDate: Date, endDate: Date) -> String? {
        let totalMinutes = Int((endDate.timeIntervalSince(startDate) / 60).rounded())
        guard totalMinutes > 0 else { return nil }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }
}

public struct MeetingNotificationContent: Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum MeetingNotificationComposer {
    public static func content(
        meetingTitle: String,
        startDate: Date,
        roomName: String?,
        now: Date
    ) -> MeetingNotificationContent {
        let countdown = MeetingCountdownFormatter.text(now: now, startDate: startDate)
        let body = roomName.map { "\(countdown) · \($0)" } ?? countdown
        return MeetingNotificationContent(title: meetingTitle, body: body)
    }
}

public enum VideoCallPlatform: String, CaseIterable, Equatable, Sendable {
    case googleMeet
    case zoom
    case microsoftTeams
    case webex

    public var displayName: String {
        switch self {
        case .googleMeet: return "Google Meet"
        case .zoom: return "Zoom"
        case .microsoftTeams: return "Microsoft Teams"
        case .webex: return "Webex"
        }
    }
}

public struct VideoCallLink: Equatable {
    public let url: URL
    public let platform: VideoCallPlatform

    public init(url: URL, platform: VideoCallPlatform) {
        self.url = url
        self.platform = platform
    }
}

public enum VideoCallLinkFinder {
    public static func firstLink(in candidates: [String]) -> VideoCallLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        for candidate in candidates {
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            let matches = detector.matches(in: candidate, options: [], range: range)

            for match in matches {
                guard let url = match.url, let platform = platform(for: url) else { continue }
                return VideoCallLink(url: url, platform: platform)
            }
        }

        return nil
    }

    public static func platform(for url: URL) -> VideoCallPlatform? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else {
            return nil
        }

        if host == "meet.google.com" {
            return .googleMeet
        }

        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return .zoom
        }

        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return .microsoftTeams
        }

        if host == "webex.com" || host.hasSuffix(".webex.com") {
            return .webex
        }

        return nil
    }
}
