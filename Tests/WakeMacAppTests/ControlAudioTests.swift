// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

@MainActor final class ControlAudioTests: XCTestCase {
    func testEachActivationPlaysExactlyOneClickWithoutThrottlingRapidActions() {
        let name = "WakeMacControlAudioTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.57, forKey: "orexin.appearance.controlVolume")
        var played: [(String, Double)] = []
        let audio = ControlAudio(preferences: defaults) { played.append(($0, $1)) }
        audio.click()
        XCTAssertEqual(played.count, 1)
        XCTAssertEqual(played.first?.0, "switch-click")
        XCTAssertEqual(played.first?.1, 0.57)
        audio.click()
        XCTAssertEqual(played.count, 2)
    }

    func testPreviewPlaysOneClickWithNoDelayedReleaseEvenWhenControlSoundsAreOff() async throws {
        let name = "WakeMacControlAudioTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "orexin.appearance.controlSounds")
        defaults.set("keyboard", forKey: "orexin.appearance.controlSound")
        var played: [(String, Double)] = []
        let audio = ControlAudio(preferences: defaults) { played.append(($0, $1)) }
        audio.click()
        XCTAssertTrue(played.isEmpty)
        audio.preview(volume: 0.6)
        XCTAssertEqual(played.count, 1)
        XCTAssertEqual(played.first?.0, "keyboard-click")
        XCTAssertEqual(played.first?.1, 0.6)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(played.count, 1)
    }

    func testMutedClickDoesNotPlayAndExistingPresetIsPreserved() {
        let name = "WakeMacControlAudioTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.0, forKey: "orexin.appearance.controlVolume")
        defaults.set("relay", forKey: "orexin.appearance.controlSound")
        var played: [String] = []
        let audio = ControlAudio(preferences: defaults) { key, _ in played.append(key) }
        audio.click()
        XCTAssertTrue(played.isEmpty)
        defaults.set(0.5, forKey: "orexin.appearance.controlVolume")
        audio.click()
        XCTAssertEqual(played, ["relay-click"])
    }

    func testDirectAuditionUsesRequestedTimbreWithoutChangingSavedChoice() {
        let name = "WakeMacControlAudioTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("keyboard", forKey: "orexin.appearance.controlSound")
        var played: [String] = []
        let audio = ControlAudio(preferences: defaults) { key, _ in played.append(key) }
        for preset in AppearanceController.ControlSound.allCases { audio.preview(volume: 0.6, preset: preset) }
        XCTAssertEqual(played, ["relay-click", "keyboard-click", "switch-click"])
        XCTAssertEqual(defaults.string(forKey: "orexin.appearance.controlSound"), "keyboard")
    }
}
