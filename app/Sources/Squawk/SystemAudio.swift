import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import SquawkCore

/// Listens to what the machine is playing, so the pet can react to it.
///
/// Uses a Core Audio process tap, which is the only supported way to see system
/// wide output: the now playing APIs are private and Apple has been closing
/// them. A tap is read only, never recorded, and never leaves this process; all
/// that comes out the other end is five numbers between zero and one.
///
/// Off unless asked for. It needs the user's consent, and a desk toy has no
/// business asking for that until it is told to.
///
/// `@unchecked Sendable` because Core Audio calls `consume` on its real time
/// thread. Shared state is copied out under `lock` before it is used; the
/// diagnostics flags are touched only on that thread, or before it starts.
final class SystemAudio: @unchecked Sendable {
    /// Why it is not running, in words that can be put in front of someone.
    enum Trouble: Equatable {
        case needsNewerSystem
        case refused
        case noOutputDevice
        case failed(String)

        var message: String {
            switch self {
            case .needsNewerSystem:
                "Listening to what is playing needs macOS 14.4 or later."
            case .refused:
                """
                macOS did not allow Squawk to listen to this computer's audio. \
                You can grant it under System Settings, Privacy and Security, \
                Audio Recording.
                """
            case .noOutputDevice:
                "There is no audio output device to listen to."
            case .failed(let detail):
                "Squawk could not listen to what is playing. \(detail)"
            }
        }
    }

    /// Called on the main queue, at whatever rate audio arrives.
    var onSpectrum: ((Spectrum) -> Void)?

    private let lock = NSLock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var running = false

    // The analyser. One setup, reused for every block that arrives.
    private static let fftSize = 1_024
    private var fft: vDSP.FFT<DSPSplitComplex>?
    private var window = [Float]()
    private var sampleBuffer = [Float]()
    private var bins: [Range<Int>] = []
    private var sampleRate: Double = 48_000
    /// Set by the self test, which is the only way to see inside a real time
    /// callback that is handing back silence.
    var diagnostics = false
    private var described = false

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// Starts listening. Returns what went wrong, or nil when it is running.
    @discardableResult
    func start() -> Trouble? {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return nil }
        guard #available(macOS 14.4, *) else { return .needsNewerSystem }

        guard let output = Self.defaultOutputDeviceUID() else { return .noOutputDevice }
        if diagnostics { NSLog("squawk audio: output device %@", output) }

        // Everything, minus nothing: a global mono mixdown, which is all a
        // level meter needs and avoids enumerating every process on the machine.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Squawk"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        // A global tap still has to be told which device's mix to follow, or it
        // is created happily and hands back silence forever.
        description.deviceUID = output

        var tap = AudioObjectID(kAudioObjectUnknown)
        let made = AudioHardwareCreateProcessTap(description, &tap)
        guard made == noErr, tap != kAudioObjectUnknown else {
            // A tap refused for want of consent comes back as a permissions
            // error rather than a prompt we can wait on.
            return made == kAudioHardwareIllegalOperationError || made == -10851
                ? .refused
                : .failed("Core Audio returned \(made) making the tap.")
        }
        tapID = tap

        // The UID Core Audio actually gave the tap, not the one the description
        // was made with. An aggregate that names a tap by the wrong UID is
        // built without complaint and its stream is silent forever.
        let tapUID = Self.tapUID(of: tap) ?? description.uuid.uuidString
        if diagnostics { NSLog("squawk audio: tap uid %@", tapUID) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Squawk Listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUID,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        let built = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard built == noErr, device != kAudioObjectUnknown else {
            teardownLocked()
            return .failed("Core Audio returned \(built) making the device.")
        }
        aggregateID = device

        sampleRate = Self.sampleRate(of: device) ?? 48_000
        prepareAnalyser()

        var proc: AudioDeviceIOProcID?
        let installed = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) {
            [weak self] _, input, _, _, _ in
            self?.consume(input)
        }
        guard installed == noErr, let proc else {
            teardownLocked()
            return .failed("Core Audio returned \(installed) installing the reader.")
        }
        procID = proc

        let started = AudioDeviceStart(device, proc)
        guard started == noErr else {
            teardownLocked()
            return .failed("Core Audio returned \(started) starting the device.")
        }
        running = true
        return nil
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        teardownLocked()
        let silent = Spectrum.silent
        DispatchQueue.main.async { [weak self] in self?.onSpectrum?(silent) }
    }

    private func teardownLocked() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.4, *) { AudioHardwareDestroyProcessTap(tapID) }
            tapID = kAudioObjectUnknown
        }
        running = false
    }

    // MARK: - Analysis

    private func prepareAnalyser() {
        let size = Self.fftSize
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(size))),
                       radix: .radix2, ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: size, isHalfWindow: false)
        sampleBuffer = []
        sampleBuffer.reserveCapacity(size * 2)
        bins = SpectrumMeter.bins(sampleRate: sampleRate, fftSize: size)
    }

    /// Called on Core Audio's own real time thread. Nothing here allocates
    /// beyond what was reserved, and nothing here touches the UI: it hands a
    /// finished spectrum to the main queue and returns.
    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first,
              let data = first.mData,
              first.mNumberChannels > 0
        else { return }

        if diagnostics, !described {
            described = true
            var peak: Float = 0
            if let raw = first.mData {
                let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
                let floats = raw.bindMemory(to: Float.self, capacity: count)
                for index in 0..<count { peak = max(peak, abs(floats[index])) }
            }
            NSLog("squawk audio: buffers=%d channels=%u bytes=%u peak=%f",
                  buffers.count, first.mNumberChannels, first.mDataByteSize, peak)
        }
        let channels = Int(first.mNumberChannels)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        guard frames > 0 else { return }
        let samples = data.bindMemory(to: Float.self, capacity: frames * channels)

        lock.lock()
        for frame in 0..<frames {
            // Mixed down: a meter has no use for the stereo image.
            var sum: Float = 0
            for channel in 0..<channels {
                sum += samples[frame * channels + channel]
            }
            sampleBuffer.append(sum / Float(channels))
        }
        let size = Self.fftSize
        guard sampleBuffer.count >= size else {
            lock.unlock()
            return
        }
        let block = Array(sampleBuffer.suffix(size))
        // Keep half a window of overlap, so a transient between blocks is not
        // analysed twice and not missed either.
        sampleBuffer.removeFirst(max(0, sampleBuffer.count - size / 2))
        let bins = self.bins
        let window = self.window
        let fft = self.fft
        lock.unlock()

        guard let fft, window.count == size else { return }
        var windowed = [Float](repeating: 0, count: size)
        vDSP.multiply(block, window, result: &windowed)

        var real = [Float](repeating: 0, count: size / 2)
        var imaginary = [Float](repeating: 0, count: size / 2)
        var magnitudes = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &split, 1, vDSP_Length(size / 2))
                }
                var output = DSPSplitComplex(realp: realPointer.baseAddress!,
                                             imagp: imaginaryPointer.baseAddress!)
                fft.forward(input: split, output: &output)
                vDSP.absolute(output, result: &magnitudes)
            }
        }
        // vDSP's real FFT packs two sides into one, so the magnitudes come back
        // at twice the amplitude of the signal that made them.
        var scale = Float(2) / Float(size)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(size / 2))

        var spectrum = Spectrum()
        let measured = SpectrumMeter.bands(from: magnitudes, bins: bins)
        spectrum.bands = measured.display
        spectrum.energy = measured.energy
        var meanSquare: Float = 0
        vDSP_measqv(block, 1, &meanSquare, vDSP_Length(size))
        spectrum.level = SpectrumMeter.loudness(Double(meanSquare.squareRoot()))

        DispatchQueue.main.async { [weak self] in self?.onSpectrum?(spectrum) }
    }

    // MARK: - Devices

    private static func tapUID(of tap: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let read = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(tap, &address, 0, nil, &size, pointer)
        }
        guard read == noErr else { return nil }
        return uid as String?
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        let read = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &uidSize, pointer)
        }
        guard read == noErr else { return nil }
        return uid as String?
    }

    private static func sampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr,
              rate > 0
        else { return nil }
        return rate
    }
}
