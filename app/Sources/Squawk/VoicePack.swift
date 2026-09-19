import CryptoKit
import Foundation
import SquawkCore

/// The optional spoken voice. Squawk ships no model and no dependency: the
/// system's own synthesiser does the talking out of the box, and this is the
/// better sounding alternative, fetched once on request and kept in
/// `~/.squawk/voice`. Nothing here is required for the app to speak.
///
/// The engine is sherpa-onnx (Apache 2.0), which runs the Piper voices as
/// published. Piper's own macOS build cannot be used: its last release ships an
/// x86_64 binary inside the file named aarch64, unsigned, with its libraries
/// missing altogether.
enum VoicePack {
    struct Download: Sendable {
        let url: URL
        /// Pinned, because this is a third party binary: it carries no
        /// signature of ours to check, so the exact bytes are the check. Each
        /// one here was downloaded and hashed, and matches the digest GitHub
        /// records for the asset.
        let sha256: String
        let bytes: Int
    }

    struct Voice: Sendable, Equatable, Identifiable {
        let id: String
        let title: String
        /// How it sounds, in the few words a menu has room for.
        let note: String
        let download: Download
        /// What the tarball unpacks into.
        let folder: String

        static func == (lhs: Voice, rhs: Voice) -> Bool { lhs.id == rhs.id }
    }

    /// One binary and one library out of a release that carries thirty.
    static let engine: Download? = {
        #if arch(arm64)
        Download(
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared.tar.bz2")!,
            sha256: "b10e5c7e2c30ea03de9c442655d14860d9edc475c6251d58a8f5f06e913a1d56",
            bytes: 20_314_448)
        #elseif arch(x86_64)
        Download(
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-x64-shared.tar.bz2")!,
            sha256: "54aad64acee9d2d596535a6080d6f22602a720af5460e1d50461b1e1b06bee40",
            bytes: 22_846_038)
        #else
        nil
        #endif
    }()

    private static func voice(_ id: String, _ title: String, _ note: String,
                              _ sha: String, _ bytes: Int) -> Voice {
        let folder = "vits-piper-\(id)"
        return Voice(
            id: id, title: title, note: note,
            download: Download(
                url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(folder).tar.bz2")!,
                sha256: sha, bytes: bytes),
            folder: folder)
    }

    /// A few, chosen rather than listed: a wall of ninety voices is not a
    /// choice. Every one is English and every one has a recorded digest.
    static let catalog: [Voice] = [
        voice("en_US-amy-low", "Amy", "American, warm",
              "c70f5284a09a7fd4ed203b39b2ff51cac1432b422b852eb647b481dade3cf639", 67_095_344),
        voice("en_US-ryan-low", "Ryan", "American, low",
              "08d0522884652402b32d6995d9df776e85c7451a333fabe97e9e4635faf568ac", 67_100_179),
        voice("en_GB-alan-low", "Alan", "British",
              "1308e730b7a12c3b64b669d65daa0138fcb83b1a086edee92fa9fa68cb0290dd", 67_086_942),
        voice("en_US-lessac-medium", "Lessac", "American, clearest",
              "9e3febfacf0abf4270172d2958bcec246032b7e88efc2720840cc80c93de334e", 67_230_653),
    ]

    static func voice(id: String) -> Voice? { catalog.first { $0.id == id } }

    // MARK: - Where it lives

    static var root: String {
        (SocketPath.directory(home: NSHomeDirectory()) as NSString)
            .appendingPathComponent("voice")
    }
    static var binary: String { path("bin/sherpa-onnx-offline-tts") }
    static var phonemes: String { path("espeak-ng-data") }
    static var cache: String { path("cache") }
    static func voiceFolder(_ voice: Voice) -> String { path("voices/\(voice.id)") }
    static func model(_ voice: Voice) -> String { "\(voiceFolder(voice))/\(voice.id).onnx" }
    static func tokens(_ voice: Voice) -> String { "\(voiceFolder(voice))/tokens.txt" }

    private static func path(_ tail: String) -> String {
        (root as NSString).appendingPathComponent(tail)
    }

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Everything a voice needs to speak, which is the engine, the phonemes and
    /// the voice itself. A half finished install counts as not installed.
    static var engineIsReady: Bool { exists(binary) && exists(phonemes) }
    static func isReady(_ voice: Voice) -> Bool {
        engineIsReady && exists(model(voice)) && exists(tokens(voice))
    }
    static var installed: [Voice] { catalog.filter(isReady) }

    /// How much this costs, before anyone commits to it.
    static func downloadBytes(for voice: Voice) -> Int {
        voice.download.bytes + (engineIsReady ? 0 : (engine?.bytes ?? 0))
    }

    static func describe(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Removes a voice, leaving the engine for the others.
    static func remove(_ voice: Voice) {
        try? FileManager.default.removeItem(atPath: voiceFolder(voice))
        try? FileManager.default.removeItem(atPath: cache)
    }

    // MARK: - Fetching it

    enum Trouble: Error, Equatable {
        case noBuild
        case failed(String)
        case cancelled

        var message: String {
            switch self {
            case .noBuild: "There is no speech engine build for this Mac."
            case .cancelled: "Cancelled."
            case .failed(let detail): detail
            }
        }
    }

    /// Downloads whatever is missing and installs it. `progress` runs on the
    /// main queue from 0 to 1 across the whole job, and so does `finished`.
    /// Returns the job, so it can be cancelled.
    @discardableResult
    static func install(
        _ voice: Voice,
        progress: @escaping @Sendable (Double) -> Void,
        finished: @escaping @Sendable (Trouble?) -> Void
    ) -> Fetch? {
        guard let engine else {
            finished(.noBuild)
            return nil
        }
        // The engine comes first and only once; after that it is just voices.
        let jobs: [Fetch.Job] = (engineIsReady ? [] : [Fetch.Job(download: engine, voice: nil)])
            + [Fetch.Job(download: voice.download, voice: voice)]
        let fetch = Fetch()
        fetch.run(jobs, progress: progress, finished: finished)
        return fetch
    }

    /// One download at a time, cancellable, with the bytes checked before
    /// anything is unpacked. Holds the run's state itself: a sequence of
    /// downloads cannot be driven from captured variables in Swift 6.
    final class Fetch: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        struct Job: Sendable {
            let download: Download
            /// Nil for the engine.
            let voice: Voice?
        }

        private let lock = NSLock()
        private var session: URLSession?
        private var jobs: [Job] = []
        private var index = 0
        private var completedBytes = 0
        private var totalBytes = 1
        private var onProgress: (@Sendable (Double) -> Void)?
        private var onFinished: (@Sendable (Trouble?) -> Void)?

        func run(_ jobs: [Job],
                 progress: @escaping @Sendable (Double) -> Void,
                 finished: @escaping @Sendable (Trouble?) -> Void) {
            lock.lock()
            self.jobs = jobs
            index = 0
            completedBytes = 0
            totalBytes = max(1, jobs.reduce(0) { $0 + $1.download.bytes })
            onProgress = progress
            onFinished = finished
            lock.unlock()
            startNext()
        }

        func cancel() {
            lock.lock()
            let session = self.session
            self.session = nil
            lock.unlock()
            session?.invalidateAndCancel()
            report(.cancelled)
        }

        private func startNext() {
            lock.lock()
            guard index < jobs.count else {
                lock.unlock()
                report(nil)
                return
            }
            let job = jobs[index]
            let configuration = URLSessionConfiguration.ephemeral
            // A stalled connection is indistinguishable from a frozen dialog,
            // so both the request and the whole transfer have a deadline.
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 20 * 60
            let session = URLSession(configuration: configuration, delegate: self,
                                     delegateQueue: nil)
            self.session = session
            lock.unlock()
            session.downloadTask(with: job.download.url).resume()
        }

        /// Nil finishes the whole run successfully; anything else stops it.
        private func report(_ trouble: Trouble?) {
            lock.lock()
            let finished = onFinished
            onFinished = nil
            onProgress = nil
            lock.unlock()
            guard let finished else { return }
            DispatchQueue.main.async { finished(trouble) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            lock.lock()
            let fraction = Double(completedBytes + Int(totalBytesWritten)) / Double(totalBytes)
            let progress = onProgress
            lock.unlock()
            guard let progress else { return }
            DispatchQueue.main.async { progress(min(1, max(0, fraction))) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            lock.lock()
            guard index < jobs.count else { return lock.unlock() }
            let job = jobs[index]
            lock.unlock()

            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return report(.failed("The download answered \(status)."))
            }
            // Moved out of the session's temporary spot before returning, which
            // is the one moment the file is guaranteed to still be there.
            let kept = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("squawk-download-\(UUID().uuidString).tar.bz2")
            do {
                try FileManager.default.moveItem(at: location, to: kept)
            } catch {
                return report(.failed("Could not keep the download: \(error.localizedDescription)"))
            }
            guard digest(of: kept) == job.download.sha256 else {
                try? FileManager.default.removeItem(at: kept)
                return report(.failed("The download did not match its expected contents."))
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let trouble = job.voice.map { unpack($0, from: kept) } ?? unpackEngine(kept)
                try? FileManager.default.removeItem(at: kept)
                if let trouble { return report(trouble) }
                lock.lock()
                completedBytes += job.download.bytes
                index += 1
                lock.unlock()
                startNext()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard let error else { return }
            let failure = (error as NSError).code == NSURLErrorCancelled
                ? Trouble.cancelled
                : .failed(error.localizedDescription)
            report(failure)
        }
    }

    private static func digest(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Unpacking it

    /// Keeps the one binary and the one library it actually loads, out of the
    /// thirty the release carries. Sixty megabytes of tools nobody will run is
    /// not something to leave in someone's home directory.
    private static func unpackEngine(_ file: URL) -> Trouble? {
        let staging = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("squawk-engine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: staging) }
        if let trouble = extract(file, into: staging) { return trouble }
        guard let unpacked = (try? FileManager.default.contentsOfDirectory(atPath: staging))?
            .first(where: { $0.hasPrefix("sherpa-onnx-") })
        else { return .failed("The speech engine did not contain what was expected.") }
        let from = (staging as NSString).appendingPathComponent(unpacked)
        do {
            try place((from as NSString).appendingPathComponent("bin/sherpa-onnx-offline-tts"),
                      at: binary)
            try place((from as NSString).appendingPathComponent("lib/libonnxruntime.dylib"),
                      at: path("lib/libonnxruntime.dylib"))
        } catch {
            return .failed("Could not install the speech engine: \(error.localizedDescription)")
        }
        return nil
    }

    private static func unpack(_ voice: Voice, from file: URL) -> Trouble? {
        let staging = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("squawk-voice-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: staging) }
        if let trouble = extract(file, into: staging) { return trouble }
        let from = (staging as NSString).appendingPathComponent(voice.folder)
        do {
            try place("\(from)/\(voice.id).onnx", at: model(voice))
            try place("\(from)/\(voice.id).onnx.json", at: "\(voiceFolder(voice))/\(voice.id).onnx.json")
            try place("\(from)/tokens.txt", at: tokens(voice))
            // Every voice carries the same eighteen megabytes of phonemes, so
            // the first one to arrive keeps them and the rest share.
            if !exists(phonemes) { try place("\(from)/espeak-ng-data", at: phonemes) }
        } catch {
            return .failed("Could not install \(voice.title): \(error.localizedDescription)")
        }
        return nil
    }

    private static func place(_ source: String, at destination: String) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source) else {
            throw NSError(domain: "squawk.voice", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "\((source as NSString).lastPathComponent) was missing",
            ])
        }
        try manager.createDirectory(
            atPath: (destination as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true, attributes: nil)
        if manager.fileExists(atPath: destination) {
            try manager.removeItem(atPath: destination)
        }
        try manager.moveItem(atPath: source, toPath: destination)
    }

    private static func extract(_ file: URL, into directory: String) -> Trouble? {
        do {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return .failed(error.localizedDescription)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        task.arguments = ["xjf", file.path, "-C", directory]
        // An unread pipe deadlocks the child once it fills the buffer.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return .failed("Could not unpack the download: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            return .failed("Unpacking the download failed.")
        }
        return nil
    }
}
