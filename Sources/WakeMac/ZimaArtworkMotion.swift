// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

struct ZimaArtworkMotion: View {
    let module: ConsoleArtworkModule
    let image: NSImage
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let frame = ArtworkFraming.imageFrame(imageSize: image.size, viewport: size)
            let stage = frame.size
            var drawing = context
            drawing.clip(to: Path(CGRect(origin: .zero, size: size)))
            drawing.translateBy(x: frame.minX, y: frame.minY)
            let t = time.truncatingRemainder(dividingBy: 3600)
            if !waterOutlines.isEmpty {
                drawWater(drawing, image: context.resolve(Image(nsImage: image)), size: stage, time: t)
            }
            switch module {
            case .triggers: drawBubbles(drawing, size: stage, time: t)
            case .command:
                drawBubbles(drawing, size: stage, time: t)
                drawUnderwaterRays(drawing, size: stage, time: t)
            case .history:
                drawStars(drawing, size: stage, time: t)
                drawComet(drawing, size: stage, time: t)
            case .about:
                drawStars(drawing, size: stage, time: t)
                drawPanelEdge(drawing, size: stage, time: t)
            case .advanced: drawStars(drawing, size: stage, time: t)
            case .thermal: drawCorona(drawing, size: stage, time: t)
            case .notices: drawSpotlights(drawing, size: stage, time: t)
            case .settings: drawBlueReflection(drawing, size: stage, time: t)
            default: break
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }

    private var waterOutlines: [[CGFloat]] {
        switch module {
        case .power:
            [[0.20, 0.20, 0.80, 0.20, 0.80, 0.80, 0.20, 0.80]]
        case .sessions:
            [[0.04, 0.56, 0.92, 0.56, 0.97, 0.96, 0.03, 0.96]]
        case .advanced:
            [[0.02, 0.78, 0.34, 0.30, 0.60, 0.30, 0.98, 0.79, 0.91, 0.87, 0.13, 0.87]]
        case .automation:
            [[0.02, 0.42, 0.27, 0.42, 0.27, 0.97, 0.02, 0.97],
             [0.20, 0.54, 0.72, 0.48, 0.78, 0.56, 0.24, 0.64]]
        case .triggers, .command:
            [[0.025, 0.03, 0.975, 0.03, 0.975, 0.97, 0.025, 0.97]]
        case .notices:
            [[0.30, 0.58, 0.68, 0.51, 0.78, 0.67, 0.42, 0.84]]
        default: []
        }
    }
    private var waterExclusions: [[CGFloat]] {
        switch module {
        case .power:
            [[0.445, 0.421, 0.556, 0.421, 0.556, 0.579, 0.445, 0.579],
             [0.37, 0.585, 0.453, 0.585, 0.453, 0.652, 0.37, 0.652]]
        case .sessions:
            [[0.12, 0.66, 0.76, 0.65, 0.88, 0.91, 0.05, 0.92],
             [0.43, 0.40, 0.55, 0.40, 0.55, 0.65, 0.43, 0.65]]
        case .advanced:
            [[0.433, 0.344, 0.57, 0.344, 0.697, 0.574, 0.697, 0.72, 0.302, 0.72, 0.302, 0.574]]
        case .automation:
            [[0.44, 0.28, 0.66, 0.28, 0.66, 0.58, 0.44, 0.58]]
        case .triggers:
            [[0.28, 0.20, 0.79, 0.20, 0.79, 0.62, 0.28, 0.62],
             [0.17, 0.51, 0.66, 0.51, 0.70, 0.72, 0.38, 0.79]]
        case .command:
            [[0.15, 0.13, 0.84, 0.13, 0.84, 0.81, 0.15, 0.81],
             [0.24, 0.82, 0.76, 0.82, 0.76, 0.94, 0.24, 0.94]]
        case .notices:
            [[0.44, 0.59, 0.49, 0.59, 0.49, 0.67, 0.44, 0.67]]
        default: []
        }
    }
    private func polygon(_ coordinates: [CGFloat], size: CGSize) -> Path {
        Path { path in
            for index in stride(from: 0, to: coordinates.count, by: 2) {
                let point = CGPoint(x: coordinates[index] * size.width, y: coordinates[index + 1] * size.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
    private func drawWater(_ original: GraphicsContext, image: GraphicsContext.ResolvedImage, size: CGSize, time: Double) {
        var context = original
        var water = Path()
        for outline in waterOutlines { water.addPath(polygon(outline, size: size)) }
        context.clip(to: water)
        for exclusion in waterExclusions {
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addPath(polygon(exclusion, size: size))
            context.clip(to: outside, style: FillStyle(eoFill: true))
        }
        let bounds = water.boundingRect
        let motion = waterMotion
        let stripHeight = size.height / 48
        for index in 0..<48 {
            let y = CGFloat(index) * stripHeight
            guard y + stripHeight >= bounds.minY, y <= bounds.maxY else { continue }
            var strip = context
            strip.clip(to: Path(CGRect(x: 0, y: y, width: size.width, height: stripHeight + 0.25)))
            let phase = Double(index) * motion.frequency
            let dx = sin(time * motion.speed + phase) * size.width * motion.amplitude
            let dy = cos(time * motion.speed * 0.73 + phase * 0.7) * size.height * motion.amplitude * 0.5
            strip.draw(image, in: CGRect(x: dx, y: dy, width: size.width, height: size.height))
        }
        context.blendMode = .screen
        for row in 0..<12 {
            var caustic = Path()
            for step in 0...32 {
                let x = size.width * Double(step) / 32
                let y = size.height * Double(row) / 12 + sin(Double(step) * motion.frequency * 1.5 + time * motion.speed + Double(row)) * size.height * motion.amplitude * 5
                if step == 0 { caustic.move(to: CGPoint(x: x, y: y)) }
                else { caustic.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(caustic, with: .color(Color(red: 0.55, green: 0.96, blue: 1).opacity(0.10 + 0.035 * sin(time + Double(row)))), lineWidth: 0.7)
        }
        let center = CGPoint(x: size.width * (0.5 + sin(time * 0.17) * 0.22), y: bounds.midY)
        context.fill(water, with: .radialGradient(Gradient(colors: [.white.opacity(0.065), .clear]),
            center: center, startRadius: 0, endRadius: size.width * 0.4))
    }
    private var waterMotion: (speed: Double, amplitude: Double, frequency: Double) {
        switch module {
        case .power: (0.60, 0.0022, 0.32)
        case .sessions: (0.82, 0.0026, 0.42)
        case .triggers: (1.05, 0.0018, 0.52)
        case .automation: (0.38, 0.0038, 0.23)
        case .command: (0.44, 0.0020, 0.30)
        case .advanced: (0.52, 0.0028, 0.37)
        case .notices: (0.70, 0.0016, 0.46)
        default: (0.65, 0.0024, 0.36)
        }
    }
    private func drawBubbles(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        for index in 0..<(module == .triggers ? 12 : 24) {
            let seed = Double(index)
            let side = index.isMultiple(of: 2) ? 0.06 : 0.80
            let x = (side + fraction(sin(seed * 14.3 + 1) * 37) * 0.14 + sin(time * 0.5 + seed) * 0.008) * size.width
            let y = fraction(seed * 0.173 - time * (module == .triggers ? 0.055 + seed * 0.002 : 0.018 + seed * 0.0007)) * size.height
            let radius = 0.7 + fraction(seed * 0.39) * 1.0
            context.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.12 + 0.10 * sin(seed + time) * sin(seed + time))), lineWidth: 0.5)
        }
        let glow = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.45)
        context.fill(Path(glow), with: .linearGradient(Gradient(colors: [.white.opacity(0.04 + 0.02 * sin(time * 0.3)), .clear]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.35, y: glow.maxY)))
    }
    private func drawUnderwaterRays(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        for index in 0..<3 {
            let x = size.width * (0.2 + Double(index) * 0.28 + sin(time * 0.12 + Double(index)) * 0.025)
            var ray = Path(); ray.move(to: CGPoint(x: x, y: 0))
            ray.addLine(to: CGPoint(x: x - size.width * 0.12, y: size.height * 0.76))
            ray.addLine(to: CGPoint(x: x + size.width * 0.06, y: size.height * 0.76)); ray.closeSubpath()
            context.fill(ray, with: .linearGradient(Gradient(colors: [.white.opacity(0.035 + 0.015 * sin(time * 0.5)), .clear]),
                startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x, y: size.height * 0.76)))
        }
    }
    private func drawComet(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        let phase = fraction(time * 0.045)
        let point = CGPoint(x: phase * size.width * 1.3 - size.width * 0.15, y: size.height * (0.12 + phase * 0.18))
        var trail = Path(); trail.move(to: CGPoint(x: point.x - size.width * 0.07, y: point.y - size.height * 0.014)); trail.addLine(to: point)
        context.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.32)]),
            startPoint: CGPoint(x: point.x - size.width * 0.07, y: point.y), endPoint: point), lineWidth: 0.8)
    }
    private func drawPanelEdge(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        let panel = CGRect(x: size.width * 0.23, y: size.height * 0.23, width: size.width * 0.54, height: size.height * 0.54)
        let point = CGPoint(x: panel.midX + cos(time * 0.35) * panel.width * 0.5, y: panel.midY + sin(time * 0.35) * panel.height * 0.5)
        context.stroke(Path(panel), with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .clear]),
            center: point, startRadius: 0, endRadius: panel.width * 0.3), lineWidth: 1.4)
    }
    private func drawStars(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        for index in 0..<30 {
            let seed = Double(index)
            let x = fraction(sin(seed * 12.7 + 0.3) * 473.5)
            let y = fraction(sin(seed * 39.1 + 2.7) * 317.1)
            if module == .advanced && y > 0.20 { continue }
            if module == .about && x > 0.22 && x < 0.79 && y > 0.22 && y < 0.80 { continue }
            if module == .history && y > 0.39 && y < 0.57 { continue }
            let alpha = 0.12 + 0.24 * pow(0.5 + 0.5 * sin(time * 0.8 + seed * 2.3), 3)
            let point = CGPoint(x: x * size.width, y: y * size.height)
            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 1.2, height: 1.2)), with: .color(.white.opacity(alpha)))
        }
    }
    private func drawCorona(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.49)
        let radius = min(size.width, size.height) * 0.39
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [.clear, .orange.opacity(0.025 + 0.02 * sin(time * 0.6)), .clear]),
            center: center, startRadius: radius * 0.65, endRadius: radius * 1.2))
        for index in 0..<14 {
            let angle = Double(index) / 14 * .pi * 2
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            if y > size.height * 0.42 && y < size.height * 0.62 { continue }
            let length = size.width * (0.008 + 0.008 * (1 + sin(time * 0.7 + Double(index))))
            var flare = Path(); flare.move(to: CGPoint(x: x, y: y))
            flare.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                control: CGPoint(x: x + cos(angle + 0.4) * length, y: y + sin(angle + 0.4) * length))
            context.stroke(flare, with: .color(.orange.opacity(0.17)), lineWidth: 1)
        }
    }
    private func drawSpotlights(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        for index in 0..<3 {
            let source = CGPoint(x: size.width * [0.08, 0.36, 0.93][index], y: size.height * [0.18, 0.14, 0.13][index])
            let landing = size.width * (0.42 + Double(index) * 0.07 + sin(time * 0.17 + Double(index)) * 0.07)
            var beam = Path(); beam.move(to: source)
            beam.addLine(to: CGPoint(x: landing - size.width * 0.11, y: size.height * 0.72))
            beam.addLine(to: CGPoint(x: landing + size.width * 0.11, y: size.height * 0.72)); beam.closeSubpath()
            context.fill(beam, with: .linearGradient(Gradient(colors: [.white.opacity(0.045), .clear]), startPoint: source,
                endPoint: CGPoint(x: landing, y: size.height * 0.75)))
        }
    }
    private func drawBlueReflection(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original; context.blendMode = .screen
        let panel = CGRect(x: size.width * 0.407, y: size.height * 0.158, width: size.width * 0.19, height: size.height * 0.54)
        context.clip(to: Path(panel))
        let x = panel.midX + sin(time * 0.42) * panel.width * 0.65
        context.fill(Path(panel), with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.18), .clear]),
            startPoint: CGPoint(x: x - panel.width * 0.3, y: panel.midY), endPoint: CGPoint(x: x + panel.width * 0.3, y: panel.midY)))
    }
    private func fraction(_ value: Double) -> Double { value - floor(value) }
}
