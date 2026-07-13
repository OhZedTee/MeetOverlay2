import AppKit
import MeetOverlayCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitorController: MeetingMonitorController?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusMenu = StatusMenuController()
        let calendarEventSource = CalendarEventSource()
        let overlayPresenter = OverlayPresenter()
        let notificationPresenter = NotificationPresenter()
        let preferencesStore = AppPreferencesStore()
        let loginItemController = LoginItemController()
        let browserLauncher = BrowserLauncher()

        let monitorController = MeetingMonitorController(
            calendarEventSource: calendarEventSource,
            overlayPresenter: overlayPresenter,
            notificationPresenter: notificationPresenter,
            statusMenu: statusMenu,
            preferencesStore: preferencesStore,
            browserLauncher: browserLauncher
        )
        let preferencesWindowController = PreferencesWindowController(
            calendarEventSource: calendarEventSource,
            preferencesStore: preferencesStore,
            loginItemController: loginItemController,
            notificationPresenter: notificationPresenter,
            browserLauncher: browserLauncher,
            onPreferencesChanged: { [weak monitorController] in
                monitorController?.refreshFromPreferences()
            }
        )

        statusMenu.onOpenPreferences = { [weak preferencesWindowController] in
            preferencesWindowController?.show()
        }

        self.monitorController = monitorController
        self.preferencesWindowController = preferencesWindowController
        monitorController.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
