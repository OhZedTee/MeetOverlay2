import AppKit
import MeetOverlayCore

@MainActor
final class StatusMenuController: NSObject {
    var onOpenPreferences: (() -> Void)?
    var onOpenCalendarSettings: (() -> Void)?
    var onOpenMeetLink: ((URL) -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let preferencesItem = NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ",")
    private let calendarSettingsItem = NSMenuItem(title: "Open Calendar Privacy Settings...", action: #selector(openCalendarSettings), keyEquivalent: "")

    private var sections: [CalendarMenuSection] = []
    private var emptyMessage = "No events today or tomorrow"
    private var showsCalendarSettingsAction = false

    override init() {
        super.init()

        statusItem.button?.title = "Meet"
        statusItem.button?.setAccessibilityLabel("MeetOverlay")
        statusItem.button?.setAccessibilityHelp("Opens upcoming calendar events and meeting reminder settings.")
        preferencesItem.target = self
        calendarSettingsItem.target = self

        statusItem.menu = menu
        rebuildMenu()
    }

    func update(
        status: String,
        isEnabled: Bool,
        menuBarTitle: String = "Meet",
        sections: [CalendarMenuSection] = [],
        emptyMessage: String = "No events today or tomorrow",
        showsCalendarSettingsAction: Bool = false
    ) {
        self.sections = sections
        self.emptyMessage = emptyMessage
        self.showsCalendarSettingsAction = showsCalendarSettingsAction
        statusItem.button?.title = menuBarTitle
        statusItem.button?.setAccessibilityLabel("MeetOverlay, \(menuBarTitle), \(status). Opens meeting menu.")
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if sections.isEmpty {
            let emptyItem = NSMenuItem(title: emptyMessage, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            if showsCalendarSettingsAction {
                menu.addItem(calendarSettingsItem)
            }
        } else {
            for section in sections {
                addSection(section)
            }
        }

        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addSection(_ section: CalendarMenuSection) {
        let headerItem = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for row in section.rows {
            let timePart = row.durationText.map { "\(row.timeText) · \($0)" } ?? row.timeText
            let title = "\(timePart)  \(row.title)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.image = NSImage(
                systemSymbolName: row.hasMeetLink ? "video.fill" : "calendar",
                accessibilityDescription: row.platform.map { "\($0.displayName) link" } ?? "Calendar event"
            )

            if let submenu = detailSubmenu(for: row) {
                // A submenu suppresses the item's own click action, so Join moves inside it.
                item.submenu = submenu
            } else if let meetURL = row.meetURL {
                item.action = #selector(openMeetLink)
                item.target = self
                item.representedObject = meetURL
            } else {
                item.isEnabled = true
            }

            menu.addItem(item)
        }
    }

    private func detailSubmenu(for row: CalendarMenuRow) -> NSMenu? {
        guard !row.attendees.isEmpty || row.roomName != nil else {
            return nil
        }

        let submenu = NSMenu()

        if let meetURL = row.meetURL {
            let joinTitle = row.platform.map { "Join \($0.displayName)" } ?? "Join Meeting"
            let joinItem = NSMenuItem(title: joinTitle, action: #selector(openMeetLink), keyEquivalent: "")
            joinItem.target = self
            joinItem.representedObject = meetURL
            joinItem.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: joinTitle)
            submenu.addItem(joinItem)
            submenu.addItem(.separator())
        }

        if let roomName = row.roomName {
            let roomItem = NSMenuItem(title: roomName, action: nil, keyEquivalent: "")
            roomItem.image = NSImage(systemSymbolName: "door.left.hand.open", accessibilityDescription: "Meeting room")
            submenu.addItem(roomItem)
            submenu.addItem(.separator())
        }

        if !row.attendees.isEmpty {
            let headerItem = NSMenuItem(
                title: "\(row.attendees.count) \(row.attendees.count == 1 ? "Attendee" : "Attendees")",
                action: nil,
                keyEquivalent: ""
            )
            headerItem.isEnabled = false
            submenu.addItem(headerItem)

            for attendee in row.attendees {
                let attendeeItem = NSMenuItem(title: attendee, action: nil, keyEquivalent: "")
                attendeeItem.image = NSImage(systemSymbolName: "person", accessibilityDescription: nil)
                attendeeItem.indentationLevel = 1
                submenu.addItem(attendeeItem)
            }
        }

        return submenu
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func openCalendarSettings() {
        onOpenCalendarSettings?()
    }

    @objc private func openMeetLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenMeetLink?(url)
    }
}
