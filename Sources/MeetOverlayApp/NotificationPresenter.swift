import AppKit
import MeetOverlayCore
import UserNotifications

private enum NotificationIdentifier {
    static let category = "MEETING_REMINDER"
    static let joinAction = "JOIN_MEETING"
    static let eventIDKey = "eventID"
    static let meetURLKey = "meetURL"
}

@MainActor
final class NotificationPresenter: NSObject {
    var onJoin: ((String, URL) -> Void)?
    var onSnooze: ((String, TimeInterval) -> Void)?

    // UNUserNotificationCenter aborts when the process is not a real .app bundle
    // (e.g. `swift run`), so notifications become a no-op there.
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : .current()
        super.init()

        guard let center else { return }

        registerCategory(snoozeOptions: [])
        center.delegate = self
    }

    private func registerCategory(snoozeOptions: [TimeInterval]) {
        guard let center else { return }

        var actions = [
            UNNotificationAction(
                identifier: NotificationIdentifier.joinAction,
                title: "Join Meeting",
                options: [.foreground]
            )
        ]

        for duration in snoozeOptions {
            actions.append(UNNotificationAction(
                identifier: SnoozeNotificationAction.identifier(for: duration),
                title: "Snooze \(SnoozeDurationFormatter.label(duration))",
                options: []
            ))
        }

        let category = UNNotificationCategory(
            identifier: NotificationIdentifier.category,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorizationDenied() async -> Bool {
        guard let center else { return false }
        return await center.notificationSettings().authorizationStatus == .denied
    }

    func showReminder(for meeting: JoinableMeeting, roomName: String?, snoozeOptions: [TimeInterval], now: Date) {
        guard let center else { return }

        // Categories are app-global, so refresh the action list to match the
        // currently configured snooze options before each delivery.
        registerCategory(snoozeOptions: snoozeOptions)

        let composed = MeetingNotificationComposer.content(
            meetingTitle: meeting.title,
            startDate: meeting.startDate,
            roomName: roomName,
            now: now
        )

        let content = UNMutableNotificationContent()
        content.title = composed.title
        content.body = composed.body
        content.sound = .default
        content.categoryIdentifier = NotificationIdentifier.category
        content.userInfo = [
            NotificationIdentifier.eventIDKey: meeting.eventID,
            NotificationIdentifier.meetURLKey: meeting.meetURL.absoluteString
        ]

        // The event ID as identifier makes a re-delivery replace the stale banner.
        center.add(UNNotificationRequest(identifier: meeting.eventID, content: content, trigger: nil))
    }

    func removeReminder(eventID: String) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [eventID])
        center.removeDeliveredNotifications(withIdentifiers: [eventID])
    }

    private func handleResponse(actionID: String, eventID: String?, urlString: String?) {
        guard let eventID else { return }

        if let duration = SnoozeNotificationAction.duration(fromIdentifier: actionID) {
            onSnooze?(eventID, duration)
            return
        }

        guard actionID == NotificationIdentifier.joinAction || actionID == UNNotificationDefaultActionIdentifier,
              let urlString,
              let url = URL(string: urlString),
              VideoCallLinkFinder.platform(for: url) != nil else {
            // The URL round-trips through notification userInfo, so re-validate
            // the host allowlist at the point of opening, not just at posting.
            return
        }

        onJoin?(eventID, url)
    }
}

extension NotificationPresenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // A menu bar app counts as foreground; show the banner anyway.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        let eventID = userInfo[NotificationIdentifier.eventIDKey] as? String
        let urlString = userInfo[NotificationIdentifier.meetURLKey] as? String

        Task { @MainActor [weak self] in
            self?.handleResponse(actionID: actionID, eventID: eventID, urlString: urlString)
        }

        completionHandler()
    }
}
