import AVFoundation
import Foundation
import Observation
import Speech

/// Listens through the microphone and turns speech into live text. It prefers on-device recognition,
/// so on supported languages nothing leaves the phone, and it stops by itself after a pause.
@MainActor @Observable
final class VoiceDictation {
    enum State: Equatable {
        case idle, starting, listening
        case denied(String)
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    /// 0...1, how loud the room is right now, for the pulsing ring.
    private(set) var level: Double = 0

    private let recorder = Recorder()
    private var silenceTask: Task<Void, Never>?
    private var onFinish: (() -> Void)?

    var isListening: Bool { state == .listening || state == .starting }

    /// Starts listening. `onFinish` runs once when listening ends, by a pause or by `stop()`.
    func start(onFinish: @escaping () -> Void) async {
        guard !isListening else { return }
        self.onFinish = onFinish
        transcript = ""
        state = .starting
        guard await Self.requestSpeechAccess() else {
            state = .denied("Allow Speech Recognition for Todos in Settings to add tasks by voice.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied("Allow the microphone for Todos in Settings to add tasks by voice.")
            return
        }
        let box = WeakBox(self)
        do {
            try recorder.start(
                onText: { text, isFinal in
                    Task { @MainActor in box.target?.heard(text, isFinal: isFinal) }
                },
                onLevel: { value in
                    Task { @MainActor in box.target?.level = value }
                },
                onFailure: { message in
                    Task { @MainActor in box.target?.failed(message) }
                })
            state = .listening
            armSilenceTimer(after: 6)
        } catch {
            state = .unavailable("Couldn’t start listening. Please try again.")
        }
    }

    /// Ends listening, keeping whatever was heard.
    func stop() {
        guard isListening else { return }
        finish()
    }

    func reset() {
        recorder.stop()
        silenceTask?.cancel()
        transcript = ""
        level = 0
        state = .idle
        onFinish = nil
    }

    private func heard(_ text: String, isFinal: Bool) {
        guard state == .listening else { return }
        transcript = text
        if isFinal { finish() } else { armSilenceTimer(after: 1.8) }
    }

    private func failed(_ message: String) {
        guard isListening else { return }
        if transcript.isEmpty { state = .unavailable(message); recorder.stop(); silenceTask?.cancel(); level = 0 }
        else { finish() }
    }

    /// A pause after speaking ends the recording; before anything is said, a longer wait gives up.
    private func armSilenceTimer(after seconds: Double) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard isListening else { return }
        silenceTask?.cancel()
        recorder.stop()
        level = 0
        state = .idle
        let callback = onFinish
        onFinish = nil
        callback?()
    }

    private static func requestSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}

/// The audio and recognition plumbing. Its callbacks arrive on audio and recognition threads,
/// so it is kept away from the main actor.
private nonisolated final class Recorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(onText: @escaping @Sendable (String, Bool) -> Void,
               onLevel: @escaping @Sendable (Double) -> Void,
               onFailure: @escaping @Sendable (String) -> Void) throws {
        stop()
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            throw CocoaError(.featureUnsupported)
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        request.addsPunctuation = false
        self.request = request

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onText(result.bestTranscription.formattedString, result.isFinal) }
            else if error != nil { onFailure("Couldn’t hear that. Please try again.") }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let rms = count > 0 ? (sum / Float(count)).squareRoot() : 0
            onLevel(min(1, Double(rms) * 9))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class WeakBox: @unchecked Sendable {
    weak var target: VoiceDictation?
    init(_ target: VoiceDictation) { self.target = target }
}
