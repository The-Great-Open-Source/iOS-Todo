import SwiftUI

/// A quiet reward: a small glass card with a ring that fills to the milestone, and a light
/// shower of confetti that grows with each tier. Haptics and a soft chime (see RewardFeedback)
/// land on the same moment as the confetti.
struct CompletionCelebration: View {
    let event: CelebrationEvent
    var dismiss: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todoTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var startedAt = Date()
    @State private var particles: [Particle] = []

    private var milestone: CompletionMilestone { event.milestone }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? milestone.impactTime + 0.6 : timeline.date.timeIntervalSince(startedAt)
            GeometryReader { proxy in
                ZStack {
                    if !reduceMotion {
                        Canvas { context, size in
                            let fade = min(1, max(0, (milestone.totalDuration - elapsed) / 0.7))
                            let colors = theme.confetti
                            for particle in particles {
                                particle.draw(in: &context, size: size, elapsed: elapsed, colors: colors, fade: fade)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    card(elapsed: elapsed)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.40)
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(milestone.rawValue) percent complete. \(milestone.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismisses the celebration")
        .accessibilityAction { dismiss() }
        .task {
            startedAt = Date()
            particles = Particle.make(for: milestone)
            AccessibilityNotification.Announcement("\(milestone.rawValue) percent complete. \(milestone.title)").post()
        }
    }

    private func card(elapsed: Double) -> some View {
        let enter = smooth(elapsed / 0.3)
        let exit = smooth((elapsed - milestone.holdDuration) / 0.4)
        let ring = easeOut(elapsed / (milestone.impactTime + 0.25)) * Double(milestone.rawValue) / 100
        return VStack(spacing: 14) {
            ZStack {
                Circle().stroke(.primary.opacity(0.10), lineWidth: 6)
                Circle().trim(from: 0, to: max(0.001, ring))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if milestone == .complete && ring > 0.98 {
                    Image(systemName: "checkmark").font(.system(size: 30, weight: .semibold)).foregroundStyle(theme.deep)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(Int((ring * 100).rounded()))%")
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            .frame(width: 88, height: 88)
            VStack(spacing: 4) {
                Text(milestone.headline).font(.system(.title2, design: .rounded, weight: .bold)).tracking(-0.5)
                Text(milestone.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36).padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .modifier(GlassCard())
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { dismiss() }
        .scaleEffect(0.94 + 0.06 * enter - 0.04 * exit)
        .opacity(enter * (1 - exit))
        .offset(y: (1 - enter) * 12 - 10 * exit)
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

// MARK: - Confetti

/// Small, soft-coloured pieces that pop from the bottom corners, slow in the air, and drift down.
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

    private static let unitSquare = Path(CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
    private static let unitCircle = Path(ellipseIn: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))

    static func make(for milestone: CompletionMilestone) -> [Particle] {
        let impact = milestone.impactTime
        let perSide = [0, 14, 20, 34][milestone.tier - 1]
        var result: [Particle] = []
        var index = 0

        func cannon(side: Int, count: Int) {
            for _ in 0..<count {
                let i = index; index += 1
                // side 0: bottom centre, 1: bottom left, 2: bottom right.
                let spread = (hash01(i, 1) - 0.5) * 0.6
                let angle = side == 0 ? -Double.pi / 2 + spread : -Double.pi / 2 + (side == 1 ? 0.8 : -0.8) + spread
                let speed = 800 + hash01(i, 2) * 700
                result.append(piece(i, delay: impact + hash01(i, 3) * 0.1,
                                    fraction: CGPoint(x: side == 0 ? 0.5 : side == 1 ? 0 : 1, y: 1),
                                    offset: CGPoint(x: side == 0 ? 0 : side == 1 ? -10 : 10, y: -30),
                                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)))
            }
        }

        if milestone == .quarter { cannon(side: 0, count: 22) }
        else { cannon(side: 1, count: perSide); cannon(side: 2, count: perSide) }
        return result
    }

    private static func piece(_ i: Int, delay: Double, fraction: CGPoint, offset: CGPoint, velocity: CGVector) -> Particle {
        let dot = hash01(i, 7) < 0.3
        return Particle(
            isDot: dot, color: Int(hash01(i, 10) * 100),
            delay: delay, originFraction: fraction, originOffset: offset, velocity: velocity,
            terminal: CGVector(dx: (hash01(i, 11) - 0.5) * 30, dy: 90 + hash01(i, 12) * 70),
            drag: 2.8, sway: 8 + hash01(i, 13) * 18, swayRate: 2 + hash01(i, 14) * 2.5, phase: hash01(i, 15) * 6.28,
            spin: (hash01(i, 16) - 0.5) * 8, flipRate: 5 + hash01(i, 17) * 7,
            dimensions: dot ? CGSize(width: 5, height: 5) : CGSize(width: 7 + hash01(i, 8) * 4, height: 4 + hash01(i, 9) * 3))
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
        layer.opacity = fade * (0.7 + 0.3 * abs(flip))
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .radians(phase + t * spin))
        layer.scaleBy(x: dimensions.width, y: isDot ? dimensions.height : max(0.15, abs(flip)) * dimensions.height)
        layer.fill(isDot ? Self.unitCircle : Self.unitSquare, with: .color(colors[color % colors.count]))
    }
}

#Preview {
    CompletionCelebration(event: CelebrationEvent(milestone: .complete))
        .background { AmbientBackground() }
}
