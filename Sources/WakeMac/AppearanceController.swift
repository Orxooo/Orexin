// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import AVFoundation
import Combine
import SwiftUI
import UserNotifications

@MainActor final class AppearanceController: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable {
        case dark, light, amber, system
        var id: String { rawValue }
        var title: String { switch self { case .dark: L("创:电子世界争霸战"); case .light: L("齐马蓝"); case .amber: L("银翼杀手2049"); case .system: L("跟随系统") } }
        var artworkName: String { switch self { case .dark, .system: "OrbitalCore"; case .light: "OrbitalZima"; case .amber: "Orbital2049" } }
        var colorScheme: ColorScheme? { switch self { case .dark, .amber: .dark; case .light: .light; case .system: nil } }
        var appearance: NSAppearance? { switch self { case .dark, .amber: NSAppearance(named: .darkAqua); case .light: NSAppearance(named: .aqua); case .system: nil } }
    }
    @Published var theme: Theme { didSet { preferences.set(theme.rawValue, forKey: "orexin.appearance.theme"); onUpdate?() } }
    @Published var controlSounds: Bool { didSet { preferences.set(controlSounds, forKey: "orexin.appearance.controlSounds") } }
    enum ControlSound: String, CaseIterable, Identifiable {
        case relay, keyboard, `switch`
        static let defaultSound = Self.switch
        var id: String { rawValue }
        var title: String { switch self { case .relay: L("A · 金属脆响"); case .keyboard: L("B · 机械扣响"); case .switch: L("C · 电子点音") } }
        var detail: String { switch self { case .relay: L("高亮、短促的金属质感"); case .keyboard: L("较低音、干脆的机械按键"); case .switch: L("干净、短促的电子点音") } }
    }
    @Published var controlSound: ControlSound { didSet { preferences.set(controlSound.rawValue, forKey: "orexin.appearance.controlSound") } }
    @Published var controlVolume: Double { didSet {
        let normalized = Self.validVolume(controlVolume)
        if controlVolume != normalized { controlVolume = normalized; return }
        preferences.set(normalized, forKey: "orexin.appearance.controlVolume")
    } }
    static func validVolume(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.3 }
    enum Icon: String, CaseIterable, Identifiable {
        case moon, cup, bolt, custom
        var id: String { rawValue }
        var title: String { switch self { case .moon: L("折月"); case .cup: L("咖啡杯"); case .bolt: L("闪电"); case .custom: L("自定义") } }
    }
    @Published var icon: Icon { didSet { preferences.set(icon.rawValue, forKey: "orexin.appearance.icon"); onUpdate?() } }
    @Published var template: Bool { didSet { preferences.set(template, forKey: "orexin.appearance.template"); onUpdate?() } }
    @Published var showEndTime: Bool { didSet { preferences.set(showEndTime, forKey: "orexin.appearance.showEndTime"); onUpdate?() } }
    @Published var twentyFourHour: Bool { didSet { preferences.set(twentyFourHour, forKey: "orexin.appearance.24hour"); onUpdate?() } }
    @Published var iconPadding: Double { didSet { preferences.set(iconPadding, forKey: "orexin.appearance.padding"); onUpdate?() } }
    @Published private(set) var soundName: String
    @Published private(set) var message = ""
    var onUpdate: (() -> Void)?
    private let preferences: UserDefaults
    init(preferences: UserDefaults) {
        self.preferences = preferences
        theme = Theme(rawValue: preferences.string(forKey: "orexin.appearance.theme") ?? "dark") ?? .dark
        controlSounds = preferences.object(forKey: "orexin.appearance.controlSounds") as? Bool ?? true
        controlSound = ControlSound(rawValue: preferences.string(forKey: "orexin.appearance.controlSound") ?? "") ?? .defaultSound
        controlVolume = Self.validVolume(preferences.object(forKey: "orexin.appearance.controlVolume") as? Double ?? 0.3)
        icon = Icon(rawValue: preferences.string(forKey: "orexin.appearance.icon") ?? "moon") ?? .moon
        template = preferences.object(forKey: "orexin.appearance.template") as? Bool ?? true
        showEndTime = preferences.bool(forKey: "orexin.appearance.showEndTime")
        twentyFourHour = preferences.object(forKey: "orexin.appearance.24hour") as? Bool ?? true
        soundName = preferences.string(forKey: "orexin.appearance.sound") ?? ""
        iconPadding = preferences.object(forKey: "orexin.appearance.padding") as? Double ?? 0
    }
    private struct MenuImageKey: Equatable {
        let icon: Icon
        let template: Bool
        let padding: Double
        let customPath: String?
    }
    private var cachedMenuImage: (key: MenuImageKey, image: NSImage)?
    func menuImage() -> NSImage {
        let key = MenuImageKey(icon: icon, template: template, padding: iconPadding.isFinite ? min(max(iconPadding, 0), 12) : 0,
                               customPath: icon == .custom ? preferences.string(forKey: "orexin.appearance.customIcon") : nil)
        if let cachedMenuImage, cachedMenuImage.key == key { return cachedMenuImage.image }
        let source = baseMenuImage()
        let padding = key.padding
        guard padding > 0 else { cachedMenuImage = (key, source); return source }
        let image = NSImage(size: NSSize(width: 20 + padding * 2, height: 18), flipped: false) { _ in
            source.draw(in: NSRect(x: padding, y: 0, width: 20, height: 18)); return true
        }
        image.isTemplate = source.isTemplate
        cachedMenuImage = (key, image)
        return image
    }
    private func baseMenuImage() -> NSImage {
        if icon == .moon { return MenuMark.image() }
        if icon == .custom, let path = preferences.string(forKey: "orexin.appearance.customIcon"), let original = NSImage(contentsOfFile: path), original.size.width > 0, original.size.height > 0 {
            let bounds = NSSize(width: 20, height: 18)
            let scale = min(bounds.width / original.size.width, bounds.height / original.size.height)
            let size = NSSize(width: original.size.width * scale, height: original.size.height * scale)
            let image = NSImage(size: bounds, flipped: false) { rect in
                original.draw(in: NSRect(x: (rect.width-size.width)/2, y: (rect.height-size.height)/2, width: size.width, height: size.height))
                return true
            }
            image.isTemplate = template; return image
        }
        let image = NSImage(systemSymbolName: icon == .cup ? "cup.and.saucer.fill" : "bolt.fill", accessibilityDescription: "Orexin") ?? MenuMark.image()
        image.isTemplate = true; image.size = NSSize(width: 20, height: 18); return image
    }
    func chooseIcon() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns]
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let attrs = try file.resourceValues(forKeys: [.fileSizeKey]); guard (attrs.fileSize ?? .max) <= 5_000_000, NSImage(contentsOf: file) != nil else { throw ImportError.invalidImage }
            let folder = AppPaths.root.appendingPathComponent("Menu Icons", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(UUID().uuidString + "." + file.pathExtension)
            try FileManager.default.copyItem(at: file, to: target)
            preferences.set(target.path, forKey: "orexin.appearance.customIcon"); icon = .custom; message = "菜单栏图标已更新。"
        } catch { message = error.localizedDescription }
    }
    func chooseSound() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        Task { await importSound(file) }
    }
    func importSound(_ file: URL) async {
        do {
            guard ["aiff", "aif", "wav", "caf"].contains(file.pathExtension.lowercased()) else { throw ImportError.invalidSound }
            let duration = try await AVURLAsset(url: file).load(.duration).seconds
            guard duration.isFinite, duration > 0, duration < 30 else { throw ImportError.invalidSound }
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "Orexin-" + UUID().uuidString + "." + file.pathExtension
            try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(name))
            soundName = name; preferences.set(name, forKey: "orexin.appearance.sound"); message = "通知声音已更新。"
        } catch { message = error.localizedDescription }
    }
    func resetSound() { soundName = ""; preferences.removeObject(forKey: "orexin.appearance.sound"); message = "已恢复系统通知声音。" }
    func previewSound() {
        guard !soundName.isEmpty else { NSSound.beep(); return }
        NSSound(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/" + soundName).path, byReference: true)?.play()
    }
    private var lidSound: NSSound?
    func playLidTone(volume: Double) {
        guard volume.isFinite, lidSound?.isPlaying != true else { return }
        let sound = soundName.isEmpty ? NSSound(named: NSSound.Name("Glass")) : NSSound(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/" + soundName).path, byReference: true)
        sound?.volume = Float(min(max(volume, 0), 1)); lidSound = sound; sound?.play()
    }
    private enum ImportError: LocalizedError {
        case invalidImage, invalidSound
        var errorDescription: String? {
            switch self { case .invalidImage: "请选择小于 5 MB 的有效图片。"; case .invalidSound: "请选择短于 30 秒的 AIFF、WAV 或 CAF 音频。" }
        }
    }
}
