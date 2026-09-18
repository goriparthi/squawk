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
        state = PrivacyState(microphone: Self.anyInputIsRunning(),
                             camera: anyCameraIsInUse())
    }

    // MARK: - The microphone

    /// True when any audio input device on the machine is running for anyone.
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` is exactly this question,
    /// asked of Core Audio rather than inferred from anything.
    private static func anyInputIsRunning() -> Bool {
        for device in inputDevices() where isRunningSomewhere(device) { return true }
        return false
    }

    private static func inputDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr
        else { return [] }
        var devices = [AudioObjectID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &devices) == noErr
        else { return [] }
        return devices.filter { hasInputStreams($0) }
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0
        else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr
        else { return false }
        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
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
