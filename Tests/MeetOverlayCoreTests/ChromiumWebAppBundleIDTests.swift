import XCTest
@testable import MeetOverlayCore

final class ChromiumWebAppBundleIDTests: XCTestCase {
    func testMapsChromePWAToParentBrowser() {
        XCTAssertEqual(
            ChromiumWebAppBundleID.parentBrowserBundleID(for: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"),
            "com.google.Chrome"
        )
    }

    func testMapsEdgeAndBravePWAs() {
        XCTAssertEqual(
            ChromiumWebAppBundleID.parentBrowserBundleID(for: "com.microsoft.edgemac.app.abcdef"),
            "com.microsoft.edgemac"
        )
        XCTAssertEqual(
            ChromiumWebAppBundleID.parentBrowserBundleID(for: "com.brave.Browser.app.xyz"),
            "com.brave.Browser"
        )
    }

    func testReturnsNilForNormalBrowsers() {
        XCTAssertNil(ChromiumWebAppBundleID.parentBrowserBundleID(for: "com.google.Chrome"))
        XCTAssertNil(ChromiumWebAppBundleID.parentBrowserBundleID(for: "org.mozilla.firefox"))
        XCTAssertNil(ChromiumWebAppBundleID.parentBrowserBundleID(for: "com.apple.Safari"))
    }
}
