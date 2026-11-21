import AVFoundation
import CoreHaptics
import UIKit

/// Haptics and sound for completing tasks. Everything is generated on device: custom
/// CoreHaptics patterns and glass-bell chimes synthesised as PCM, so there are no audio assets.
/// Sound uses the ambient session category, so it respects the silent switch and never
/// interrupts music.
@MainActor
final class RewardFeedback {
    static let shared = RewardFeedback()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var sounds: [String: Data] = [:]
    private var players: [AVAudioPlayer] = []

    // MARK: Public API

    /// Renders the sounds off the main thread so the first completion never stutters.
    func prepare() {
        guard sounds.isEmpty else { return }
        Task.detached(priority: .utility) {
            let rendered = Self.renderAllSounds()
            await MainActor.run { RewardFeedback.shared.sounds = rendered }
        }
        _ = startEngine()
    }

    /// A single task was checked off. `combo` counts completions in quick succession.
    func completed(combo: Int, haptics: Bool, sound: Bool) {
        let level = Float(min(combo, 6))
        if haptics {
            play([tap(0, min(1, 0.7 + 0.06 * level), 0.7), tap(0.07, 0.45 + 0.05 * level, 0.35)],
                 fallback: { UIImpactFeedbackGenerator(style: .medium).impactOccurred() })
        }
        if sound { play("combo\(min(max(combo, 1), 8))") }
    }

    /// Pressing Add Task: a soft, springy tap.
    func pressed(haptics: Bool) {
        guard haptics else { return }
        play([tap(0, 0.5, 0.3), tap(0.06, 0.25, 0.2)], fallback: { UIImpactFeedbackGenerator(style: .soft).impactOccurred() })
    }

    /// A new tile has landed in the list.
    func added(haptics: Bool) {
        guard haptics else { return }
        play([tap(0, 0.45, 0.7), tap(0.09, 0.7, 0.5)], fallback: { UIImpactFeedbackGenerator(style: .light).impactOccurred() })
    }

    /// A tile was swiped away: a low, quick thud.
    func removed(haptics: Bool) {
        guard haptics else { return }
        play([tap(0, 0.6, 0.15)], fallback: { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() })
    }

    /// A light tick when the tab changes.
    func tabChanged(haptics: Bool) {
        guard haptics else { return }
        play([tap(0, 0.4, 0.5)], fallback: { UISelectionFeedbackGenerator().selectionChanged() })
    }

    func reopened(haptics: Bool, sound: Bool) {
        if haptics { play([tap(0, 0.4, 0.2)], fallback: { UISelectionFeedbackGenerator().selectionChanged() }) }
        if sound { play("reopen") }
    }

    func celebrate(_ milestone: CompletionMilestone, haptics: Bool, sound: Bool) {
        if haptics {
            let (events, curves) = hapticPattern(for: milestone)
            play(events, curves: curves, fallback: { UINotificationFeedbackGenerator().notificationOccurred(.success) })
            // A system "success" buzz on top, at the moment of impact, so the hit is felt even if the
            // custom pattern is dulled by the phone's settings.
            DispatchQueue.main.asyncAfter(deadline: .now() + milestone.impactTime) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        if sound { play("milestone\(milestone.tier)") }
    }

    // MARK: Haptics

    private func startEngine() -> CHHapticEngine? {
        guard supportsHaptics else { return nil }
        if let engine { return engine }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
            return engine
        } catch {
            return nil
        }
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = [], fallback: () -> Void) {
        guard let engine = startEngine() else { return fallback() }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    private func tap(_ time: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    /// A drumroll that builds, a hard thump when the colour hits, then a long rumble that fades in steps
    /// with a pulse for every shockwave and, for the big ones, a shimmer of ticks. It is strong on purpose:
    /// the celebration plays behind the interface, so the vibration carries much of the feeling.
    private func hapticPattern(for milestone: CompletionMilestone) -> ([CHHapticEvent], [CHHapticParameterCurve]) {
        let tier = milestone.tier
        let rolls = [3, 5, 7, 9][tier - 1]
        let span = milestone.impactTime - 0.07
        var events: [CHHapticEvent] = []
        for k in 0..<rolls {
            let fraction = Double(k) / Double(rolls)
            events.append(tap(span * (1 - pow(1 - fraction, 1.6)), Float(0.5 + 0.5 * fraction), 0.6))
        }
        let thump = milestone.impactTime
        events.append(tap(thump, 1.0, 0.45))
        events.append(tap(thump + 0.05, 1.0, 0.9))
        // The rumble, in four steps that die away.
        let rumble = [0.6, 1.0, 1.5, 2.4][tier - 1]
        for (step, level) in [1.0, 0.8, 0.55, 0.3].enumerated() {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(level)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(0.25 + 0.1 * Double(step))),
            ], relativeTime: thump + rumble / 4 * Double(step), duration: rumble / 4))
        }
        // One pulse for each shockwave that follows the first.
        for ring in 1..<[1, 2, 3, 5][tier - 1] {
            events.append(tap(thump + Double(ring) * 0.28, 0.9, 0.7))
        }
        // A shimmer of light ticks as the confetti falls.
        for k in 0..<[0, 0, 8, 22][tier - 1] {
            events.append(tap(thump + rumble + 0.1 + Double(k) * 0.14, k.isMultiple(of: 3) ? 0.5 : 0.3, 0.95))
        }
        return (events, [])
    }

    // MARK: Sound

    private func play(_ name: String) {
        guard let data = sounds[name] else { return }
        players.removeAll { !$0.isPlaying }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.volume = 0.8
            player.play()
            players.append(player)
        } catch {
            // Sound is a bonus; never surface an error for it.
        }
    }

    private struct Note {
        let frequency: Double
        let start: Double
        let length: Double
        var amplitude = 1.0
    }

    // C major pentatonic from C5, so back-to-back completions climb like a little melody.
    private nonisolated static let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51]
    private nonisolated static let c4 = 261.63, c5 = 523.25, e5 = 659.25, g5 = 783.99
    private nonisolated static let c6 = 1046.50, e6 = 1318.51, g6 = 1567.98, c7 = 2093.00

    private nonisolated static func renderAllSounds() -> [String: Data] {
        var result: [String: Data] = [:]
        for combo in 1...8 {
            let index = combo - 1
            result["combo\(combo)"] = wav([
                Note(frequency: scale[index], start: 0, length: 0.55),
                Note(frequency: scale[min(index + 2, 7)] * 2, start: 0.07, length: 0.35, amplitude: 0.3),
            ])
        }
        result["reopen"] = wav([Note(frequency: 392.0, start: 0, length: 0.22, amplitude: 0.6)])
        result["milestone1"] = wav(arpeggio([c5, e5, g5], gap: 0.075, length: 0.9))
        result["milestone2"] = wav(arpeggio([c5, e5, g5, c6], gap: 0.07, length: 1.1))
        result["milestone3"] = wav(arpeggio([c5, e5, g5, c6, e6], gap: 0.065, length: 1.4)
            + [Note(frequency: c4, start: 0.3, length: 1.2, amplitude: 0.5)])
        result["milestone4"] = wav(arpeggio([c5, e5, g5, c6, e6], gap: 0.07, length: 1.4)
            + [c4, c5, g5, c6].map { Note(frequency: $0, start: 0.4, length: 1.6, amplitude: 0.45) })
        return result
    }

    private nonisolated static func arpeggio(_ frequencies: [Double], gap: Double, length: Double) -> [Note] {
        frequencies.enumerated().map { Note(frequency: $0.element, start: Double($0.offset) * gap, length: length) }
    }

    /// Glass-bell timbre: a pure fundamental, a quieter inharmonic partial for the "ting", and
    /// a faint high shimmer that dies away faster.
    private nonisolated static func wav(_ notes: [Note]) -> Data {
        let sampleRate = 44100.0
        let total = (notes.map { $0.start + $0.length }.max() ?? 0.2) + 0.05
        var samples = [Float](repeating: 0, count: Int(total * sampleRate))
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [(1, 1, 1), (2.76, 0.30, 2.2), (5.4, 0.10, 3.5)]
        for note in notes {
            let begin = Int(note.start * sampleRate)
            let count = min(Int(note.length * sampleRate), samples.count - begin)
            guard count > 0 else { continue }
            for index in 0..<count {
                let t = Double(index) / sampleRate
                let attack = min(1, t / 0.004)
                var value = 0.0
                for partial in partials {
                    value += partial.gain * sin(2 * .pi * note.frequency * partial.ratio * t)
                        * exp(-t * 5.5 * partial.decay / note.length)
                }
                let release = min(1, Double(count - index) / (0.01 * sampleRate))
                samples[begin + index] += Float(value * attack * release * note.amplitude)
            }
        }
        let peak = samples.map { abs($0) }.max() ?? 1
        let scale = peak > 0 ? 0.55 / peak : 1
        var pcm = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) } }
        pcm.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples.count * 2))
        pcm.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        pcm.append(contentsOf: Array("data".utf8)); append(UInt32(samples.count * 2))
        for sample in samples { append(Int16(max(-1, min(1, sample * scale)) * 32767)) }
        return pcm
    }
}
