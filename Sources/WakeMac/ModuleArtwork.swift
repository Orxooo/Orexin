// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import Combine
import ImageIO
import SwiftUI

enum ConsoleArtworkModule: String, CaseIterable {
    case power, sessions, triggers, automation, command, settings, thermal, advanced, notices, history, about

    var atmosphere: ArtworkAtmosphere.Kind {
        switch self {
        case .power: .scan
        case .sessions: .sparks
        case .advanced: .hologram
        case .triggers: .flight
        case .notices: .rain
        case .about: .searchlight
        case .automation: .snow
        case .settings: .water
        case .command: .dust
        case .thermal: .heat
        case .history: .mist
        }
    }
}

@MainActor final class ArtworkRotation: ObservableObject {
    static let shared = ArtworkRotation()
    static let interval: TimeInterval = 30
    let ticks = Timer.publish(every: interval, on: .main, in: .common).autoconnect().share()
    @Published private(set) var orders: [String: [ConsoleArtworkModule]]
    private var lastChange: [String: Date]

    init(now: Date = Date()) {
        let themes = ["dark", "light", "amber"]
        orders = Dictionary(uniqueKeysWithValues: themes.map { ($0, ConsoleArtworkModule.allCases.shuffled()) })
        lastChange = Dictionary(uniqueKeysWithValues: themes.map { ($0, now) })
    }
    func artwork(for slot: ConsoleArtworkModule, theme: AppearanceController.Theme) -> ConsoleArtworkModule {
        let index = ConsoleArtworkModule.allCases.firstIndex(of: slot) ?? 0
        return orders[theme.rawValue]?[index] ?? slot
    }
    func advance(theme: AppearanceController.Theme, now: Date = Date()) {
        guard let current = orders[theme.rawValue], current.count > 1 else { return }
        let offset = Int.random(in: 1..<current.count)
        orders[theme.rawValue] = Array(current[offset...] + current[..<offset])
        lastChange[theme.rawValue] = now
    }
    @discardableResult func advanceIfDue(theme: AppearanceController.Theme, now: Date) -> Bool {
        guard let last = lastChange[theme.rawValue], now.timeIntervalSince(last) >= Self.interval else { return false }
        advance(theme: theme, now: now)
        return true
    }
}

enum ArtworkFraming {
    static let edgeInset: CGFloat = 0.025
    static func imageFrame(imageSize: CGSize, viewport: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let usable = 1 - edgeInset * 2
        let scale = max(viewport.width / (imageSize.width * usable), viewport.height / (imageSize.height * usable))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2, width: size.width, height: size.height)
    }
}

private struct ConsoleArtworkModuleKey: EnvironmentKey {
    static let defaultValue = ConsoleArtworkModule.power
}
extension EnvironmentValues {
    var consoleArtworkModule: ConsoleArtworkModule {
        get { self[ConsoleArtworkModuleKey.self] }
        set { self[ConsoleArtworkModuleKey.self] = newValue }
    }
}

extension ConsoleAssets {
    private static let moduleImages: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>(); cache.totalCostLimit = 9 * 1024 * 1024
        return cache
    }()
    static func artwork(for module: ConsoleArtworkModule, theme: AppearanceController.Theme = .amber, directory: URL? = nil) -> NSImage? {
        let folder = directory ?? theme.moduleArtworkFolder.flatMap { Bundle.main.resourceURL?.appendingPathComponent($0) }
        guard let url = folder?.appendingPathComponent(module.rawValue + ".png") else { return nil }
        if let cached = moduleImages.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 840,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
        moduleImages.setObject(image, forKey: url as NSURL, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }
}

struct ModuleArtwork: View {
    let slot: ConsoleArtworkModule
    let theme: AppearanceController.Theme
    @ObservedObject private var rotation = ArtworkRotation.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var hovered = false

    var body: some View {
        Group {
            let artwork = rotation.artwork(for: slot, theme: theme)
            if let image = ConsoleAssets.artwork(for: artwork, theme: theme) {
                if visible && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                        ArtworkScene(artwork: artwork, theme: theme, image: image, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    ArtworkScene(artwork: artwork, theme: theme, image: image, time: nil)
                }
            } else {
                Color.clear
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .background(ArtworkVisibilityProbe { visible = $0 })
            .brightness(hovered && !reduceMotion ? 0.02 : 0)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: hovered)
            .onReceive(rotation.ticks) { date in
                if visible { rotation.advanceIfDue(theme: theme, now: date) }
            }
            .accessibilityHidden(true)
    }
}

struct ArtworkScene: View {
    let artwork: ConsoleArtworkModule
    let theme: AppearanceController.Theme
    let image: NSImage
    var time: TimeInterval?

    var body: some View {
        GeometryReader { geometry in
            let frame = ArtworkFraming.imageFrame(imageSize: image.size, viewport: geometry.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                if let time {
                    if theme == .light {
                        ZimaArtworkMotion(module: artwork, image: image, time: time)
                    } else if theme == .dark {
                        TronArtworkMotion(artwork: artwork, imageFrame: frame, time: time)
                    } else {
                        ArtworkAtmosphere(kind: artwork.atmosphere, time: time, imageFrame: frame)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

struct ArtworkAtmosphere: View {
    enum Kind: CaseIterable { case rain, snow, dust, water, hologram, mist, scan, sparks, flight, heat, searchlight }
    let kind: Kind
    let time: TimeInterval
    var imageFrame: CGRect? = nil

    var body: some View {
        Canvas { original, viewport in
            let frame = imageFrame ?? CGRect(origin: .zero, size: viewport)
            let size = frame.size
            var context = original
            context.clip(to: Path(CGRect(origin: .zero, size: viewport)))
            context.translateBy(x: frame.minX, y: frame.minY)
            let t = time.truncatingRemainder(dividingBy: 3600)
            let cool = Color(red: 0.55, green: 0.9, blue: 1)
            let warm = Color(red: 1, green: 0.76, blue: 0.35)
            if kind == .water {
                for row in 0..<7 {
                    var wave = Path()
                    for step in 0...32 {
                        let x = size.width * Double(step) / 32
                        let y = size.height * (0.57 + Double(row) * 0.065) + sin(x / size.width * 11 + t * 0.6 + Double(row)) * size.height * 0.014
                        if step == 0 { wave.move(to: CGPoint(x: x, y: y)) }
                        else { wave.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(wave, with: .color(warm.opacity(0.10 + 0.035 * sin(t + Double(row)))), lineWidth: 1)
                }
            } else if kind == .scan || kind == .hologram {
                let y = size.height * (0.30 + fraction(t * (kind == .scan ? 0.055 : 0.075)) * 0.40)
                let band = CGRect(x: 0, y: y, width: size.width, height: 45)
                context.fill(Path(band), with: .linearGradient(Gradient(colors: [.clear, cool.opacity(0.11), .clear]),
                    startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + 45)))
                if kind == .hologram {
                    let glow = CGRect(x: size.width * 0.24, y: size.height * 0.28, width: size.width * 0.52, height: size.height * 0.52)
                    context.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [warm.opacity(0.035 + 0.025 * sin(t * 0.7)), .clear]),
                        center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 0, endRadius: size.width * 0.32))
                }
            } else if kind == .mist {
                let x = (0.5 + sin(t * 0.12) * 0.35) * size.width
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [.white.opacity(0.06), .clear]),
                    center: CGPoint(x: x, y: size.height * 0.55), startRadius: 0, endRadius: size.width * 0.65))
            } else if kind == .sparks {
                let center = CGPoint(x: size.width * 0.48, y: size.height * 0.48)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [warm.opacity(0.035 + 0.025 * sin(t * 1.1)), .clear]),
                    center: center, startRadius: 0, endRadius: size.width * 0.26))
            } else if kind == .flight {
                for index in 0..<18 {
                    let seed = Double(index)
                    let x = fraction(seed * 0.237 - t * 0.10) * size.width
                    let y = fraction(seed * 0.319 + t * 0.16) * size.height
                    var streak = Path(); streak.move(to: CGPoint(x: x, y: y))
                    streak.addLine(to: CGPoint(x: x - size.width * 0.018, y: y + size.height * 0.035))
                    context.stroke(streak, with: .color(cool.opacity(0.09)), lineWidth: 0.6)
                }
                let engine = CGPoint(x: size.width * 0.69, y: size.height * 0.47)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [.orange.opacity(0.06 + 0.035 * sin(t * 2)), .clear]),
                    center: engine, startRadius: 0, endRadius: size.width * 0.13))
            } else if kind == .heat {
                for column in 0..<6 {
                    let x = size.width * (0.15 + Double(column) * 0.14 + sin(t * 0.26 + Double(column)) * 0.025)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                        Gradient(colors: [.clear, warm.opacity(0.022 + 0.012 * sin(t * 0.8 + Double(column))), .clear]),
                        startPoint: CGPoint(x: x - size.width * 0.06, y: size.height),
                        endPoint: CGPoint(x: x + size.width * 0.08, y: 0)))
                }
            } else if kind == .searchlight {
                for index in 0..<2 {
                    let source = CGPoint(x: size.width * (index == 0 ? 0.49 : 0.61), y: size.height * 0.25)
                    let target = CGPoint(x: size.width * (0.5 + sin(t * 0.16 + Double(index) * .pi) * 0.5), y: size.height * 0.03)
                    var beam = Path(); beam.move(to: source)
                    beam.addLine(to: CGPoint(x: target.x - size.width * 0.12, y: target.y))
                    beam.addLine(to: CGPoint(x: target.x + size.width * 0.12, y: target.y)); beam.closeSubpath()
                    context.fill(beam, with: .linearGradient(Gradient(colors: [cool.opacity(0.09), .clear]), startPoint: source, endPoint: target))
                }
            }
            if kind == .rain || kind == .snow || kind == .dust || kind == .hologram || kind == .sparks {
                for index in 0..<28 {
                    let seed = Double(index)
                    let startX = fraction(sin(seed * 21.43 + 1.2) * 437.5)
                    let startY = fraction(sin(seed * 43.17 + 3.7) * 317.1)
                    let speed = 0.035 + fraction(seed * 0.37) * 0.035
                    let down = kind == .rain ? t * speed * 3 : kind == .dust || kind == .hologram || kind == .sparks ? -t * speed : t * speed
                    let y = (kind == .sparks ? 0.30 + fraction(startY + down * 1.5) * 0.35 : fraction(startY + down)) * size.height
                    let x = (kind == .sparks ? 0.32 + startX * 0.23 + sin(t + seed) * 0.012 : fraction(startX + sin(t * 0.25 + seed) * 0.035)) * size.width
                    let alpha = 0.10 + 0.13 * (0.5 + 0.5 * sin(seed + t * 0.6))
                    if kind == .rain {
                        var streak = Path(); streak.move(to: CGPoint(x: x, y: y))
                        streak.addLine(to: CGPoint(x: x - 1, y: y + 8 + seed.truncatingRemainder(dividingBy: 7)))
                        context.stroke(streak, with: .color(cool.opacity(alpha)), lineWidth: 0.5)
                    } else {
                        let radius = kind == .snow ? 0.8 : kind == .sparks ? 1.0 : 0.6
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                            with: .color((kind == .snow ? Color.white : warm).opacity(alpha)))
                    }
                }
            }
        }.blendMode(.screen).clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
    private func fraction(_ value: Double) -> Double { value - floor(value) }
}

private struct ArtworkVisibilityProbe: NSViewRepresentable {
    let changed: (Bool) -> Void
    final class Probe: NSView {
        var changed: (Bool) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        private var previous = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observe() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); observe() }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); report() }
        private func observe() {
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.report() })
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in self?.report() })
            }
            var ancestor = superview
            while let view = ancestor {
                if let clip = view as? NSClipView {
                    clip.postsBoundsChangedNotifications = true
                    observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.report() })
                }
                ancestor = view.superview
            }
            report()
        }
        private func report() {
            let active = NSApp.isActive && window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } == true && !visibleRect.isEmpty
            guard active != previous else { return }; previous = active
            DispatchQueue.main.async { [weak self] in self?.changed(active) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
    func makeNSView(context: Context) -> Probe { let probe = Probe(); probe.changed = changed; return probe }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed }
}
