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
    private let onPreviewReminder: () -> Void

    private var window: NSWindow?
    private var viewModel: PreferencesViewModel?

    init(
        calendarEventSource: CalendarEventSource,
        preferencesStore: AppPreferencesStore,
        loginItemController: LoginItemController,
        notificationPresenter: NotificationPresenter,
        browserLauncher: BrowserLauncher,
        onPreferencesChanged: @escaping () -> Void,
        onPreviewReminder: @escaping () -> Void
    ) {
        self.calendarEventSource = calendarEventSource
        self.preferencesStore = preferencesStore
        self.loginItemController = loginItemController
        self.notificationPresenter = notificationPresenter
        self.browserLauncher = browserLauncher
        self.onPreferencesChanged = onPreferencesChanged
        self.onPreviewReminder = onPreviewReminder
    }

    func show() {
        let now = Date()
        let preferences = preferencesStore.load()
        let calendarAccessStatus = calendarEventSource.calendarAccessStatus
        let calendars = calendarEventSource.calendars()
        let diagnosticEvents = eventsForDiagnostics(now: now, calendarAccessStatus: calendarAccessStatus)
        let viewModel = PreferencesViewModel(
            calendars: calendars,
            calendarAccessStatus: calendarAccessStatus,
            diagnosticEvents: diagnosticEvents,
            initialPreferences: preferences,
            preferencesStore: preferencesStore,
            loginItemController: loginItemController,
            notificationPresenter: notificationPresenter,
            browserLauncher: browserLauncher,
            onPreferencesChanged: onPreferencesChanged,
            onPreviewReminder: onPreviewReminder
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

            window.title = "MeetOverlay Settings"
            window.minSize = NSSize(width: 560, height: 520)
            window.tabbingMode = .disallowed
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.setFrameAutosaveName("MeetOverlaySettings")
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }

        self.viewModel = viewModel
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func eventsForDiagnostics(
        now: Date,
        calendarAccessStatus: CalendarAccessDiagnosticState
    ) -> [CalendarEventSnapshot] {
        guard calendarAccessStatus == .allowed else {
            return []
        }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: 2, to: startDate) ?? now.addingTimeInterval(48 * 60 * 60)
        return calendarEventSource.events(from: startDate, to: endDate)
    }
}

@MainActor
private final class PreferencesViewModel: ObservableObject {
    let calendars: [CalendarSnapshot]
    let calendarAccessStatus: CalendarAccessDiagnosticState
    let diagnosticEvents: [CalendarEventSnapshot]

    @Published var selectedCalendarIDs: Set<String>?
    @Published var isOverlayEnabled: Bool
    @Published var isSystemNotificationEnabled: Bool
    @Published var notificationPermissionDenied = false
    @Published var hidesFinishedEvents: Bool
    @Published var launchAtLogin: Bool
    @Published var reminderSoundID: String
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

    let reminderSounds = ReminderSoundCatalog.sounds
    let availableBrowsers: [InstalledBrowser]
    private let defaultBrowserName: String?

    var systemDefaultBrowserLabel: String {
        guard let defaultBrowserName else { return "System Default" }
        return "System Default (\(defaultBrowserName))"
    }

    var needsStartupAttention: Bool {
        !calendarSyncDiagnostic.launchAtLogin.isHealthy
    }

    var anyReminderStyleEnabled: Bool {
        isOverlayEnabled || isSystemNotificationEnabled
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

    var calendarSyncDiagnostic: CalendarSyncDiagnostic {
        CalendarSyncDiagnostic.summary(
            calendarAccess: calendarAccessStatus,
            calendars: calendars,
            selectedCalendarIDs: selectedCalendarIDs,
            launchAtLoginStatus: loginItemStatus,
            now: Date(),
            events: diagnosticEvents
        )
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
    private let reminderSoundPlayer = ReminderSoundPlayer()
    private let onPreferencesChanged: () -> Void
    private let onPreviewReminder: () -> Void

    init(
        calendars: [CalendarSnapshot],
        calendarAccessStatus: CalendarAccessDiagnosticState,
        diagnosticEvents: [CalendarEventSnapshot],
        initialPreferences: AppPreferences,
        preferencesStore: AppPreferencesStore,
        loginItemController: LoginItemController,
        notificationPresenter: NotificationPresenter,
        browserLauncher: BrowserLauncher,
        onPreferencesChanged: @escaping () -> Void,
        onPreviewReminder: @escaping () -> Void
    ) {
        self.calendars = calendars
        self.calendarAccessStatus = calendarAccessStatus
        self.diagnosticEvents = diagnosticEvents
        self.selectedCalendarIDs = initialPreferences.selectedCalendarIDs
        self.isOverlayEnabled = initialPreferences.isOverlayEnabled
        self.isSystemNotificationEnabled = initialPreferences.isSystemNotificationEnabled
        self.hidesFinishedEvents = initialPreferences.hidesFinishedEvents
        self.reminderSoundID = initialPreferences.reminderSoundID
        self.alertLeadTime = initialPreferences.alertLeadTime
        self.alertLeadTimeUnit = initialPreferences.alertLeadTimeUnit
        self.isSnoozeEnabled = initialPreferences.isSnoozeEnabled
        self.snoozeOptions = initialPreferences.snoozeOptions.sorted()
        self.isMeetingRoomCalloutEnabled = initialPreferences.isMeetingRoomCalloutEnabled
        self.isMeetingRoomInAttendees = initialPreferences.isMeetingRoomInAttendees
        self.meetingRoomPattern = initialPreferences.meetingRoomPattern
        self.preferredBrowserBundleID = initialPreferences.preferredBrowserBundleID
        self.launchAtLogin = loginItemController.isEnabled
        self.loginItemStatus = loginItemController.statusText
        self.availableBrowsers = browserLauncher.availableBrowsers()
        self.defaultBrowserName = browserLauncher.defaultBrowserName()
        self.preferencesStore = preferencesStore
        self.loginItemController = loginItemController
        self.notificationPresenter = notificationPresenter
        self.onPreferencesChanged = onPreferencesChanged
        self.onPreviewReminder = onPreviewReminder

        if initialPreferences.isSystemNotificationEnabled {
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

    func setReminderSound(_ soundID: String) {
        reminderSoundID = soundID
        savePreferences()
    }

    func previewReminderSound() {
        reminderSoundPlayer.play(ReminderSoundCatalog.sound(for: reminderSoundID))
    }

    func previewReminder() {
        onPreviewReminder()
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
            reminderSoundID: reminderSoundID,
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
            GeneralSettingsView(viewModel: viewModel)
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
}

private struct GeneralSettingsView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.large) {
                SettingsPageHeader(
                    title: "General",
                    subtitle: "Keep the menu quiet and the reminder behavior predictable."
                )

                startupCard
                remindersCard
                meetingLinksCard
                meetingRoomsCard
                menuCard

                SettingsCard(
                    systemImage: "stethoscope",
                    title: "Sync Doctor",
                    description: "Whether MeetOverlay is ready to catch your next meeting."
                ) {
                    SyncDoctorView(diagnostic: viewModel.calendarSyncDiagnostic)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(MeetOverlayTheme.Typography.helper)
                        .foregroundStyle(MeetOverlayTheme.Palette.warning)
                }
            }
            .padding(MeetOverlayTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var startupCard: some View {
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
    }

    private var remindersCard: some View {
        SettingsCard(
            systemImage: "bell.and.waves.left.and.right",
            title: "Reminders",
            description: "Reminders appear only for joinable video meetings."
        ) {
            VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.medium) {
                Toggle("Show fullscreen reminders", isOn: overlayBinding)

                Toggle("Show system notifications", isOn: systemNotificationBinding)

                if viewModel.notificationPermissionDenied {
                    Text("Notifications for MeetOverlay are turned off. Allow them in System Settings → Notifications.")
                        .font(MeetOverlayTheme.Typography.helper.weight(.medium))
                        .foregroundStyle(MeetOverlayTheme.Palette.attention)
                }

                HStack(spacing: 8) {
                    Text("Alert me")
                        .foregroundStyle(viewModel.anyReminderStyleEnabled ? .primary : .secondary)
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
                .disabled(!viewModel.anyReminderStyleEnabled)

                HStack(spacing: MeetOverlayTheme.Spacing.small) {
                    Picker("Sound", selection: reminderSoundBinding) {
                        ForEach(viewModel.reminderSounds) { sound in
                            Text(sound.title).tag(sound.id)
                        }
                    }
                    .frame(maxWidth: 280)

                    Button("Preview") {
                        viewModel.previewReminderSound()
                    }
                }

                Text("Used by fullscreen reminders. Back-to-back airlock stays silent.")
                    .font(MeetOverlayTheme.Typography.helper)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Enable snooze", isOn: isSnoozeEnabledBinding)
                    .disabled(!viewModel.isOverlayEnabled)

                if viewModel.isSnoozeEnabled && viewModel.isOverlayEnabled {
                    SnoozeOptionsEditor(viewModel: viewModel)
                        .padding(.top, 2)
                }

                Button("Show Sample Reminder") {
                    viewModel.previewReminder()
                }
            }
        }
    }

    private var meetingLinksCard: some View {
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
    }

    private var meetingRoomsCard: some View {
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
    }

    private var menuCard: some View {
        SettingsCard(
            systemImage: "menubar.rectangle",
            title: "Menu",
            description: "Keep the menu focused on events that still matter."
        ) {
            Toggle("Hide finished events", isOn: hidesFinishedEventsBinding)
        }
    }

    private var overlayBinding: Binding<Bool> {
        Binding(get: { viewModel.isOverlayEnabled }, set: { viewModel.setOverlayEnabled($0) })
    }

    private var systemNotificationBinding: Binding<Bool> {
        Binding(get: { viewModel.isSystemNotificationEnabled }, set: { viewModel.setSystemNotificationEnabled($0) })
    }

    private var hidesFinishedEventsBinding: Binding<Bool> {
        Binding(get: { viewModel.hidesFinishedEvents }, set: { viewModel.setHidesFinishedEvents($0) })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { viewModel.launchAtLogin }, set: { viewModel.setLaunchAtLogin($0) })
    }

    private var reminderSoundBinding: Binding<String> {
        Binding(get: { viewModel.reminderSoundID }, set: { viewModel.setReminderSound($0) })
    }

    private var alertLeadTimeValueBinding: Binding<Double> {
        Binding(
            get: { viewModel.alertLeadTimeUnit.fromSeconds(viewModel.alertLeadTime) },
            set: { viewModel.setAlertLeadTimeDisplayValue($0) }
        )
    }

    private var alertLeadTimeUnitBinding: Binding<AlertLeadTimeUnit> {
        Binding(get: { viewModel.alertLeadTimeUnit }, set: { viewModel.setAlertLeadTimeUnit($0) })
    }

    private var isSnoozeEnabledBinding: Binding<Bool> {
        Binding(get: { viewModel.isSnoozeEnabled }, set: { viewModel.setSnoozeEnabled($0) })
    }

    private var meetingRoomCalloutBinding: Binding<Bool> {
        Binding(get: { viewModel.isMeetingRoomCalloutEnabled }, set: { viewModel.setMeetingRoomCalloutEnabled($0) })
    }

    private var meetingRoomInAttendeesBinding: Binding<Bool> {
        Binding(get: { viewModel.isMeetingRoomInAttendees }, set: { viewModel.setMeetingRoomInAttendees($0) })
    }

    private var meetingRoomPatternBinding: Binding<String> {
        Binding(get: { viewModel.meetingRoomPattern }, set: { viewModel.setMeetingRoomPattern($0) })
    }

    private var preferredBrowserBinding: Binding<String?> {
        Binding(get: { viewModel.preferredBrowserBundleID }, set: { viewModel.setPreferredBrowser($0) })
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

private struct CalendarSettingsView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.large) {
                SettingsPageHeader(
                    title: "Calendars",
                    subtitle: "Choose which synced calendars can appear in the menu and trigger reminders."
                )

                SettingsCard(
                    systemImage: "calendar",
                    title: "Included Calendars",
                    description: "Using all calendars also includes calendars added later."
                ) {
                    VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.medium) {
                        if let problem = viewModel.calendarSyncDiagnostic.problem {
                            CalendarSyncProblemBanner(problem: problem)
                        }

                        CalendarSelectionView(viewModel: viewModel)
                    }
                }
            }
            .padding(MeetOverlayTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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

private struct SyncDoctorView: View {
    let diagnostic: CalendarSyncDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.medium) {
            if let problem = diagnostic.problem {
                CalendarSyncProblemBanner(problem: problem)
            }

            VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.small) {
                SyncDoctorRow(item: diagnostic.calendarAccess)
                SyncDoctorRow(item: diagnostic.includedCalendars)
                SyncDoctorRow(item: diagnostic.launchAtLogin)
                SyncDoctorRow(item: diagnostic.nextMeet)
            }
        }
    }
}

private struct SyncDoctorRow: View {
    let item: CalendarSyncDiagnosticItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MeetOverlayTheme.Spacing.small) {
            Image(systemName: item.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(MeetOverlayTheme.Typography.helper.weight(.semibold))
                .foregroundStyle(item.isHealthy ? MeetOverlayTheme.Palette.healthy : MeetOverlayTheme.Palette.attention)
                .frame(width: MeetOverlayTheme.Size.settingsStatusIcon)
                .accessibilityLabel(item.isHealthy ? "OK" : "Needs attention")

            Text(item.title)
                .font(MeetOverlayTheme.Typography.helper)
                .foregroundStyle(.secondary)
                .fixedSize()

            Spacer(minLength: MeetOverlayTheme.Spacing.medium)

            Text(item.value)
                .font(MeetOverlayTheme.Typography.helper.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }
}

private struct CalendarSyncProblemBanner: View {
    let problem: CalendarSyncDiagnosticProblem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MeetOverlayTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(MeetOverlayTheme.Typography.helper.weight(.semibold))
                .foregroundStyle(MeetOverlayTheme.Palette.attention)

            Text(problem.message)
                .font(MeetOverlayTheme.Typography.helper)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.inset)
                .fill(MeetOverlayTheme.Palette.attention.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.inset)
                .stroke(MeetOverlayTheme.Palette.attention.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct CalendarSelectionView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.medium) {
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

            if !viewModel.calendars.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MeetOverlayTheme.Spacing.small) {
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
