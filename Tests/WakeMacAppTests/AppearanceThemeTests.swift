// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

@MainActor final class AppearanceThemeTests: XCTestCase {
    func testMenuLayoutPersistsIndependentlyAndNotifiesWindowSizing() {
        let name = "WakeMacMenuLayoutTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let appearance = AppearanceController(preferences: defaults)
        XCTAssertEqual(appearance.menuLayout, .deck)
        var updates = 0
        appearance.onUpdate = { updates += 1 }
        appearance.menuLayout = .band
        XCTAssertEqual(updates, 1)
        let restored = AppearanceController(preferences: defaults)
        XCTAssertEqual(restored.menuLayout, .band)
        XCTAssertEqual(restored.theme, .dark)
        defaults.set("unrecognized", forKey: "orexin.appearance.menuLayout")
        XCTAssertEqual(AppearanceController(preferences: defaults).menuLayout, .deck)
    }

    func testMenuLayoutsFitScreenAndSwitchBetweenDistinctDimensions() {
        let available = CGSize(width: 1280, height: 800)
        let deck = AppearanceController.MenuLayout.deck.size(available: available)
        let band = AppearanceController.MenuLayout.band.size(available: available)
        XCTAssertLessThanOrEqual(deck.height, available.height - 64)
        XCTAssertLessThanOrEqual(band.width, available.width - 32)
        XCTAssertGreaterThan(band.width, deck.width)
        XCTAssertLessThan(band.height, deck.height)
    }
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
