// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI

struct TronArtworkMotion: View {
    let artwork: ConsoleArtworkModule
    let imageFrame: CGRect
    let time: TimeInterval
    private let cyan = Color(red: 0.35, green: 0.94, blue: 1)
    private let gold = Color(red: 1, green: 0.65, blue: 0.16)

    var body: some View {
        Canvas { original, viewport in
            var context = original
            context.clip(to: Path(CGRect(origin: .zero, size: viewport)))
            context.translateBy(x: imageFrame.minX, y: imageFrame.minY)
            context.blendMode = .screen
            let size = imageFrame.size
            let t = time.truncatingRemainder(dividingBy: 3600)
            switch artwork {
            case .power: lightWall(context, size: size, time: t)
            case .sessions: transport(context, size: size, time: t)
            case .triggers: lightTrail(context, size: size, time: t)
            case .automation: portal(context, size: size, time: t)
            case .command: circuits(context, size: size, time: t)
            case .settings: hangar(context, size: size, time: t)
            case .thermal: coreRings(context, size: size, time: t)
            case .advanced: solarSail(context, size: size, time: t)
            case .notices: engines(context, size: size, time: t)
            case .history: fragments(context, size: size, time: t)
            case .about: shipReflection(context, size: size, time: t)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }

    private func point(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
    private func fraction(_ value: Double) -> Double { value - floor(value) }
    private func glow(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: bounds), with: .radialGradient(Gradient(colors: [color.opacity(opacity), .clear]),
            center: center, startRadius: 0, endRadius: radius))
    }
    private func lightWall(_ original: GraphicsContext, size: CGSize, time: Double) {
        var context = original
        context.clip(to: Path(CGRect(x: size.width * 0.215, y: 0, width: size.width * 0.19, height: size.height * 0.87)))
        for index in 0..<9 {
            let y = fraction(Double(index) / 9 - time * 0.16) * size.height
            let band = CGRect(x: size.width * 0.215, y: y, width: size.width * 0.19, height: size.height * 0.012)
            context.fill(Path(band), with: .color(cyan.opacity(0.15)))
        }
        glow(context, center: point(0.31, 0.5, size), radius: size.width * 0.20, color: cyan, opacity: 0.04 + 0.03 * sin(time * 1.4))
    }
    private func transport(_ context: GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<5 {
            let phase = fraction(Double(index) / 5 - time * 0.09)
            let ring = CGRect(x: size.width * (0.5 - 0.07 - phase * 0.04), y: size.height * (0.18 + phase * 0.38),
                              width: size.width * (0.14 + phase * 0.08), height: size.height * 0.035)
            context.stroke(Path(ellipseIn: ring), with: .color(cyan.opacity(0.18)), lineWidth: 0.9)
        }
        for index in 0..<16 {
            let seed = Double(index)
            let center = point(0.47 + fraction(seed * 0.237) * 0.06, 0.2 + fraction(seed * 0.173 - time * 0.11) * 0.36, size)
            glow(context, center: center, radius: 2, color: .white, opacity: 0.35)
        }
    }
    private func lightTrail(_ context: GraphicsContext, size: CGSize, time: Double) {
        var trail = Path(); trail.move(to: point(1.02, 0.418, size))
        trail.addQuadCurve(to: point(0.11, 0.47, size), control: point(0.55, 0.44, size))
        trail.addQuadCurve(to: point(0.64, 0.73, size), control: point(0.04, 0.49, size))
        let phase = fraction(time * 0.13)
        let highlight = trail.trimmedPath(from: phase, to: min(phase + 0.12, 1))
        context.stroke(highlight, with: .color(gold.opacity(0.12)), lineWidth: size.width * 0.022)
        context.stroke(highlight, with: .color(.white.opacity(0.35)), lineWidth: size.width * 0.003)
    }
    private func portal(_ context: GraphicsContext, size: CGSize, time: Double) {
        let beam = CGRect(x: size.width * 0.35, y: size.height * 0.49, width: size.width * 0.30, height: size.height * 0.015)
        let x = size.width * (0.5 + sin(time * 0.9) * 0.16)
        context.fill(Path(beam), with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.45), .clear]),
            startPoint: CGPoint(x: x - size.width * 0.07, y: beam.midY), endPoint: CGPoint(x: x + size.width * 0.07, y: beam.midY)))
        for index in 0..<18 {
            let seed = Double(index)
            let phase = fraction(seed * 0.139 - time * 0.06)
            glow(context, center: point(0.36 + fraction(seed * 0.317) * 0.28, 0.51 + phase * 0.25, size),
                 radius: 1.3, color: gold, opacity: (1 - phase) * 0.35)
        }
    }
    private func circuits(_ context: GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<3 {
            let y = 0.68 + Double(index) * 0.035
            var path = Path(); path.move(to: point(0.20, y, size)); path.addLine(to: point(0.30, y, size))
            path.addLine(to: point(0.34, y + 0.018, size)); path.addLine(to: point(0.54, y + 0.018, size))
            let phase = fraction(time * 0.18 + Double(index) * 0.27)
            context.stroke(path.trimmedPath(from: phase, to: min(phase + 0.17, 1)), with: .color(gold.opacity(0.6)), lineWidth: 1.0)
        }
        glow(context, center: point(0.58, 0.72, size), radius: size.width * 0.09, color: gold, opacity: 0.035 + 0.025 * sin(time * 1.6))
    }
    private func hangar(_ context: GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<5 {
            let depth = Double(index)
            let alpha = 0.025 + 0.07 * pow(0.5 + 0.5 * sin(time * 1.1 - depth * 0.9), 3)
            glow(context, center: point(0.17 + depth * 0.105, 0.38 + depth * 0.062, size),
                 radius: size.width * (0.14 - depth * 0.017), color: gold, opacity: alpha)
        }
    }
    private func coreRings(_ context: GraphicsContext, size: CGSize, time: Double) {
        for (index, y) in [0.16, 0.31, 0.48, 0.66, 0.81].enumerated() {
            let angle = time * (0.55 + Double(index) * 0.07) + Double(index) * 1.4
            let center = point(0.5 + cos(angle) * (0.18 + Double(index) * 0.018), y + sin(angle) * 0.035, size)
            glow(context, center: center, radius: size.width * 0.017, color: cyan, opacity: 0.7)
        }
        glow(context, center: point(0.50, 0.49, size), radius: size.width * 0.19, color: .red, opacity: 0.03 + 0.02 * sin(time * 0.8))
    }
    private func solarSail(_ context: GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<8 {
            let phase = fraction(Double(index) / 8 + time * 0.08)
            var ray = Path(); ray.move(to: point(phase - 0.025, 1.0 - phase + 0.025, size))
            ray.addLine(to: point(phase, 1.0 - phase, size))
            context.stroke(ray, with: .color(gold.opacity(0.35)), lineWidth: 1)
        }
        glow(context, center: point(0.51, 0.39, size), radius: size.width * 0.23, color: cyan, opacity: 0.035 + 0.025 * sin(time * 0.6))
    }
    private func engines(_ context: GraphicsContext, size: CGSize, time: Double) {
        for x in [0.35, 0.65] {
            glow(context, center: point(x, 0.57, size), radius: size.width * 0.10, color: gold, opacity: 0.06 + 0.04 * sin(time * 2.2))
            for index in 0..<7 {
                let phase = fraction(Double(index) / 7 + time * 0.17)
                var exhaust = Path(); exhaust.move(to: point(x, 0.58 + phase * 0.12, size))
                exhaust.addLine(to: point(x, 0.59 + phase * 0.12, size))
                context.stroke(exhaust, with: .color(gold.opacity((1 - phase) * 0.25)), lineWidth: 0.6)
            }
        }
    }
    private func fragments(_ context: GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<24 {
            let seed = Double(index)
            let phase = fraction(seed * 0.137 + time * 0.055)
            let center = point(0.66 - phase * 0.45 + sin(seed * 2.3) * 0.05, 0.5 - phase * 0.36 + cos(seed * 1.7) * 0.06, size)
            let radius = size.width * (0.002 + fraction(seed * 0.31) * 0.004)
            var shard = Path()
            for vertex in 0..<3 {
                let angle = Double(vertex) * .pi * 2 / 3 + time * 0.3 + seed
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if vertex == 0 { shard.move(to: p) } else { shard.addLine(to: p) }
            }
            shard.closeSubpath()
            context.stroke(shard, with: .color(cyan.opacity(0.3 * (1 - phase))), lineWidth: 0.7)
        }
    }
    private func shipReflection(_ context: GraphicsContext, size: CGSize, time: Double) {
        for row in 0..<8 {
            var wave = Path()
            for step in 0...32 {
                let x = Double(step) / 32
                let y = 0.65 + Double(row) * 0.035 + sin(x * 14 + time * 0.7 + Double(row)) * 0.008
                if step == 0 { wave.move(to: point(x, y, size)) } else { wave.addLine(to: point(x, y, size)) }
            }
            context.stroke(wave, with: .color(gold.opacity(0.045 + 0.025 * sin(time + Double(row)))), lineWidth: 0.7)
        }
        glow(context, center: point(0.35, 0.36, size), radius: size.width * 0.14, color: gold, opacity: 0.03 + 0.025 * sin(time * 1.2))
    }
}
