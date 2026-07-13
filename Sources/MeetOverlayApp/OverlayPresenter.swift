import AppKit
import MeetOverlayCore
import SwiftUI

@MainActor
final class OverlayPresenter {
    private var windows: [NSWindow] = []
    private let reminderSoundPlayer = ReminderSoundPlayer()

    func show(
        meeting: JoinableMeeting,
        reminderSound: ReminderSound,
        snoozeOptions: [TimeInterval],
        attendees: [String],
        roomName: String?,
        onJoin: @escaping () -> Void,
        onSnooze: @escaping (TimeInterval) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        hide()
        reminderSoundPlayer.play(reminderSound)

        present(
            MeetingOverlayView(
                meeting: meeting,
                snoozeOptions: snoozeOptions,
                attendees: attendees,
                roomName: roomName,
                onJoin: onJoin,
                onSnooze: onSnooze,
                onDismiss: onDismiss
            ),
            onDismiss: onDismiss,
            // S snoozes by the shortest configured option; nil leaves the key inert.
            onSnoozeKey: snoozeOptions.first.map { duration in { onSnooze(duration) } }
        )
    }

    func showAirlock(
        transition: BackToBackTransition,
        onJoin: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        hide()
        present(
            BackToBackAirlockView(
                transition: transition,
                onJoin: onJoin,
                onDismiss: onDismiss
            ),
            onDismiss: onDismiss
        )
    }

    func hide() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func present<Content: View>(
        _ contentView: Content,
        onDismiss: @escaping () -> Void,
        onSnoozeKey: (() -> Void)? = nil
    ) {
        let activeScreen = NSScreen.main ?? NSScreen.screens.first

        // The overlay should become key on the screen the cursor is already on,
        // so keyboard shortcuts and the pointer land where the user is looking.
        let mouseLocation = NSEvent.mouseLocation
        var keyWindow: NSWindow?

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            window.onDismiss = onDismiss
            window.onSnoozeKey = onSnoozeKey
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isReleasedWhenClosed = false

            if screen == activeScreen {
                window.contentView = NSHostingView(rootView: contentView)
            } else {
                window.contentView = NSHostingView(rootView: SecondaryScreenScrimView())
            }

            window.orderFrontRegardless()
            windows.append(window)

            if NSMouseInRect(mouseLocation, screen.frame, false) {
                keyWindow = window
            }
        }

        // Activate first so the app owns the cursor and controls render active,
        // then promote exactly one window to key (a per-window makeKey in the
        // loop would leave whichever screen happened to be last as the key one).
        NSApplication.shared.activate(ignoringOtherApps: true)
        (keyWindow ?? windows.first)?.makeKeyAndOrderFront(nil)

        // The previously-active app may have hidden the pointer (full-screen
        // video, slideshow); reveal it so the user can aim before clicking.
        NSCursor.setHiddenUntilMouseMoves(false)
    }

}

private struct SecondaryScreenScrimView: View {
    var body: some View {
        MeetOverlayTheme.Palette.overlayScrim.ignoresSafeArea()
    }
}

@MainActor
private final class OverlayWindow: NSWindow {
    var onDismiss: (() -> Void)?
    var onSnoozeKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }

        if let onSnoozeKey,
           event.charactersIgnoringModifiers?.lowercased() == "s",
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            onSnoozeKey()
            return
        }

        super.keyDown(with: event)
    }
}

private struct OverlayPrimaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat = 150

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, minWidth: minWidth)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let minWidth: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(MeetOverlayTheme.Typography.overlayButton.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 26)
                .padding(.vertical, 17)
                .frame(minWidth: minWidth)
                .background(
                    Capsule()
                        .fill(MeetOverlayTheme.Palette.accent)
                        .overlay(Capsule().fill(highlight))
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? MeetOverlayTheme.Motion.pressedScale : 1)
                .animation(.easeOut(duration: MeetOverlayTheme.Motion.hoverDuration), value: isHovered)
                .animation(.easeOut(duration: MeetOverlayTheme.Motion.pressDuration), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }

        private var highlight: Color {
            if configuration.isPressed {
                return MeetOverlayTheme.Palette.overlayPrimaryPressedShade
            }

            return isHovered ? MeetOverlayTheme.Palette.overlayPrimaryHoverHighlight : .clear
        }
    }
}

private struct OverlaySecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, compact: compact)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let compact: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(compact ? MeetOverlayTheme.Typography.overlayCompactButton : MeetOverlayTheme.Typography.overlaySecondaryButton)
                .foregroundStyle(
                    isHovered
                        ? MeetOverlayTheme.Palette.overlayText
                        : MeetOverlayTheme.Palette.overlaySecondaryText
                )
                .padding(.horizontal, compact ? 14 : 16)
                .padding(.vertical, compact ? 7 : 14)
                .frame(minWidth: compact ? 0 : 96)
                .background(Capsule().fill(fill))
                .overlay(
                    Capsule()
                        .stroke(
                            isHovered ? MeetOverlayTheme.Palette.overlaySecondaryHoverBorder : MeetOverlayTheme.Palette.overlayPanelBorder,
                            lineWidth: 1
                        )
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? MeetOverlayTheme.Motion.pressedScale : 1)
                .animation(.easeOut(duration: MeetOverlayTheme.Motion.hoverDuration), value: isHovered)
                .animation(.easeOut(duration: MeetOverlayTheme.Motion.pressDuration), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }

        private var fill: Color {
            if configuration.isPressed {
                return MeetOverlayTheme.Palette.overlaySecondaryPressedFill
            }

            return isHovered ? MeetOverlayTheme.Palette.overlaySecondaryHoverFill : MeetOverlayTheme.Palette.overlayPanel
        }
    }
}

private struct KeycapHint: View {
    enum Tone {
        case onPanel
        case onAccent
    }

    let symbol: String
    var tone: Tone = .onPanel

    var body: some View {
        Text(symbol)
            .font(MeetOverlayTheme.Typography.overlayKeycap)
            .foregroundStyle(
                tone == .onAccent
                    ? MeetOverlayTheme.Palette.overlayKeycapOnAccentText
                    : MeetOverlayTheme.Palette.overlayTertiaryText
            )
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(tone == .onAccent ? MeetOverlayTheme.Palette.overlayKeycapOnAccentFill : MeetOverlayTheme.Palette.overlayKeycapFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(tone == .onAccent ? Color.clear : MeetOverlayTheme.Palette.overlayKeycapBorder, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private struct OverlayBackdropView: View {
    var body: some View {
        LinearGradient(
            colors: [MeetOverlayTheme.Palette.overlayStart, MeetOverlayTheme.Palette.overlayEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct OverlayPanelModifier: ViewModifier {
    let maxWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MeetOverlayTheme.Spacing.overlayPanelHorizontal)
            .padding(.vertical, MeetOverlayTheme.Spacing.overlayPanelVertical)
            .frame(maxWidth: maxWidth)
            .background(
                RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.overlayPanel)
                    .fill(MeetOverlayTheme.Palette.overlayPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.overlayPanel)
                    .stroke(MeetOverlayTheme.Palette.overlayPanelBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 30, y: 18)
            .padding(48)
            .opacity(hasEntered ? 1 : 0)
            .scaleEffect(hasEntered || reduceMotion ? 1 : MeetOverlayTheme.Motion.overlayEntranceScale)
            .onAppear {
                withAnimation(.easeOut(duration: MeetOverlayTheme.Motion.overlayEntranceDuration)) {
                    hasEntered = true
                }
            }
    }
}

extension View {
    fileprivate func overlayPanel(maxWidth: CGFloat) -> some View {
        modifier(OverlayPanelModifier(maxWidth: maxWidth))
    }
}

private func meetingTimeRangeText(from startDate: Date, to endDate: Date) -> String {
    "\(startDate.formatted(date: .omitted, time: .shortened)) to \(endDate.formatted(date: .omitted, time: .shortened))"
}

private struct MeetingOverlayView: View {
    let meeting: JoinableMeeting
    let snoozeOptions: [TimeInterval]
    let attendees: [String]
    let roomName: String?
    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            OverlayBackdropView()

            VStack(spacing: MeetOverlayTheme.Spacing.overlayContent) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 12) {
                        Text(MeetingCountdownFormatter.text(now: context.date, startDate: meeting.startDate))
                            .font(MeetOverlayTheme.Typography.overlayStatus)
                            .monospacedDigit()
                            .foregroundStyle(
                                context.date >= meeting.startDate
                                    ? MeetOverlayTheme.Palette.attention
                                    : MeetOverlayTheme.Palette.accent
                            )

                        Text(meeting.title)
                            .font(MeetOverlayTheme.Typography.overlayTitle)
                            .foregroundStyle(MeetOverlayTheme.Palette.overlayText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)

                        Label(
                            meetingTimeRangeText(from: meeting.startDate, to: meeting.endDate),
                            systemImage: "clock"
                        )
                        .font(MeetOverlayTheme.Typography.overlayMetadata)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)
                    }
                }

                if let roomName {
                    Label(roomName, systemImage: "door.left.hand.open")
                        .font(MeetOverlayTheme.Typography.overlayMetadata)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)
                }

                if !attendees.isEmpty {
                    VStack(spacing: 6) {
                        Label(
                            "\(attendees.count) \(attendees.count == 1 ? "Attendee" : "Attendees")",
                            systemImage: "person.2"
                        )
                        .font(MeetOverlayTheme.Typography.overlayMetadata)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)

                        Text(attendees.joined(separator: ", "))
                            .font(MeetOverlayTheme.Typography.overlayHint)
                            .foregroundStyle(MeetOverlayTheme.Palette.overlayTertiaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .frame(maxWidth: 760)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onJoin) {
                        HStack(spacing: 10) {
                            Text(joinTitle)
                            KeycapHint(symbol: "⏎", tone: .onAccent)
                        }
                    }
                    .buttonStyle(OverlayPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    ForEach(Array(snoozeOptions.prefix(9).enumerated()), id: \.offset) { index, duration in
                        secondaryButton(
                            "Snooze \(SnoozeDurationFormatter.label(duration))",
                            keycap: "\(index + 1)",
                            key: KeyEquivalent(Character("\(index + 1)"))
                        ) {
                            onSnooze(duration)
                        }
                    }

                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Text("Dismiss")
                            KeycapHint(symbol: "esc")
                        }
                    }
                    .buttonStyle(OverlaySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)

                if meeting.meetLinks.count > 1 {
                    MeetLinkRescueView(links: meeting.meetLinks)
                }
            }
            .overlayPanel(maxWidth: 880)
        }
        .tint(MeetOverlayTheme.Palette.accent)
        // Force active control rendering: only one overlay window can be key, so
        // on additional displays — and for the brief moment before the app
        // activates — the bordered Join/Dismiss buttons would otherwise render in
        // their dimmed inactive state and read as missing against the dark panel.
        .environment(\.controlActiveState, .active)
        .onExitCommand(perform: onDismiss)
    }

    private var joinTitle: String {
        if meeting.meetLinks.count > 1 {
            return "Join First Room"
        }

        return "Join \(meeting.platform.displayName)"
    }

    private func secondaryButton(_ title: String, keycap: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                KeycapHint(symbol: keycap)
            }
        }
        .buttonStyle(OverlaySecondaryButtonStyle())
        .keyboardShortcut(key, modifiers: [])
    }
}

private struct BackToBackAirlockView: View {
    let transition: BackToBackTransition
    let onJoin: () -> Void
    let onDismiss: () -> Void

    private var nextMeeting: JoinableMeeting {
        transition.nextMeeting
    }

    var body: some View {
        ZStack {
            OverlayBackdropView()

            VStack(spacing: 18) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        Text(MeetingCountdownFormatter.text(now: context.date, startDate: nextMeeting.startDate))
                            .font(MeetOverlayTheme.Typography.overlayStatus)
                            .monospacedDigit()
                            .foregroundStyle(MeetOverlayTheme.Palette.accent)

                        Text(nextMeeting.title)
                            .font(MeetOverlayTheme.Typography.overlayTitle)
                            .foregroundStyle(MeetOverlayTheme.Palette.overlayText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)

                        Label(
                            meetingTimeRangeText(from: nextMeeting.startDate, to: nextMeeting.endDate),
                            systemImage: "clock"
                        )
                        .font(MeetOverlayTheme.Typography.overlayMetadata)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)
                    }
                }

                Text("Close notes. Join when ready.")
                    .font(MeetOverlayTheme.Typography.overlayHint)
                    .foregroundStyle(MeetOverlayTheme.Palette.overlayTertiaryText)

                HStack(spacing: 12) {
                    Button(action: onJoin) {
                        HStack(spacing: 10) {
                            Text("Join Next Room")
                            KeycapHint(symbol: "⏎", tone: .onAccent)
                        }
                    }
                    .buttonStyle(OverlayPrimaryButtonStyle(minWidth: 210))
                    .keyboardShortcut(.defaultAction)

                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Text("Dismiss")
                            KeycapHint(symbol: "esc")
                        }
                    }
                    .buttonStyle(OverlaySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)
            }
            .overlayPanel(maxWidth: 780)
        }
        .tint(MeetOverlayTheme.Palette.accent)
        .onExitCommand(perform: onDismiss)
    }
}

private struct MeetLinkRescueView: View {
    let links: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Multiple Meet links detected")
                .font(MeetOverlayTheme.Typography.overlayHint.weight(.semibold))
                .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)

            ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                HStack(spacing: 10) {
                    Text("Room \(index + 1): \(GoogleMeetLinkFormatter.roomCode(for: link))")
                        .font(MeetOverlayTheme.Typography.overlayHint)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)

                    Spacer()

                    Button("Open") {
                        open(link)
                    }
                    .buttonStyle(OverlaySecondaryButtonStyle(compact: true))

                    Button("Copy") {
                        copy(link)
                    }
                    .buttonStyle(OverlaySecondaryButtonStyle(compact: true))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(MeetOverlayTheme.Palette.overlayPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(MeetOverlayTheme.Palette.overlayPanelBorder, lineWidth: 1)
        )
    }

    private func open(_ link: URL) {
        NSWorkspace.shared.open(link)
    }

    private func copy(_ link: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }
}
