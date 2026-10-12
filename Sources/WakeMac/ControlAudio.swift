// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

@MainActor final class ControlAudio {
    static let shared = ControlAudio()
    private var sounds: [String: NSSound] = [:]
    private let preferences: UserDefaults
    private let playback: ((String, Double) -> Void)?
    init(preferences: UserDefaults = .standard, playback: ((String, Double) -> Void)? = nil) {
        self.preferences = preferences; self.playback = playback
    }
    private func sound(_ key: String) -> NSSound? {
        if let cached = sounds[key] { return cached }
        guard let url = Bundle.main.url(forResource: key, withExtension: "wav", subdirectory: "Sounds"),
              let loaded = NSSound(contentsOf: url, byReference: true) else { return nil }
        sounds[key] = loaded
        return loaded
    }
    /// One completed control action produces one click, with no release cue.
    func click() {
        guard preferences.object(forKey: "orexin.appearance.controlSounds") as? Bool ?? true else { return }
        playClick(volume: AppearanceController.validVolume(preferences.object(forKey: "orexin.appearance.controlVolume") as? Double ?? 0.3))
    }
    private func playClick(volume: Double, preset requestedPreset: AppearanceController.ControlSound? = nil) {
        guard volume > 0 else { return }
        let preset = requestedPreset ?? AppearanceController.ControlSound(rawValue: preferences.string(forKey: "orexin.appearance.controlSound") ?? "") ?? .defaultSound
        let key = preset.rawValue + "-click"
        if let playback { playback(key, volume); return }
        guard let sound = sound(key) else { return }
        // An audition interrupts the previous tail, keeping comparisons to a single sound.
        for loaded in sounds.values where loaded.isPlaying { loaded.stop() }
        sound.volume = Float(volume)
        sound.play()
    }
    func preview(volume: Double, preset: AppearanceController.ControlSound? = nil) {
        playClick(volume: AppearanceController.validVolume(volume), preset: preset)
    }
}

struct ControlPressFeedback: ViewModifier {
    let pressed: Bool
    let enabled: Bool
    @State private var flash = false
    @State private var revision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .overlay { Rectangle().fill(TerminalStyle.accent.opacity(flash ? 0.12 : 0)).allowsHitTesting(false) }
            .shadow(color: TerminalStyle.accent.opacity(flash ? 0.35 : 0), radius: 8)
            .onChange(of: pressed) { old, new in
            guard enabled, old != new else { return }
            if old && !new && !reduceMotion {
                revision += 1
                let current = revision
                flash = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard current == revision else { return }
                    withAnimation(.easeOut(duration: 0.24)) { flash = false }
                }
            }
        }
    }
}
