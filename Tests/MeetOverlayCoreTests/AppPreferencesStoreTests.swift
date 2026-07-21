import XCTest
@testable import MeetOverlayCore

final class AppPreferencesStoreTests: XCTestCase {
    func testLoadsDefaultsWhenNothingWasSaved() throws {
        let defaults = makeDefaults()
        let store = AppPreferencesStore(defaults: defaults)

        let preferences = store.load()

        XCTAssertNil(preferences.selectedCalendarIDs)
        XCTAssertTrue(preferences.isOverlayEnabled)
        XCTAssertFalse(preferences.isSystemNotificationEnabled)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertTrue(preferences.hidesFinishedEvents)
        XCTAssertEqual(preferences.reminderSoundID, ReminderSoundCatalog.defaultSound.id)
        XCTAssertEqual(preferences.alertLeadTime, 900)
        XCTAssertEqual(preferences.alertLeadTimeUnit, .minutes)
        XCTAssertTrue(preferences.isSnoozeEnabled)
        XCTAssertEqual(preferences.snoozeOptions, [60, 120, 300, 600, 900])
        XCTAssertFalse(preferences.isMeetingRoomCalloutEnabled)
        XCTAssertTrue(preferences.isMeetingRoomInAttendees)
        XCTAssertEqual(preferences.meetingRoomPattern, "")
        XCTAssertNil(preferences.preferredBrowserBundleID)
    }

    func testPersistsPreferences() throws {
        let defaults = makeDefaults()
        let store = AppPreferencesStore(defaults: defaults)
        let savedPreferences = AppPreferences(
            selectedCalendarIDs: ["work", "personal"],
            isOverlayEnabled: false,
            isSystemNotificationEnabled: true,
            launchAtLogin: true,
            hidesFinishedEvents: false,
            reminderSoundID: "soft-chime",
            alertLeadTime: 300,
            alertLeadTimeUnit: .seconds,
            isSnoozeEnabled: false,
            snoozeOptions: [30, 60],
            isMeetingRoomCalloutEnabled: true,
            isMeetingRoomInAttendees: false,
            meetingRoomPattern: "MTL-*",
            preferredBrowserBundleID: "com.google.Chrome"
        )

        store.save(savedPreferences)

        XCTAssertEqual(store.load(), savedPreferences)
    }

    func testLoadsOldSavedPreferencesWithHideFinishedEventsEnabled() throws {
        let defaults = makeDefaults()
        let oldSavedPreferences = """
        {
          "selectedCalendarIDs": ["work"],
          "isOverlayEnabled": false,
          "launchAtLogin": true
        }
        """.data(using: .utf8)!
        defaults.set(oldSavedPreferences, forKey: "appPreferences")

        let preferences = AppPreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.selectedCalendarIDs, ["work"])
        XCTAssertFalse(preferences.isOverlayEnabled)
        XCTAssertFalse(preferences.isSystemNotificationEnabled, "Old saved data missing isSystemNotificationEnabled should default to false")
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertTrue(preferences.hidesFinishedEvents)
        XCTAssertEqual(preferences.reminderSoundID, ReminderSoundCatalog.defaultSound.id)
        XCTAssertEqual(preferences.alertLeadTime, 900, "Old saved data missing alertLeadTime should default to 15 minutes")
        XCTAssertEqual(preferences.alertLeadTimeUnit, .minutes, "Old saved data missing alertLeadTimeUnit should default to minutes")
        XCTAssertTrue(preferences.isSnoozeEnabled, "Old saved data missing isSnoozeEnabled should default to true")
        XCTAssertEqual(preferences.snoozeOptions, [60, 120, 300, 600, 900], "Old saved data missing snoozeOptions should use defaults")
        XCTAssertFalse(preferences.isMeetingRoomCalloutEnabled, "Old saved data missing room callout flag should default to off")
        XCTAssertTrue(preferences.isMeetingRoomInAttendees, "Old saved data missing room-in-attendees flag should default to true")
        XCTAssertEqual(preferences.meetingRoomPattern, "", "Old saved data missing room pattern should default to empty")
        XCTAssertNil(preferences.preferredBrowserBundleID, "Old saved data missing browser preference should default to the system default browser")
    }

    func testMeetingRoomConfigMirrorsPreferenceFields() throws {
        let preferences = AppPreferences(
            isMeetingRoomCalloutEnabled: true,
            isMeetingRoomInAttendees: false,
            meetingRoomPattern: "MTL-*"
        )

        let config = preferences.meetingRoomConfig

        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.isRoomInAttendees)
        XCTAssertEqual(config.pattern, "MTL-*")
    }

    func testPersistsMeetingRoomSettings() throws {
        let defaults = makeDefaults()
        let store = AppPreferencesStore(defaults: defaults)

        store.save(AppPreferences(
            isMeetingRoomCalloutEnabled: true,
            isMeetingRoomInAttendees: true,
            meetingRoomPattern: "Room-?-*"
        ))

        let loaded = store.load()
        XCTAssertTrue(loaded.isMeetingRoomCalloutEnabled)
        XCTAssertTrue(loaded.isMeetingRoomInAttendees)
        XCTAssertEqual(loaded.meetingRoomPattern, "Room-?-*")
    }

    func testPersistsAlertLeadTime() throws {
        let defaults = makeDefaults()
        let store = AppPreferencesStore(defaults: defaults)

        store.save(AppPreferences(alertLeadTime: 600))

        XCTAssertEqual(store.load().alertLeadTime, 600)
    }

    func testPersistsSnoozeSettings() throws {
        let defaults = makeDefaults()
        let store = AppPreferencesStore(defaults: defaults)

        store.save(AppPreferences(
            alertLeadTimeUnit: .seconds,
            isSnoozeEnabled: false,
            snoozeOptions: [30, 90, 180]
        ))

        let loaded = store.load()
        XCTAssertEqual(loaded.alertLeadTimeUnit, .seconds)
        XCTAssertFalse(loaded.isSnoozeEnabled)
        XCTAssertEqual(loaded.snoozeOptions, [30, 90, 180])
    }

    func testPersistsPreferredBrowser() throws {
        let defaults = makeDefaults()
        let store = AppPreferencesStore(defaults: defaults)

        store.save(AppPreferences(preferredBrowserBundleID: "org.mozilla.firefox"))
        XCTAssertEqual(store.load().preferredBrowserBundleID, "org.mozilla.firefox")

        store.save(AppPreferences(preferredBrowserBundleID: nil))
        XCTAssertNil(store.load().preferredBrowserBundleID, "Clearing the preference should fall back to the system default browser")
    }

    func testLoadsUnknownReminderSoundAsDefault() throws {
        let defaults = makeDefaults()
        let savedPreferences = """
        {
          "reminderSoundID": "missing"
        }
        """.data(using: .utf8)!
        defaults.set(savedPreferences, forKey: "appPreferences")

        let preferences = AppPreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.reminderSoundID, ReminderSoundCatalog.defaultSound.id)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MeetOverlayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
