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
    private let airlock = BackToBackAirlock()
    private let menuPresenter = CalendarMenuPresenter()

    private var timer: Timer?
    private var isEnabled = true
    private var hasCalendarAccess = false
    private var visibleEventID: String?
    private var isPreviewVisible = false
    private var reminderState = MeetingReminderState()

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

        calendarEventSource.onEventStoreChanged = { [weak self] in
            self?.checkNow()
        }

        notificationPresenter.onJoin = { [weak self] eventID, url in
            self?.openMeetingLink(url)
            self?.joinVisibleMeeting(eventID)
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

    func previewReminder() {
        let now = Date()
        let preferences = preferencesStore.load()
        let sampleEvent = CalendarEventSnapshot(
            id: "preview",
            title: "Sample Meeting",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(30 * 60),
            isAllDay: false,
            participationStatus: .accepted,
            url: nil,
            notes: "https://meet.google.com/abc-defg-hij",
            location: nil
        )

        guard let meeting = JoinableMeeting.from(sampleEvent) else { return }

        let snoozeOptions = preferences.isSnoozeEnabled ? preferences.snoozeOptions.sorted() : []

        // Preview the reminder style the user actually has on: the fullscreen
        // overlay when enabled, otherwise a sample system notification (the gentle
        // channel). Showing a fullscreen sample while fullscreen is off would
        // demo something that never fires.
        if !preferences.isOverlayEnabled, preferences.isSystemNotificationEnabled {
            notificationPresenter.showReminder(
                for: meeting,
                roomName: nil,
                snoozeOptions: snoozeOptions,
                now: now
            )
            return
        }

        guard visibleEventID == nil, !isPreviewVisible else { return }

        isPreviewVisible = true
        overlayPresenter.show(
            meeting: meeting,
            reminderSound: ReminderSoundCatalog.sound(for: preferences.reminderSoundID),
            snoozeOptions: snoozeOptions,
            attendees: meeting.attendees,
            roomName: nil,
            onJoin: { [weak self] in self?.endPreview() },
            onSnooze: { [weak self] _ in self?.endPreview() },
            onDismiss: { [weak self] in self?.endPreview() }
        )
    }

    private func endPreview() {
        isPreviewVisible = false
        overlayPresenter.hide()
        checkNow()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNow()
            }
        }
        timer?.tolerance = 3
    }

    private func checkNow() {
        guard !isPreviewVisible else { return }

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
        let sections = menuPresenter.sections(
            now: now,
            events: events,
            hideFinishedEvents: preferences.hidesFinishedEvents,
            roomConfig: preferences.meetingRoomConfig
        )
        let menuBarPresentation = menuPresenter.menuBarPresentation(now: now, events: events)
        let emptyMessage = emptyMessage(for: preferences)

        guard isEnabled || notificationsEnabled else {
            visibleEventID = nil
            overlayPresenter.hide()
            statusMenu.update(
                status: "Reminders off",
                isEnabled: isEnabled,
                menuBarTitle: menuBarPresentation.title,
                menuBarUrgency: menuBarPresentation.urgency,
                sections: sections,
                emptyMessage: emptyMessage
            )
            return
        }

        let hiddenEventIDs = reminderState.hiddenEventIDs(now: now)

        // Back-to-back airlock is a fullscreen affordance, so it only runs when
        // the fullscreen overlay is enabled.
        if isEnabled, let transition = airlock.transition(
            now: now,
            events: events,
            hiddenEventIDs: hiddenEventIDs,
            dismissedTransitionEventIDs: reminderState.dismissedAirlockEventIDs
        ) {
            let meeting = transition.nextMeeting
            statusMenu.update(
                status: "Back-to-back: \(meeting.title)",
                isEnabled: isEnabled,
                menuBarTitle: menuBarPresentation.title,
                menuBarUrgency: menuBarPresentation.urgency,
                sections: sections,
                emptyMessage: emptyMessage
            )

            guard visibleEventID != meeting.eventID else {
                return
            }

            visibleEventID = meeting.eventID
            overlayPresenter.showAirlock(
                transition: transition,
                onJoin: { [weak self] in
                    self?.openMeetingLink(meeting.meetURL)
                    self?.joinVisibleMeeting(meeting.eventID)
                },
                onDismiss: { [weak self] in
                    self?.dismissAirlock(meeting.eventID)
                }
            )
            return
        }

        // The user-configured lead time drives the gentle stage; the fullscreen
        // stage still fires in the final minute (never later than the gentle one).
        let gentleLeadTime = ReminderTimeLimits.clamped(preferences.alertLeadTime)
        let ladder = MeetingAlertLadder(
            gentleLeadTime: gentleLeadTime,
            fullscreenLeadTime: min(60, gentleLeadTime)
        )
        let alert = ladder.alert(
            now: now,
            events: events,
            hiddenEventIDs: hiddenEventIDs,
            lateAlertExemptEventIDs: reminderState.expiredSnoozeEventIDs
        )

        guard let alert else {
            visibleEventID = nil
            overlayPresenter.hide()
            statusMenu.update(
                status: "No meeting soon",
                isEnabled: isEnabled,
                menuBarTitle: menuBarPresentation.title,
                menuBarUrgency: menuBarPresentation.urgency,
                sections: sections,
                emptyMessage: emptyMessage
            )
            return
        }

        let meeting = alert.meeting
        let roomPresentation = MeetingRoomResolver.resolve(
            attendees: meeting.attendees,
            location: meeting.location,
            config: preferences.meetingRoomConfig
        )
        let snoozeOptions = preferences.isSnoozeEnabled ? preferences.snoozeOptions.sorted() : []

        // The actionable system notification is the "gentle" channel: deliver it
        // once, as soon as the meeting enters the alert window, if enabled.
        if notificationsEnabled, reminderState.shouldDeliver(eventID: meeting.eventID, stage: .gentle) {
            reminderState.recordDelivery(eventID: meeting.eventID, stage: .gentle)
            notificationPresenter.showReminder(
                for: meeting,
                roomName: roomPresentation.roomName,
                snoozeOptions: snoozeOptions,
                now: now
            )
        }

        guard alert.stage == .fullscreen else {
            visibleEventID = nil
            overlayPresenter.hide()
            statusMenu.update(
                status: "Meeting soon: \(meeting.title)",
                isEnabled: isEnabled,
                menuBarTitle: menuBarPresentation.title,
                menuBarUrgency: menuBarPresentation.urgency,
                sections: sections,
                emptyMessage: emptyMessage
            )
            return
        }

        statusMenu.update(
            status: "Upcoming: \(meeting.title)",
            isEnabled: isEnabled,
            menuBarTitle: menuBarPresentation.title,
            menuBarUrgency: menuBarPresentation.urgency,
            sections: sections,
            emptyMessage: emptyMessage
        )

        guard isEnabled else {
            visibleEventID = nil
            overlayPresenter.hide()
            return
        }

        guard visibleEventID != meeting.eventID else {
            return
        }

        guard reminderState.shouldDeliver(eventID: meeting.eventID, stage: .fullscreen) else {
            return
        }

        visibleEventID = meeting.eventID
        reminderState.recordDelivery(eventID: meeting.eventID, stage: .fullscreen)
        overlayPresenter.show(
            meeting: meeting,
            reminderSound: ReminderSoundCatalog.sound(for: preferences.reminderSoundID),
            snoozeOptions: snoozeOptions,
            attendees: roomPresentation.attendees,
            roomName: roomPresentation.roomName,
            onJoin: { [weak self] in
                self?.openMeetingLink(meeting.meetURL)
                self?.joinVisibleMeeting(meeting.eventID)
            },
            onSnooze: { [weak self] duration in
                self?.snoozeVisibleMeeting(meeting.eventID, duration: duration)
            },
            onDismiss: { [weak self] in
                self?.dismissVisibleMeeting(meeting.eventID)
            }
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

    private func joinVisibleMeeting(_ eventID: String) {
        reminderState.join(eventID: eventID)
        notificationPresenter.removeReminder(eventID: eventID)
        hideVisibleMeeting()
        checkNow()
    }

    private func dismissVisibleMeeting(_ eventID: String) {
        reminderState.dismiss(eventID: eventID)
        notificationPresenter.removeReminder(eventID: eventID)
        hideVisibleMeeting()
        checkNow()
    }

    private func snoozeVisibleMeeting(_ eventID: String, duration: TimeInterval) {
        reminderState.snooze(eventID: eventID, until: Date().addingTimeInterval(duration))
        notificationPresenter.removeReminder(eventID: eventID)
        hideVisibleMeeting()
        checkNow()
    }

    private func dismissAirlock(_ eventID: String) {
        reminderState.dismissAirlock(eventID: eventID)
        hideVisibleMeeting()
        checkNow()
    }

    private func hideVisibleMeeting() {
        visibleEventID = nil
        overlayPresenter.hide()
    }
}
