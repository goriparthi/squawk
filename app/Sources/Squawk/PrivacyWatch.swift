import AVFoundation
import AppKit
import CoreAudio
import SquawkCore

/// Watches whether anything on the machine is using the microphone or the
/// camera, so the pet can say so.
///
/// Both answers come from public system frameworks rather than from anything
/// private or scraped: Core Audio reports whether an input device is running
/// for anybody, and AVFoundation reports whether a capture device is in use by
/// another application. Neither needs permission, because neither opens the
/// device: it is the same question the system's own dots answer.
@MainActor
final class PrivacyWatch {
    var onChange: ((PrivacyState) -> Void)?

    private(set) var state = PrivacyState.clear {
        didSet {
            guard state != oldValue else { return }
            onChange?(state)
        }
    }

    private var timer: Timer?
    private var cameraObservations: [NSKeyValueObservation] = []
    private var discovery: AVCaptureDevice.DiscoverySession?

    func start() {
        guard timer == nil else { return }
        watchCameras()
        // Core Audio's running state has a property listener, but the set of
        // input devices changes as things are plugged in, and a poll at this
        // rate costs nothing measurable. It is a boolean read, not a capture.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cameraObservations.removeAll()
        discovery = nil
        state = .clear
    }

    private func refresh() {
        state = PrivacyState(microphone: Self.anyProcessIsRecording(),
                             camera: anyCameraIsInUse())
    }

    // MARK: - The microphone

    /// True when any process on the machine is running audio input.
    ///
    /// Asked per process, not per device. The device level answer,
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere`, is true when a device is
    /// running in *either* direction, so a Bluetooth headset playing music
    /// reported its microphone as live, and so did this app's own tap.
    /// `kAudioProcessPropertyIsRunningInput` asks the question that was
    /// actually meant.
    private static func anyProcessIsRecording() -> Bool {
        let mine = ProcessInfo.processInfo.processIdentifier
        for process in audioProcesses() {
            // Squawk listening to what is playing is not the microphone being
            // used, and a pet that lit up at its own feature would be lying.
            if pid(of: process) == mine { continue }
            if isRunningInput(process) { return true }
        }
        return false
    }

    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var processes = [AudioObjectID](repeating: 0,
                                        count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &processes) == noErr
        else { return [] }
        return processes
    }

    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func pid(of process: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr
        else { return -1 }
        return value
    }

    /// What every audio process says about itself, for working out which one is
    /// claiming to record when nothing is.
    static func describeProcesses() -> [String] {
        let mine = ProcessInfo.processInfo.processIdentifier
        let processes = audioProcesses()
        guard !processes.isEmpty else {
            return ["no audio process list: this system is older than macOS 14.2"]
        }
        return processes.map { process in
            let owner = pid(of: process)
            let name = owner > 0
                ? (NSRunningApplication(processIdentifier: owner)?.localizedName ?? "pid \(owner)")
                : "unknown"
            return "\(name)  input=\(isRunningInput(process))\(owner == mine ? "  (us)" : "")"
        }
    }

    // MARK: - The camera

    /// `isInUseByAnotherApplication` is AVFoundation's own answer to this, and
    /// reading it does not open the camera, so it needs no permission and turns
    /// no light on by itself.
    private func watchCameras() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified)
        discovery = session
        cameraObservations = session.devices.map { device in
            device.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    private func anyCameraIsInUse() -> Bool {
        discovery?.devices.contains { $0.isInUseByAnotherApplication } ?? false
    }
}
