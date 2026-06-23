import AppKit
import MeetOverlayCore
import SwiftUI

@MainActor
final class OverlayPresenter {
    private var windows: [NSWindow] = []
    private var notificationSound: NSSound?

    func show(meeting: JoinableMeeting, onJoin: @escaping () -> Void, onDismiss: @escaping () -> Void, onSnooze: @escaping (TimeInterval) -> Void, snoozeOptions: [TimeInterval], attendees: [String], roomName: String?) {
        hide()
        playNotificationSound()

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
            // S snoozes by the shortest configured option; nil leaves the key inert.
            window.onSnoozeKey = snoozeOptions.first.map { duration in
                { onSnooze(duration) }
            }
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: MeetingOverlayView(
                    meeting: meeting,
                    onJoin: onJoin,
                    onDismiss: onDismiss,
                    onSnooze: onSnooze,
                    snoozeOptions: snoozeOptions,
                    attendees: attendees,
                    roomName: roomName
                )
            )

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

    func hide() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func playNotificationSound() {
        guard let url = Bundle.main.url(forResource: "notification", withExtension: "mp3") else {
            return
        }

        let sound = notificationSound ?? NSSound(contentsOf: url, byReference: false)
        notificationSound = sound
        sound?.stop()
        sound?.play()
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

private struct MeetingOverlayView: View {
    let meeting: JoinableMeeting
    let onJoin: () -> Void
    let onDismiss: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let snoozeOptions: [TimeInterval]
    let attendees: [String]
    let roomName: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [MeetOverlayTheme.Palette.overlayStart, MeetOverlayTheme.Palette.overlayEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: MeetOverlayTheme.Spacing.overlayContent) {
                Image(systemName: "video.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(MeetOverlayTheme.Palette.overlayText)
                    .frame(
                        width: MeetOverlayTheme.Size.overlayIconBadge,
                        height: MeetOverlayTheme.Size.overlayIconBadge
                    )
                    .background(
                        Circle()
                            .fill(MeetOverlayTheme.Palette.accent.opacity(0.22))
                    )
                    .overlay(
                        Circle()
                            .stroke(MeetOverlayTheme.Palette.accent.opacity(0.45), lineWidth: 1)
                    )

                VStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(meeting.startDate > context.date ? "Meeting starts soon" : "Meeting started")
                            .font(MeetOverlayTheme.Typography.overlayStatus)
                            .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)
                    }

                    Text(meeting.title)
                        .font(MeetOverlayTheme.Typography.overlayTitle)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlayText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.45)
                }

                HStack(spacing: 14) {
                    Label(timeRangeText, systemImage: "clock")

                    if let durationText = MeetingDurationFormatter.text(startDate: meeting.startDate, endDate: meeting.endDate) {
                        Label(durationText, systemImage: "hourglass")
                    }

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(MeetingCountdownFormatter.text(now: context.date, startDate: meeting.startDate))
                    }
                }
                .font(MeetOverlayTheme.Typography.overlayMetadata)
                .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(MeetOverlayTheme.Palette.overlayPanel)
                )
                .overlay(
                    Capsule()
                        .stroke(MeetOverlayTheme.Palette.overlayPanelBorder, lineWidth: 1)
                )

                if let roomName {
                    Label(roomName, systemImage: "door.left.hand.open")
                        .font(MeetOverlayTheme.Typography.overlayMetadata)
                        .foregroundStyle(MeetOverlayTheme.Palette.overlaySecondaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(MeetOverlayTheme.Palette.overlayPanel)
                        )
                        .overlay(
                            Capsule()
                                .stroke(MeetOverlayTheme.Palette.overlayPanelBorder, lineWidth: 1)
                        )
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

                HStack(spacing: 14) {
                    Button(action: onJoin) {
                        Text("Join \(meeting.platform.displayName)")
                            .font(MeetOverlayTheme.Typography.overlayButton.weight(.bold))
                            .padding(.horizontal, 34)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    if !snoozeOptions.isEmpty {
                        Menu {
                            ForEach(snoozeOptions, id: \.self) { duration in
                                Button("Snooze \(SnoozeDurationFormatter.label(duration))") {
                                    onSnooze(duration)
                                }
                            }
                        } label: {
                            Text("Snooze")
                                .font(MeetOverlayTheme.Typography.overlayButton)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 18)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(action: onDismiss) {
                        Text("Dismiss for This Meeting")
                            .font(MeetOverlayTheme.Typography.overlayButton)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 14)

                Text(hintText)
                    .font(MeetOverlayTheme.Typography.overlayHint)
                    .foregroundStyle(MeetOverlayTheme.Palette.overlayTertiaryText)
            }
            .padding(.horizontal, MeetOverlayTheme.Spacing.overlayPanelHorizontal)
            .padding(.vertical, MeetOverlayTheme.Spacing.overlayPanelVertical)
            .frame(maxWidth: 980)
            .background(
                RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.overlayPanel)
                    .fill(MeetOverlayTheme.Palette.overlayPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MeetOverlayTheme.Radius.overlayPanel)
                    .stroke(MeetOverlayTheme.Palette.overlayPanelBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 38, y: 22)
            .padding(48)
        }
        .tint(MeetOverlayTheme.Palette.accent)
        // Force active control rendering: only one overlay window can be key, so
        // on additional displays — and for the brief moment before the app
        // activates — the bordered Join/Dismiss buttons would otherwise render in
        // their dimmed inactive state and read as missing against the dark panel.
        .environment(\.controlActiveState, .active)
        .onExitCommand(perform: onDismiss)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: meeting.startDate)) to \(formatter.string(from: meeting.endDate))"
    }

    private var hintText: String {
        guard let firstOption = snoozeOptions.first else {
            return "Return joins. Esc dismisses."
        }

        return "Return joins. Esc dismisses. S snoozes \(SnoozeDurationFormatter.label(firstOption))."
    }
}
