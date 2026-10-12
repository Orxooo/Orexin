// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

@MainActor final class AppearanceThemeTests: XCTestCase {
    func testThemeAndControlAudioPersistWithoutChangingExistingMenuPreferences() {
        let name = "WakeMacAppearanceTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("cup", forKey: "orexin.appearance.icon")
        let appearance = AppearanceController(preferences: defaults)
        XCTAssertEqual(appearance.theme, .dark)
        XCTAssertTrue(appearance.controlSounds)
        XCTAssertEqual(appearance.controlSound, .switch)
        appearance.theme = .light
        appearance.controlSounds = true
        appearance.controlVolume = 0.4
        appearance.controlSound = .keyboard
        let restored = AppearanceController(preferences: defaults)
        XCTAssertEqual(restored.theme, .light)
        XCTAssertTrue(restored.controlSounds)
        XCTAssertEqual(restored.controlVolume, 0.4, accuracy: 0.001)
        XCTAssertEqual(restored.controlSound, .keyboard)
        XCTAssertEqual(restored.icon, .cup)
        restored.controlSounds = false
        XCTAssertFalse(AppearanceController(preferences: defaults).controlSounds)
    }

    func testInvalidStoredThemeAndAudioVolumeHaveUsableDefaults() {
        let name = "WakeMacAppearanceTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("unrecognized", forKey: "orexin.appearance.theme")
        defaults.set(4.0, forKey: "orexin.appearance.controlVolume")
        let appearance = AppearanceController(preferences: defaults)
        XCTAssertEqual(appearance.theme, .dark)
        XCTAssertEqual(appearance.controlVolume, 1)
        appearance.controlVolume = -1
        XCTAssertEqual(appearance.controlVolume, 0)
        appearance.controlVolume = .nan
        XCTAssertEqual(appearance.controlVolume, 0.3)
    }
}
