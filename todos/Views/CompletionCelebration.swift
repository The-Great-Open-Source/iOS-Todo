import SwiftUI

/// The reward for a milestone, played entirely *behind* the interface. Nothing covers the list: the
/// colour washes, shockwaves, ribbons, rays, confetti and fireworks show between the tiles and
/// through the glass, and every tap and scroll keeps working while it plays. Each tier is bigger
/// than the last; 100% is a full finale. All motion comes from one clock, tuned to the haptics.
struct CelebrationBackdrop: View {
    let event: CelebrationEvent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todoTheme) private var theme
    @State private var startedAt = Date()
    @State private var show: Show?
    @State private var calmGlow = 0.0

    private var milestone: CompletionMilestone { event.milestone }

    /// Everything that is random, decided once per celebration so frames stay continuous.
    private struct Show {
        let particles: [Particle]
        let bursts: [Burst]
    }

    var body: some View {
        Group {
            if reduceMotion {
                // A single soft glow, no movement.
                RadialGradient(colors: [theme.accent.opacity(0.5), theme.accent2.opacity(0.2), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 520)
                    .opacity(calmGlow)
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(&context, size: size, elapsed: timeline.date.timeIntervalSince(startedAt))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            startedAt = Date()
            show = Show(particles: Particle.make(for: milestone), bursts: Burst.make(for: milestone))
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.5)) { calmGlow = 1 }
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeIn(duration: 0.9)) { calmGlow = 0 }
            }
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        guard let show else { return }
        let tier = milestone.tier
        let impact = milestone.impactTime
        let total = milestone.totalDuration
        guard elapsed >= 0, elapsed < total else { return }
        let since = elapsed - impact
        let fadeOut = 1 - smooth((elapsed - (total - 1.4)) / 1.4)
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let reach = hypot(size.width, size.height)

        // Colour wash: swells while the haptic roll builds, flares at impact, then settles.
        let build = smooth(elapsed / (impact + 0.2))
        let flare = exp(-max(0, since) * 1.5)
        let amount = (0.35 + 0.65 * flare) * build * fadeOut * [0.6, 0.75, 0.9, 1.0][tier - 1]
        let pulse = reach * (0.46 + 0.08 * sin(elapsed * 4.2))
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [theme.accent.opacity(0.95 * amount), theme.accent2.opacity(0.55 * amount), theme.accent3.opacity(0)]),
            center: origin, startRadius: 0, endRadius: pulse))
        if tier >= 3 {
            for corner in [CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [TodoPalette.gold.opacity(0.7 * amount), TodoPalette.gold.opacity(0)]),
                    center: corner, startRadius: 0, endRadius: reach * 0.5))
            }
        }

        guard since > -0.05 else { return }

        // Light rays (75% and up).
        if tier >= 3 {
            let alpha = smooth(since / 0.4) * fadeOut
            for index in 0..<16 {
                let angle = Double(index) / 16 * 2 * .pi + elapsed * 0.3
                var ray = Path()
                ray.move(to: origin)
                ray.addArc(center: origin, radius: reach, startAngle: .radians(angle - 0.05), endAngle: .radians(angle + 0.05), clockwise: false)
                ray.closeSubpath()
                var layer = context
                layer.opacity = 0.55 * alpha
                layer.fill(ray, with: .radialGradient(
                    Gradient(colors: [(tier == 4 ? TodoPalette.gold : theme.accent3), .clear]),
                    center: origin, startRadius: 30, endRadius: reach * 0.85))
            }
        }

        // Flowing ribbons of colour (50% and up).
        if tier >= 2 {
            let env = smooth(since / 0.5) * fadeOut
            for index in 0..<(tier - 1) {
                var path = Path()
                var x = -20.0
                let baseY = size.height * (0.2 + 0.24 * Double(index))
                while x <= size.width + 20 {
                    let y = baseY + sin(x * 0.011 + elapsed * 1.7 + Double(index) * 2.1) * 62 + sin(x * 0.027 - elapsed * 1.1) * 18
                    if x == -20 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += 12
                }
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [theme.accent, theme.accent2, TodoPalette.gold, theme.accent3]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                var layer = context
                layer.opacity = 0.34 * env
                layer.stroke(path, with: shading, style: StrokeStyle(lineWidth: 78, lineCap: .round))
                layer.opacity = 0.7 * env
                layer.stroke(path, with: shading, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            }
        }

        // Shockwaves, one per haptic pulse.
        for ring in 0..<[1, 2, 3, 5][tier - 1] {
            let u = (since - Double(ring) * 0.28) / 1.5
            guard u > 0, u < 1 else { continue }
            let radius = easeOut(u) * reach * 0.62
            let ringPath = Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
            var layer = context
            layer.opacity = pow(1 - u, 1.3) * 0.9
            layer.stroke(ringPath, with: .color([theme.accent3, .white, TodoPalette.gold][ring % 3]), lineWidth: 26 * (1 - u) + 2)
            layer.opacity = pow(1 - u, 1.3) * 0.35
            layer.stroke(ringPath, with: .color(theme.accent), lineWidth: 60 * (1 - u) + 6)
        }

        // Confetti cannons.
        let confettiFade = min(1, max(0, (total - elapsed) / 0.9))
        let colors = Particle.palette(for: theme)
        for particle in show.particles { particle.draw(in: &context, size: size, elapsed: elapsed, colors: colors, fade: confettiFade) }

        // Fireworks (75% and up).
        for burst in show.bursts { burst.draw(in: &context, size: size, elapsed: elapsed, colors: colors) }

        // Twinkling stars drifting upward.
        let sparkleCount = [0, 12, 24, 48][tier - 1]
        for index in 0..<sparkleCount {
            let start = impact + hash01(index, 1) * max(0.5, total - impact - 2.2)
            let life = 0.9 + hash01(index, 2) * 0.8
            let u = (elapsed - start) / life
            guard u > 0, u < 1 else { continue }
            let scale = sin(.pi * u) * (8 + hash01(index, 5) * 14)
            var layer = context
            layer.translateBy(x: hash01(index, 3) * size.width, y: hash01(index, 4) * size.height - u * 50)
            layer.rotate(by: .degrees(60 * u))
            layer.scaleBy(x: scale, y: scale)
            layer.opacity = fadeOut
            layer.fill(Particle.sparklePath, with: .color(index.isMultiple(of: 2) ? .white : TodoPalette.gold))
        }
    }

    private func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    private func easeOut(_ value: Double) -> Double { 1 - pow(1 - min(1, max(0, value)), 3) }
}

private func hash01(_ index: Int, _ salt: Double) -> Double {
    let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
    return value - floor(value)
}

// MARK: - Fireworks

/// A radial burst of sparks that arc and fall under gravity, with short bright trails.
private struct Burst {
    let time: Double
    let center: CGPoint
    let colorOffset: Int

    static func make(for milestone: CompletionMilestone) -> [Burst] {
        let count = [0, 0, 2, 5][milestone.tier - 1]
        return (0..<count).map { index in
            Burst(time: milestone.impactTime + 0.55 + Double(index) * 0.5,
                  center: CGPoint(x: 0.16 + hash01(index, 21) * 0.68, y: 0.14 + hash01(index, 22) * 0.4),
                  colorOffset: index * 2)
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double, colors: [Color]) {
        let t = elapsed - time
        guard t >= 0, t < 1.5 else { return }
        let origin = CGPoint(x: center.x * size.width, y: center.y * size.height)
        func position(_ index: Int, at t: Double) -> CGPoint {
            let angle = Double(index) / 40 * 2 * .pi + hash01(index, 23) * 0.2
            let speed = 300 + hash01(index, 24) * 260
            let travel = (1 - exp(-2.4 * t)) / 2.4
            return CGPoint(x: origin.x + cos(angle) * speed * travel, y: origin.y + sin(angle) * speed * travel + 170 * t * t)
        }
        let life = t / 1.5
        if t < 0.22 {
            var flash = context
            flash.opacity = (1 - t / 0.22) * 0.9
            flash.fill(Path(ellipseIn: CGRect(x: origin.x - 70, y: origin.y - 70, width: 140, height: 140)),
                       with: .radialGradient(Gradient(colors: [.white, colors[0].opacity(0)]), center: origin, startRadius: 0, endRadius: 70))
        }
        for index in 0..<40 {
            var trail = Path()
            trail.move(to: position(index, at: max(0, t - 0.07)))
            trail.addLine(to: position(index, at: t))
            var layer = context
            layer.opacity = pow(1 - life, 1.2)
            layer.stroke(trail, with: .color(colors[(index + colorOffset) % colors.count]),
                         style: StrokeStyle(lineWidth: 4 * (1 - life) + 1, lineCap: .round))
        }
    }
}

// MARK: - Confetti

/// Large, bright pieces that pop from the bottom corners, slow in the air, and drift down.
private struct Particle {
    let isDot: Bool
    let color: Int
    let delay: Double
    let originFraction: CGPoint
    let originOffset: CGPoint
    let velocity: CGVector
    let terminal: CGVector
    let drag: Double
    let sway: Double
    let swayRate: Double
    let phase: Double
    let spin: Double
    let flipRate: Double
    let dimensions: CGSize

    static let sparklePath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -1))
        path.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: 0.12, y: -0.12))
        path.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.12, y: 0.12))
        path.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: -0.12, y: 0.12))
        path.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -0.12, y: -0.12))
        return path
    }()
    private static let unitSquare = Path(CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
    private static let unitCircle = Path(ellipseIn: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))

    static func palette(for theme: TodoTheme) -> [Color] {
        [theme.accent, theme.accent2, theme.accent3, TodoPalette.gold, .white,
         Color(hue: 0.92, saturation: 0.55, brightness: 1), Color(hue: 0.45, saturation: 0.5, brightness: 1), Color(hue: 0.58, saturation: 0.55, brightness: 1)]
    }

    static func make(for milestone: CompletionMilestone) -> [Particle] {
        let tier = milestone.tier
        let impact = milestone.impactTime
        var result: [Particle] = []
        var index = 0

        func cannon(side: Int, wave: Double, count: Int) {
            for _ in 0..<count {
                let i = index; index += 1
                // side 0: bottom centre, 1: bottom left, 2: bottom right.
                let spread = (hash01(i, 1) - 0.5) * 0.7
                let angle = side == 0 ? -Double.pi / 2 + spread : -Double.pi / 2 + (side == 1 ? 0.75 : -0.75) + spread
                let speed = 1100 + hash01(i, 2) * 1000
                result.append(piece(i, delay: impact + wave + hash01(i, 3) * 0.14,
                                    fraction: CGPoint(x: side == 0 ? 0.5 : side == 1 ? 0 : 1, y: 1),
                                    offset: CGPoint(x: side == 0 ? 0 : side == 1 ? -10 : 10, y: -30),
                                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed), drag: 2.5))
            }
        }

        switch tier {
        case 1: cannon(side: 0, wave: 0, count: 70)
        case 2: cannon(side: 1, wave: 0, count: 55); cannon(side: 2, wave: 0, count: 55)
        case 3: for wave in [0.0, 0.45] { cannon(side: 1, wave: wave, count: 65); cannon(side: 2, wave: wave, count: 65) }
        default: for wave in [0.0, 0.5, 1.1, 1.9] { cannon(side: 1, wave: wave, count: 80); cannon(side: 2, wave: wave, count: 80) }
        }

        // A radial pop from the centre at impact.
        for _ in 0..<[0, 30, 50, 100][tier - 1] {
            let i = index; index += 1
            let angle = hash01(i, 1) * 2 * .pi
            let speed = 420 + hash01(i, 2) * 760
            result.append(piece(i, delay: impact + hash01(i, 3) * 0.06,
                                fraction: CGPoint(x: 0.5, y: 0.42), offset: .zero,
                                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed), drag: 3.2))
        }

        // Confetti rain for the big ones.
        for _ in 0..<[0, 0, 60, 150][tier - 1] {
            let i = index; index += 1
            result.append(piece(i, delay: impact + 0.4 + hash01(i, 3) * 2.6,
                                fraction: CGPoint(x: hash01(i, 6), y: 0), offset: CGPoint(x: 0, y: -30),
                                velocity: CGVector(dx: (hash01(i, 1) - 0.5) * 90, dy: 130 + hash01(i, 2) * 150), drag: 1.5))
        }
        return result
    }

    private static func piece(_ i: Int, delay: Double, fraction: CGPoint, offset: CGPoint, velocity: CGVector, drag: Double) -> Particle {
        let dot = hash01(i, 7) < 0.28
        return Particle(
            isDot: dot, color: Int(hash01(i, 10) * 100),
            delay: delay, originFraction: fraction, originOffset: offset, velocity: velocity,
            terminal: CGVector(dx: (hash01(i, 11) - 0.5) * 36, dy: 110 + hash01(i, 12) * 90),
            drag: drag, sway: 10 + hash01(i, 13) * 24, swayRate: 2 + hash01(i, 14) * 3, phase: hash01(i, 15) * 6.28,
            spin: (hash01(i, 16) - 0.5) * 9, flipRate: 5 + hash01(i, 17) * 8,
            dimensions: dot ? CGSize(width: 8, height: 8) : CGSize(width: 11 + hash01(i, 8) * 8, height: 7 + hash01(i, 9) * 5))
    }

    func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double, colors: [Color], fade: Double) {
        let t = elapsed - delay
        guard t >= 0 else { return }
        // Velocity relaxes from the launch speed to a gentle terminal fall.
        let eased = (1 - exp(-drag * t)) / drag
        let x = originFraction.x * size.width + originOffset.x + terminal.dx * t + (velocity.dx - terminal.dx) * eased
            + sway * sin(t * swayRate + phase) * min(1, t * 2)
        let y = originFraction.y * size.height + originOffset.y + terminal.dy * t + (velocity.dy - terminal.dy) * eased
        guard x > -40, x < size.width + 40, y > -60, y < size.height + 60 else { return }
        let flip = cos(t * flipRate + phase)
        var layer = context
        layer.opacity = fade * (0.75 + 0.25 * abs(flip))
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .radians(phase + t * spin))
        layer.scaleBy(x: dimensions.width, y: isDot ? dimensions.height : max(0.15, abs(flip)) * dimensions.height)
        layer.fill(isDot ? Self.unitCircle : Self.unitSquare, with: .color(colors[color % colors.count]))
    }
}

#Preview {
    CelebrationBackdrop(event: CelebrationEvent(milestone: .complete))
        .background { AmbientBackground() }
}
