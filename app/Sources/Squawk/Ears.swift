import AVFoundation
import AppKit
import Speech
import SquawkCore

/// Listening for what you ask it. Recognition happens on this Mac: nothing is
/// recorded, nothing is written down, and nothing leaves the machine.
///
/// Two ways in, both optional. Holding the hotkey records until it is let go,
/// which needs no wake word and no microphone open when you are not using it.
/// The wake word keeps the microphone running, which costs a little of a core
/// and is why it is a separate setting rather than the only way.
@MainActor
final class Ears {
    enum Trouble: Equatable {
        case refused
        case unavailable
        case failed(String)

        var message: String {
            switch self {
            case .refused:
                """
                Squawk was not allowed to listen. You can grant it under System \
                Settings, Privacy and Security, under Microphone and under \
                Speech Recognition.
                """
            case .unavailable:
                "This Mac cannot recognise speech without sending it away, so Squawk will not listen."
            case .failed(let detail):
                "Squawk could not listen. \(detail)"
            }
        }
    }

    /// A finished utterance. Partial results drive this too, so a command can
    /// act the moment it is understood rather than after a pause.
    var onHeard: ((String, Bool) -> Void)?

    private let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var wantsContinuous = false
    private var restarting = false
    /// Whether it is meant to be listening at all, held key included. Kept
    /// apart from `wantsContinuous` so a device change can put either back.
    private var wanted = false
    private var deviceWatch: NSObjectProtocol?
    /// Told when the microphone was swapped out from under it, which is worth
    /// a line in the log: the pet looked like it was listening and was not.
    var onDeviceChanged: ((Bool) -> Void)?

    var isRunning: Bool { engine.isRunning }

    /// Asks for both permissions. The microphone one is raised by starting the
    /// engine, so it is asked for here rather than at the first word.
    ///
    /// `nonisolated`, and every closure in it `@Sendable`, because these answer
    /// on whatever queue the permission service replies on. Left to inherit
    /// this class's main actor, the compiler inserts an isolation check that
    /// fails the moment the answer arrives, and the app dies on the spot: the
    /// first time anyone turned listening on, it trapped rather than asking.
    nonisolated static func requestConsent(_ finished: @escaping @Sendable (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { @Sendable speech in
            guard speech == .authorized else { return finished(false) }
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable microphone in
                finished(microphone)
            }
        }
    }

    nonisolated static var isPermitted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Runs until stopped. `continuous` restarts itself, because an on device
    /// session is capped at about a minute and simply ends.
    @discardableResult
    func start(continuous: Bool) -> Trouble? {
        wantsContinuous = continuous
        wanted = true
        guard let recogniser, recogniser.isAvailable else { return .unavailable }
        guard recogniser.supportsOnDeviceRecognition else { return .unavailable }
        guard Self.isPermitted else { return .refused }
        return begin()
    }

    private func begin() -> Trouble? {
        stopTask()
        guard let recogniser else { return .unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        // The whole point: it is recognised here or not at all.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return .failed("There is no microphone to listen with.") }
        input.removeTap(onBus: 0)
        // Also `@Sendable`: this one is called on the audio thread, and an
        // isolation check there would trap in the middle of recording.
        // Appending from that thread is what the request is for, which is what
        // `nonisolated(unsafe)` is saying out loud here.
        nonisolated(unsafe) let sink = request
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable buffer, _ in
            sink.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return .failed(error.localizedDescription)
        }
        watchForDeviceChanges()
        task = recogniser.recognitionTask(with: request) { @Sendable [weak self] result, error in
            // Read out here, on whatever thread this is, so only plain values
            // cross to the main actor: the result itself is not safe to send.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let ended = error != nil || isFinal
            Task { @MainActor in
                guard let self else { return }
                if let transcript { self.onHeard?(transcript, isFinal) }
                // A session that ends is restarted, or the wake word works for
                // a minute after launch and never again.
                if ended { self.restart() }
            }
        }
        return nil
    }

    /// Starts a fresh session, which also clears the transcript so the next
    /// command is not read against the last one.
    func restart() {
        guard wantsContinuous, !restarting else { return stop() }
        restarting = true
        // A beat, so a failing session cannot spin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            restarting = false
            guard wantsContinuous else { return }
            _ = begin()
        }
    }

    /// Stops recording but lets the recogniser deliver what it heard, which is
    /// what the end of a held key means. Cancelling here would throw the
    /// sentence away at the moment it was finished.
    func finish() {
        wantsContinuous = false
        wanted = false
        request?.endAudio()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Plugging headphones in, or pulling them out, replaces the input device
    /// under a running engine. It keeps running and delivers nothing at all,
    /// so the lamp stays lit and the pet hears nothing until this rebuilds it.
    private func watchForDeviceChanges() {
        guard deviceWatch == nil else { return }
        deviceWatch = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.wanted else { return }
                let trouble = self.begin()
                self.onDeviceChanged?(trouble == nil)
            }
        }
    }

    func stop() {
        wanted = false
        wantsContinuous = false
        stopTask()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func stopTask() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}
