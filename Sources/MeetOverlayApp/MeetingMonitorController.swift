import AppKit
import Foundation
import MeetOverlayCore

@MainActor
final class MeetingMonitorController {
    private let calendarEventSource: CalendarEventSource
    private let overlayPresenter: OverlayPresenter
    private let notificationPresenter: NotificationPresenter
    private let statusMenu: StatusMenuController
    private let preferencesStore: AppPreferencesStore
    private let browserLauncher: BrowserLauncher
    private let menuPresenter = CalendarMenuPresenter()

    private var timer: Timer?
    private var isEnabled = true
    private var hasCalendarAccess = false
    private var visibleEventID: String?
    private var suppressedEventIDs = Set<String>()
    private var snoozedUntil: [String: Date] = [:]
    private var notifiedEventIDs = Set<String>()

    init(
        calendarEventSource: CalendarEventSource,
        overlayPresenter: OverlayPresenter,
        notificationPresenter: NotificationPresenter,
        statusMenu: StatusMenuController,
        preferencesStore: AppPreferencesStore,
        browserLauncher: BrowserLauncher
    ) {
        self.calendarEventSource = calendarEventSource
        self.overlayPresenter = overlayPresenter
        self.notificationPresenter = notificationPresenter
        self.statusMenu = statusMenu
        self.preferencesStore = preferencesStore
        self.browserLauncher = browserLauncher
        self.isEnabled = preferencesStore.load().isOverlayEnabled

        statusMenu.onOpenCalendarSettings = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
            NSWorkspace.shared.open(url)
        }

        statusMenu.onOpenMeetLink = { [weak self] url in
            self?.openMeetingLink(url)
        }

        notificationPresenter.onJoin = { [weak self] eventID, url in
            self?.openMeetingLink(url)
            self?.suppressVisibleMeeting(eventID)
        }

        notificationPresenter.onSnooze = { [weak self] eventID, duration in
            self?.snoozeVisibleMeeting(eventID, duration: duration)
        }
    }

    func start() {
        statusMenu.update(status: "Requesting Calendar access", isEnabled: isEnabled)

        calendarEventSource.requestAccess { [weak self] granted in
            guard let self else { return }

            self.hasCalendarAccess = granted

            if granted {
                self.statusMenu.update(status: "Watching for meetings", isEnabled: self.isEnabled)
                self.startTimer()
                self.checkNow()
            } else {
                self.statusMenu.update(status: "Calendar access denied", isEnabled: self.isEnabled)
            }
        }
    }

    func refreshFromPreferences() {
        isEnabled = preferencesStore.load().isOverlayEnabled
        checkNow()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNow()
            }
        }
    }

    private func checkNow() {
        guard hasCalendarAccess else {
            statusMenu.update(
                status: "Calendar access needed",
                isEnabled: isEnabled,
                emptyMessage: "Allow Calendar access in System Settings",
                showsCalendarSettingsAction: true
            )
            return
        }

        let now = Date()
        let preferences = preferencesStore.load()
        isEnabled = preferences.isOverlayEnabled
        let notificationsEnabled = preferences.isSystemNotificationEnabled
        let events = eventsForMenu(now: now, preferences: preferences)
        pruneTrackedEventIDs(keeping: Set(events.map(\.id)))
        let sections = menuPresenter.sections(
            now: now,
            events: events,
            hideFinishedEvents: preferences.hidesFinishedEvents,
            roomConfig: preferences.meetingRoomConfig
        )
        let menuBarTitle = menuPresenter.menuBarTitle(now: now, events: events)
        let emptyMessage = emptyMessage(for: preferences)

        guard isEnabled || notificationsEnabled else {
            visibleEventID = nil
            overlayPresenter.hide()
            statusMenu.update(
                status: "Reminders off",
                isEnabled: isEnabled,
                menuBarTitle: menuBarTitle,
                sections: sections,
                emptyMessage: emptyMessage
            )
            return
        }

        let activelySnoozed = Set(snoozedUntil.filter { $0.value > now }.keys)
        let selector = MeetingAlertSelector(alertLeadTime: preferences.alertLeadTime)
        let meeting = selector.meetingToShow(now: now, events: events, suppressedEventIDs: suppressedEventIDs.union(activelySnoozed))

        guard let meeting else {
            visibleEventID = nil
            overlayPresenter.hide()
            statusMenu.update(
                status: "No meeting soon",
                isEnabled: isEnabled,
                menuBarTitle: menuBarTitle,
                sections: sections,
                emptyMessage: emptyMessage
            )
            return
        }

        statusMenu.update(
            status: "Upcoming: \(meeting.title)",
            isEnabled: isEnabled,
            menuBarTitle: menuBarTitle,
            sections: sections,
            emptyMessage: emptyMessage
        )

        let roomPresentation = MeetingRoomResolver.resolve(
            attendees: meeting.attendees,
            location: meeting.location,
            config: preferences.meetingRoomConfig
        )
        let snoozeOptions = preferences.isSnoozeEnabled ? preferences.snoozeOptions.sorted() : []

        if notificationsEnabled, !notifiedEventIDs.contains(meeting.eventID) {
            notifiedEventIDs.insert(meeting.eventID)
            notificationPresenter.showReminder(
                for: meeting,
                roomName: roomPresentation.roomName,
                snoozeOptions: snoozeOptions,
                now: now
            )
        }

        guard isEnabled else {
            visibleEventID = nil
            overlayPresenter.hide()
            return
        }

        guard visibleEventID != meeting.eventID else {
            return
        }

        visibleEventID = meeting.eventID
        overlayPresenter.show(
            meeting: meeting,
            onJoin: { [weak self] in
                self?.openMeetingLink(meeting.meetURL)
                self?.suppressVisibleMeeting(meeting.eventID)
            },
            onDismiss: { [weak self] in
                self?.suppressVisibleMeeting(meeting.eventID)
            },
            onSnooze: { [weak self] duration in
                self?.snoozeVisibleMeeting(meeting.eventID, duration: duration)
            },
            snoozeOptions: snoozeOptions,
            attendees: roomPresentation.attendees,
            roomName: roomPresentation.roomName
        )
    }

    private func openMeetingLink(_ url: URL) {
        browserLauncher.open(url, preferredBundleID: preferencesStore.load().preferredBrowserBundleID)
    }

    private func eventsForMenu(now: Date, preferences: AppPreferences) -> [CalendarEventSnapshot] {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: 2, to: startDate) ?? now.addingTimeInterval(48 * 60 * 60)
        let events = calendarEventSource.events(from: startDate, to: endDate)

        return CalendarEventFilter.events(events, selectedCalendarIDs: preferences.selectedCalendarIDs)
    }

    private func emptyMessage(for preferences: AppPreferences) -> String {
        if preferences.selectedCalendarIDs == [] {
            return "No calendars selected. Open Settings to choose calendars."
        }

        return "No selected-calendar events today or tomorrow"
    }

    // The suppression/snooze/notified sets only matter for events still in the
    // fetched window (today and tomorrow); dropping the rest keeps them from
    // growing for the lifetime of the process.
    private func pruneTrackedEventIDs(keeping currentEventIDs: Set<String>) {
        guard !currentEventIDs.isEmpty else { return }
        suppressedEventIDs.formIntersection(currentEventIDs)
        notifiedEventIDs.formIntersection(currentEventIDs)
        snoozedUntil = snoozedUntil.filter { currentEventIDs.contains($0.key) }
    }

    private func suppressVisibleMeeting(_ eventID: String) {
        suppressedEventIDs.insert(eventID)
        visibleEventID = nil
        overlayPresenter.hide()
        notificationPresenter.removeReminder(eventID: eventID)
        checkNow()
    }

    private func snoozeVisibleMeeting(_ eventID: String, duration: TimeInterval) {
        snoozedUntil[eventID] = Date().addingTimeInterval(duration)
        visibleEventID = nil
        overlayPresenter.hide()
        // A fresh notification should fire when the snooze expires.
        notifiedEventIDs.remove(eventID)
        notificationPresenter.removeReminder(eventID: eventID)
        checkNow()
    }
}
