import AppKit

/// A browser installed on this Mac that can open web links.
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
    /// A representative web link used to ask Launch Services which apps handle http(s).
    private static let webProbeURL = URL(string: "https://example.com")!

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    /// Installed browsers, deduplicated by bundle id and sorted by name.
    func availableBrowsers() -> [InstalledBrowser] {
        var seen = Set<String>()
        return workspace.urlsForApplications(toOpen: Self.webProbeURL)
            .compactMap(browser(at:))
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name of the current system default browser, e.g. "Firefox", if one is set.
    func defaultBrowserName() -> String? {
        workspace.urlForApplication(toOpen: Self.webProbeURL).map(name(for:))
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
