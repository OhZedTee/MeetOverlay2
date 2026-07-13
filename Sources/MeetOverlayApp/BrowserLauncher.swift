import AppKit
import UniformTypeIdentifiers

/// A browser (or app / PWA) installed on this Mac that can open meeting links.
struct InstalledBrowser: Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// Opens meeting links in a chosen browser, and enumerates the browsers available
/// to choose from. When no preference is set (or the chosen browser is gone), links
/// fall back to the system default browser.
@MainActor
final class BrowserLauncher {
    /// A generic web link used to ask Launch Services which apps are web browsers.
    private static let webProbeURL = URL(string: "https://example.com")!

    /// Representative meeting URLs, so apps and PWAs registered for a specific
    /// platform (e.g. a Google Meet PWA scoped to meet.google.com) also surface.
    private static let probeURLs: [URL] = [
        webProbeURL,
        URL(string: "https://meet.google.com/landing"),
        URL(string: "https://zoom.us/join"),
        URL(string: "https://teams.microsoft.com"),
        URL(string: "https://www.webex.com")
    ].compactMap { $0 }

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    /// Installed browsers and meeting apps/PWAs, deduplicated by bundle id and
    /// sorted by name.
    func availableBrowsers() -> [InstalledBrowser] {
        var seen = Set<String>()
        return Self.probeURLs
            .flatMap { workspace.urlsForApplications(toOpen: $0) }
            .compactMap(browser(at:))
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name of the current system default browser, e.g. "Firefox", if one is set.
    func defaultBrowserName() -> String? {
        workspace.urlForApplication(toOpen: Self.webProbeURL).map(name(for:))
    }

    /// Resolves a stored bundle id (e.g. a hand-picked app or PWA) to a display
    /// entry, so a saved choice that isn't auto-detected still shows by name.
    func browser(forBundleID bundleID: String) -> InstalledBrowser? {
        workspace.urlForApplication(withBundleIdentifier: bundleID).flatMap(browser(at:))
    }

    /// Presents an open panel so the user can pick any installed `.app` — including
    /// a PWA installed through Chrome. Returns nil if the panel is cancelled.
    func chooseApplication() -> InstalledBrowser? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose an app to open meeting links (including installed PWAs)."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return browser(at: url)
    }

    /// Opens `url` in the browser identified by `preferredBundleID`. Falls back to the
    /// system default when no preference is set or that browser is no longer installed.
    func open(_ url: URL, preferredBundleID: String?) {
        guard let preferredBundleID,
              let appURL = workspace.urlForApplication(withBundleIdentifier: preferredBundleID) else {
            workspace.open(url)
            return
        }

        workspace.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func browser(at appURL: URL) -> InstalledBrowser? {
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        return InstalledBrowser(bundleID: bundleID, name: name(for: appURL))
    }

    private func name(for appURL: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: appURL.path)
        return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    }
}
