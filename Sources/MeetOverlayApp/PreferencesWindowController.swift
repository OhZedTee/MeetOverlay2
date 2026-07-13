import AppKit
import MeetOverlayCore
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private let calendarEventSource: CalendarEventSource
    private let preferencesStore: AppPreferencesStore
    private let loginItemController: LoginItemController
    private let notificationPresenter: NotificationPresenter
    private let browserLauncher: BrowserLauncher
    private let onPreferencesChanged: () -> Void

    private var window: NSWindow?
    private var viewModel: PreferencesViewModel?

    init(
        calendarEventSource: CalendarEventSource,
        preferencesStore: AppPreferencesStore,
        loginItemController: LoginItemController,
        notificationPresenter: NotificationPresenter,
        browserLauncher: BrowserLauncher,
        onPreferencesChanged: @escaping () -> Void
    ) {
        self.calendarEventSource = calendarEventSource
        self.preferencesStore = preferencesStore
        self.loginItemController = loginItemController
        self.notificationPresenter = notificationPresenter
        self.browserLauncher = browserLauncher
        self.onPreferencesChanged = onPreferencesChanged
    }

    func show() {
        let viewModel = PreferencesViewModel(
            calendars: calendarEventSource.calendars(),
            preferencesStore: preferencesStore,
            loginItemController: loginItemController,
            notificationPresenter: notificationPresenter,
            browserLauncher: browserLauncher,
            onPreferencesChanged: onPreferencesChanged
        )
        let contentView = SettingsView(viewModel: viewModel)

        if let window {
            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            window.title = "Settings"
            window.minSize = NSSize(width: 560, height: 520)
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }

        self.viewModel = viewModel
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class PreferencesViewModel: ObservableObject {
    let calendars: [CalendarSnapshot]

    @Published var selectedCalendarIDs: Set<String>?
    @Published var isOverlayEnabled: Bool
    @Published var isSystemNotificationEnabled: Bool
    @Published var notificationPermissionDenied = false
    @Published var hidesFinishedEvents: Bool
    @Published var launchAtLogin: Bool
    @Published var alertLeadTime: TimeInterval
    @Published var alertLeadTimeUnit: AlertLeadTimeUnit
    @Published var isSnoozeEnabled: Bool
    @Published var snoozeOptions: [TimeInterval]
    @Published var isMeetingRoomCalloutEnabled: Bool
    @Published var isMeetingRoomInAttendees: Bool
    @Published var meetingRoomPattern: String
    @Published var preferredBrowserBundleID: String?
    @Published var loginItemStatus: String
    @Published var errorMessage: String?

    let availableBrowsers: [InstalledBrowser]
    private let defaultBrowserName: String?

    var systemDefaultBrowserLabel: String {
        guard let defaultBrowserName else { return "System Default" }
        return "System Default (\(defaultBrowserName))"
    }

    var needsStartupAttention: Bool {
        !["Enabled", "Disabled"].contains(loginItemStatus)
    }

    var calendarSelectionSummary: String {
        guard !calendars.isEmpty else {
            return "No calendars available."
        }

        guard let selectedCalendarIDs else {
            return "Using all \(calendars.count) calendars, including calendars added later."
        }

        return "\(selectedCalendarIDs.count) of \(calendars.count) calendars selected."
    }

    var allVisibleCalendarsSelected: Bool {
        selectedCalendarIDs == nil || selectedCalendarIDs == Set(calendars.map(\.id))
    }

    var noCalendarsSelected: Bool {
        selectedCalendarIDs == []
    }

    private let preferencesStore: AppPreferencesStore
    private let loginItemController: LoginItemController
    private let notificationPresenter: NotificationPresenter
    private let onPreferencesChanged: () -> Void

    init(
        calendars: [CalendarSnapshot],
        preferencesStore: AppPreferencesStore,
        loginItemController: LoginItemController,
        notificationPresenter: NotificationPresenter,
        browserLauncher: BrowserLauncher,
        onPreferencesChanged: @escaping () -> Void
    ) {
        let preferences = preferencesStore.load()

        self.calendars = calendars
        self.availableBrowsers = browserLauncher.availableBrowsers()
        self.defaultBrowserName = browserLauncher.defaultBrowserName()
        self.preferredBrowserBundleID = preferences.preferredBrowserBundleID
        self.selectedCalendarIDs = preferences.selectedCalendarIDs
        self.isOverlayEnabled = preferences.isOverlayEnabled
        self.isSystemNotificationEnabled = preferences.isSystemNotificationEnabled
        self.hidesFinishedEvents = preferences.hidesFinishedEvents
        self.alertLeadTime = preferences.alertLeadTime
        self.alertLeadTimeUnit = preferences.alertLeadTimeUnit
        self.isSnoozeEnabled = preferences.isSnoozeEnabled
        self.snoozeOptions = preferences.snoozeOptions.sorted()
        self.isMeetingRoomCalloutEnabled = preferences.isMeetingRoomCalloutEnabled
        self.isMeetingRoomInAttendees = preferences.isMeetingRoomInAttendees
        self.meetingRoomPattern = preferences.meetingRoomPattern
        self.launchAtLogin = loginItemController.isEnabled
        self.loginItemStatus = loginItemController.statusText
        self.preferencesStore = preferencesStore
        self.loginItemController = loginItemController
        self.notificationPresenter = notificationPresenter
        self.onPreferencesChanged = onPreferencesChanged

        if preferences.isSystemNotificationEnabled {
            Task { [weak self] in
                let denied = await notificationPresenter.isAuthorizationDenied()
                self?.notificationPermissionDenied = denied
            }
        }
    }

    func isCalendarSelected(_ calendarID: String) -> Bool {
        selectedCalendarIDs?.contains(calendarID) ?? true
    }

    func setOverlayEnabled(_ isEnabled: Bool) {
        isOverlayEnabled = isEnabled
        savePreferences()
    }

    func setSystemNotificationEnabled(_ isEnabled: Bool) {
        isSystemNotificationEnabled = isEnabled
        savePreferences()

        guard isEnabled else {
            notificationPermissionDenied = false
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let granted = await self.notificationPresenter.requestAuthorization()
            self.notificationPermissionDenied = !granted
        }
    }

    func setHidesFinishedEvents(_ isEnabled: Bool) {
        hidesFinishedEvents = isEnabled
        savePreferences()
    }

    func setAlertLeadTimeDisplayValue(_ value: Double) {
        alertLeadTime = ReminderTimeLimits.clamped(alertLeadTimeUnit.toSeconds(max(1, value)))
        savePreferences()
    }

    func setAlertLeadTimeUnit(_ unit: AlertLeadTimeUnit) {
        alertLeadTimeUnit = unit
        savePreferences()
    }

    func setSnoozeEnabled(_ enabled: Bool) {
        isSnoozeEnabled = enabled
        savePreferences()
    }

    func addSnoozeOption(_ duration: TimeInterval) {
        let clamped = ReminderTimeLimits.clamped(duration)
        guard !snoozeOptions.contains(clamped) else { return }
        snoozeOptions.append(clamped)
        snoozeOptions.sort()
        savePreferences()
    }

    func removeSnoozeOption(_ duration: TimeInterval) {
        snoozeOptions.removeAll { $0 == duration }
        savePreferences()
    }

    func setMeetingRoomCalloutEnabled(_ enabled: Bool) {
        isMeetingRoomCalloutEnabled = enabled
        savePreferences()
    }

    func setMeetingRoomInAttendees(_ inAttendees: Bool) {
        isMeetingRoomInAttendees = inAttendees
        savePreferences()
    }

    func setMeetingRoomPattern(_ pattern: String) {
        meetingRoomPattern = pattern
        savePreferences()
    }

    func setPreferredBrowser(_ bundleID: String?) {
        preferredBrowserBundleID = bundleID
        savePreferences()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItemController.setEnabled(isEnabled)
            launchAtLogin = loginItemController.isEnabled
            loginItemStatus = loginItemController.statusText
            errorMessage = nil
        } catch {
            launchAtLogin = loginItemController.isEnabled
            loginItemStatus = loginItemController.statusText
            errorMessage = "Could not update startup setting: \(error.localizedDescription)"
        }

        savePreferences()
    }

    func setCalendar(_ calendarID: String, isSelected: Bool) {
        selectedCalendarIDs = CalendarSelectionUpdater.updatedSelection(
            currentSelection: selectedCalendarIDs,
            allCalendarIDs: Set(calendars.map(\.id)),
            calendarID: calendarID,
            isSelected: isSelected
        )
        savePreferences()
    }

    func selectAllCalendars() {
        selectedCalendarIDs = nil
        savePreferences()
    }

    func selectNoCalendars() {
        selectedCalendarIDs = []
        savePreferences()
    }

    private func savePreferences() {
        let preferences = AppPreferences(
            selectedCalendarIDs: selectedCalendarIDs,
            isOverlayEnabled: isOverlayEnabled,
            isSystemNotificationEnabled: isSystemNotificationEnabled,
            launchAtLogin: launchAtLogin,
            hidesFinishedEvents: hidesFinishedEvents,
            alertLeadTime: alertLeadTime,
            alertLeadTimeUnit: alertLeadTimeUnit,
            isSnoozeEnabled: isSnoozeEnabled,
            snoozeOptions: snoozeOptions,
            isMeetingRoomCalloutEnabled: isMeetingRoomCalloutEnabled,
            isMeetingRoomInAttendees: isMeetingRoomInAttendees,
            meetingRoomPattern: meetingRoomPattern,
            preferredBrowserBundleID: preferredBrowserBundleID
        )

        preferencesStore.save(preferences)
        onPreferencesChanged()
    }
}

private struct SettingsView: View {
    @StateObject private var viewModel: PreferencesViewModel

    init(viewModel: PreferencesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        TabView {
            GeneralSettingsView(
                viewModel: viewModel,
                launchAtLoginBinding: launchAtLoginBinding,
                overlayBinding: overlayBinding,
                systemNotificationBinding: systemNotificationBinding,
                hidesFinishedEventsBinding: hidesFinishedEventsBinding,
                alertLeadTimeValueBinding: alertLeadTimeValueBinding,
                alertLeadTimeUnitBinding: alertLeadTimeUnitBinding,
                isSnoozeEnabledBinding: isSnoozeEnabledBinding,
                meetingRoomCalloutBinding: meetingRoomCalloutBinding,
                meetingRoomInAttendeesBinding: meetingRoomInAttendeesBinding,
                meetingRoomPatternBinding: meetingRoomPatternBinding,
                preferredBrowserBinding: preferredBrowserBinding
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            CalendarSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Calendars", systemImage: "calendar")
                }
        }
        .tint(MeetOverlayTheme.Palette.accent)
        .padding(MeetOverlayTheme.Spacing.xLarge)
        .frame(minWidth: 560, minHeight: 520, alignment: .topLeading)
        .background(MeetOverlayTheme.Palette.settingsBackground)
    }

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isOverlayEnabled },
            set: { viewModel.setOverlayEnabled($0) }
        )
    }

    private var systemNotificationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isSystemNotificationEnabled },
            set: { viewModel.setSystemNotificationEnabled($0) }
        )
    }

    private var hidesFinishedEventsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hidesFinishedEvents },
            set: { viewModel.setHidesFinishedEvents($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    private var alertLeadTimeValueBinding: Binding<Double> {
        Binding(
            get: { viewModel.alertLeadTimeUnit.fromSeconds(viewModel.alertLeadTime) },
            set: { viewModel.setAlertLeadTimeDisplayValue($0) }
        )
    }

    private var alertLeadTimeUnitBinding: Binding<AlertLeadTimeUnit> {
        Binding(
            get: { viewModel.alertLeadTimeUnit },
            set: { viewModel.setAlertLeadTimeUnit($0) }
        )
    }

    private var isSnoozeEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isSnoozeEnabled },
            set: { viewModel.setSnoozeEnabled($0) }
        )
    }

    private var meetingRoomCalloutBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isMeetingRoomCalloutEnabled },
            set: { viewModel.setMeetingRoomCalloutEnabled($0) }
        )
    }

    private var meetingRoomInAttendeesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isMeetingRoomInAttendees },
            set: { viewModel.setMeetingRoomInAttendees($0) }
        )
    }

    private var meetingRoomPatternBinding: Binding<String> {
        Binding(
            get: { viewModel.meetingRoomPattern },
            set: { viewModel.setMeetingRoomPattern($0) }
        )
    }

    private var preferredBrowserBinding: Binding<String?> {
        Binding(
            get: { viewModel.preferredBrowserBundleID },
            set: { viewModel.setPreferredBrowser($0) }
        )
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    let launchAtLoginBinding: Binding<Bool>
    let overlayBinding: Binding<Bool>
    let systemNotificationBinding: Binding<Bool>
    let hidesFinishedEventsBinding: Binding<Bool>
    let alertLeadTimeValueBinding: Binding<Double>
    let alertLeadTimeUnitBinding: Binding<AlertLeadTimeUnit>
    let isSnoozeEnabledBinding: Binding<Bool>
    let meetingRoomCalloutBinding: Binding<Bool>
    let meetingRoomInAttendeesBinding: Binding<Bool>
    let meetingRoomPatternBinding: Binding<String>
    let preferredBrowserBinding: Binding<String?>

    private var anyReminderStyleEnabled: Bool {
        viewModel.isOverlayEnabled || viewModel.isSystemNotificationEnabled
    }

    var body: some View {
        ScrollView {
            content
                .padding(MeetOverlayTheme.Spacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(
                title: "General",
                subtitle: "Keep the menu quiet and the reminder behavior predictable."
            )

            SettingsCard(
                systemImage: "power",
                title: "Startup",
                description: "Control whether MeetOverlay is ready after sign-in."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open at Login", isOn: launchAtLoginBinding)

                    if viewModel.needsStartupAttention {
                        Text("Startup: \(viewModel.loginItemStatus)")
                            .font(MeetOverlayTheme.Typography.helper.weight(.medium))
                            .foregroundStyle(MeetOverlayTheme.Palette.attention)
                    }
                }
            }

            SettingsCard(
                systemImage: "bell.and.waves.left.and.right",
                title: "Reminders",
                description: "Reminders appear only for joinable Google Meet events."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show fullscreen reminders", isOn: overlayBinding)

                    Toggle("Show system notifications", isOn: systemNotificationBinding)

                    if viewModel.notificationPermissionDenied {
                        Text("Notifications for MeetOverlay are turned off. Allow them in System Settings → Notifications.")
                            .font(MeetOverlayTheme.Typography.helper.weight(.medium))
                            .foregroundStyle(MeetOverlayTheme.Palette.attention)
                    }

                    HStack(spacing: 8) {
                        Text("Alert me")
                            .foregroundStyle(anyReminderStyleEnabled ? .primary : .secondary)
                        TextField("", value: alertLeadTimeValueBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Picker("", selection: alertLeadTimeUnitBinding) {
                            Text("minutes").tag(AlertLeadTimeUnit.minutes)
                            Text("seconds").tag(AlertLeadTimeUnit.seconds)
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        Text("before meeting")
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!anyReminderStyleEnabled)

                    Divider()

                    Toggle("Enable snooze", isOn: isSnoozeEnabledBinding)
                        .disabled(!viewModel.isOverlayEnabled)

                    if viewModel.isSnoozeEnabled && viewModel.isOverlayEnabled {
                        SnoozeOptionsEditor(viewModel: viewModel)
                            .padding(.top, 2)
                    }
                }
            }

            SettingsCard(
                systemImage: "safari",
                title: "Meeting Links",
                description: "Choose which browser opens meeting links when you join."
            ) {
                HStack(spacing: 8) {
                    Text("Open links in")
                    Picker("", selection: preferredBrowserBinding) {
                        Text(viewModel.systemDefaultBrowserLabel).tag(String?.none)
                        if !viewModel.availableBrowsers.isEmpty {
                            Divider()
                            ForEach(viewModel.availableBrowsers) { browser in
                                Text(browser.name).tag(Optional(browser.bundleID))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(
                systemImage: "door.left.hand.open",
                title: "Meeting Rooms",
                description: "Call out the booked room on reminders and in the menu."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Call out meeting room", isOn: meetingRoomCalloutBinding)

                    if viewModel.isMeetingRoomCalloutEnabled {
                        Toggle("Room appears in the attendee list", isOn: meetingRoomInAttendeesBinding)

                        if viewModel.isMeetingRoomInAttendees {
                            HStack(spacing: 8) {
                                Text("Room name pattern")
                                TextField("e.g. MTL-*", text: meetingRoomPatternBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 180)
                            }

                            Text("* matches any characters, ? matches one. The first matching attendee is shown as the room.")
                                .font(MeetOverlayTheme.Typography.helper)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("The event's location is used as the room name.")
                                .font(MeetOverlayTheme.Typography.helper)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsCard(
                systemImage: "menubar.rectangle",
                title: "Menu",
                description: "Keep the menu focused on events that still matter."
            ) {
                Toggle("Hide finished events", isOn: hidesFinishedEventsBinding)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(MeetOverlayTheme.Typography.helper)
                    .foregroundStyle(MeetOverlayTheme.Palette.warning)
            }
        }
    }
}

private struct CalendarSettingsView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        ScrollView {
            content
                .padding(MeetOverlayTheme.Spacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPageHeader(
                title: "Calendars",
                subtitle: "Choose which synced calendars can appear in the menu and trigger reminders."
            )

            SettingsCard(
                systemImage: "calendar",
                title: "Included Calendars",
                description: "Using all calendars also includes calendars added later."
            ) {
                CalendarSelectionView(viewModel: viewModel)
            }
        }
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.xSmall) {
            Text(title)
                .font(MeetOverlayTheme.Typography.pageTitle)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(MeetOverlayTheme.Typography.helper)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let systemImage: String
    let title: String
    let description: String?
    @ViewBuilder let content: Content

    init(
        systemImage: String,
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: MeetOverlayTheme.Spacing.medium) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MeetOverlayTheme.Palette.accent)
                    .frame(
                        width: MeetOverlayTheme.Size.settingsIconBadge,
                        height: MeetOverlayTheme.Size.settingsIconBadge
                    )
                    .background(
                        RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.iconBadge)
                            .fill(MeetOverlayTheme.Palette.iconBadgeBackground)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(MeetOverlayTheme.Typography.sectionTitle)
                        .foregroundStyle(.primary)

                    if let description {
                        Text(description)
                            .font(MeetOverlayTheme.Typography.helper)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(MeetOverlayTheme.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.card)
                .fill(MeetOverlayTheme.Palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.card)
                .stroke(MeetOverlayTheme.Palette.border, lineWidth: 1)
        )
    }
}

private struct SnoozeOptionsEditor: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var newValue: Int = 5
    @State private var newUnit: AlertLeadTimeUnit = .minutes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Snooze options")
                .font(MeetOverlayTheme.Typography.helper.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(viewModel.snoozeOptions, id: \.self) { duration in
                    HStack {
                        Text(SnoozeDurationFormatter.label(duration))
                            .font(.body)
                        Spacer()
                        Button {
                            viewModel.removeSnoozeOption(duration)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(MeetOverlayTheme.Palette.warning)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                    if duration != viewModel.snoozeOptions.last {
                        Divider().padding(.horizontal, 10)
                    }
                }

                if viewModel.snoozeOptions.isEmpty {
                    Text("No snooze options — add one below.")
                        .font(MeetOverlayTheme.Typography.helper)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("", value: $newValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                    Picker("", selection: $newUnit) {
                        Text("minutes").tag(AlertLeadTimeUnit.minutes)
                        Text("seconds").tag(AlertLeadTimeUnit.seconds)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    Spacer()
                    Button {
                        let duration = newUnit.toSeconds(Double(max(1, newValue)))
                        viewModel.addSnoozeOption(duration)
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(MeetOverlayTheme.Typography.helper.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MeetOverlayTheme.Palette.accent)
                    .disabled(newValue <= 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .background(
                RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.inset)
                    .fill(MeetOverlayTheme.Palette.insetBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.inset)
                    .stroke(MeetOverlayTheme.Palette.mutedBorder, lineWidth: 1)
            )
        }
    }
}

private struct CalendarSelectionView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.calendarSelectionSummary)
                    .font(MeetOverlayTheme.Typography.helper)
                    .foregroundStyle(viewModel.noCalendarsSelected ? MeetOverlayTheme.Palette.warning : .secondary)

                Spacer()

                Button("Use All Calendars") {
                    viewModel.selectAllCalendars()
                }
                .disabled(viewModel.allVisibleCalendarsSelected)

                Button("Deselect All") {
                    viewModel.selectNoCalendars()
                }
                .disabled(viewModel.noCalendarsSelected)
            }
            .controlSize(.small)

            if viewModel.noCalendarsSelected {
                Text("Warning: no calendars selected. Meeting reminders will not trigger.")
                    .font(MeetOverlayTheme.Typography.helper)
                    .foregroundStyle(MeetOverlayTheme.Palette.warning)
            }

            if viewModel.calendars.isEmpty {
                Text("No calendars available. Allow Calendar access in System Settings.")
                    .font(MeetOverlayTheme.Typography.helper)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.calendars) { calendar in
                            CalendarToggleRow(viewModel: viewModel, calendar: calendar)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MeetOverlayTheme.Spacing.medium)
                }
                .frame(minHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.inset)
                        .fill(MeetOverlayTheme.Palette.insetBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.inset)
                        .stroke(MeetOverlayTheme.Palette.mutedBorder, lineWidth: 1)
                )
            }
        }
    }
}

private struct CalendarToggleRow: View {
    @ObservedObject var viewModel: PreferencesViewModel
    let calendar: CalendarSnapshot

    var body: some View {
        Toggle(calendar.displayTitle, isOn: isSelectedBinding)
            .font(.body)
    }

    private var isSelectedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isCalendarSelected(calendar.id) },
            set: { viewModel.setCalendar(calendar.id, isSelected: $0) }
        )
    }
}
