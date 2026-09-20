// Update check against the GitHub releases API, from the menu or once a day when
// the user opts in. Squawk otherwise makes no network calls at all.
import Foundation
import SquawkCore

enum Updates {
    /// Baked in so the source and the releases are reachable from the app itself,
    /// not only from wherever someone found the download.
    static let repoURL = URL(string: "https://github.com/goriparthi/squawk")!
    static let siteURL = URL(string: "https://goriparthi.github.io/squawk/")!
    static let latestReleaseURL = URL(string:
        "https://api.github.com/repos/goriparthi/squawk/releases/latest")!

    enum Outcome {
        case upToDate(String)
        case available(version: String, page: URL, asset: URL?)
        case failed(String)
    }

    static var bundleVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static func check(
        currentVersion: String = bundleVersion,
        completion: @escaping @Sendable (Outcome) -> Void
    ) {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failed("Update check failed: \(error.localizedDescription)"))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, (200..<300).contains(status) else {
                // An unauthenticated request to a repo with no releases answers 404.
                completion(.failed(status == 404
                    ? "No published releases yet"
                    : "Update check failed (HTTP \(status))"))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else {
                completion(.failed("Could not read the release feed"))
                return
            }

            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? repoURL
            let assets = json["assets"] as? [[String: Any]] ?? []
            let asset = assets
                .first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))

            UpdateSchedule.recordCheck()
            if Version.isNewer(tag, than: currentVersion) {
                completion(.available(version: tag, page: page, asset: asset))
            } else {
                completion(.upToDate(currentVersion))
            }
        }.resume()
    }
}

/// The user's choices, kept in ~/.squawk/config.json so they can be read and
/// edited without a defaults command. Migrated once from the old defaults
/// domain, which is then cleared so there is only ever one source of truth.
@MainActor
enum Settings {
    private static var config = ConfigFile.load()

    static func reload() {
        config = ConfigFile.load()
        behaviour = BehaviourRules.load()
    }

    /// What the local model is told, from a file the app re-reads rather than
    /// compiled in. Held here so a call site asks once rather than reading the
    /// disk in the middle of building a prompt.
    private(set) static var behaviour = BehaviourRules.load()

    /// Re-read, for the watcher. Cheap: a small file, and only on a change.
    static func reloadBehaviour() { behaviour = BehaviourRules.load() }

    private static func mutate(_ change: (inout SquawkConfig) -> Void) {
        change(&config)
        ConfigFile.save(config)
    }

    static var configPath: String { ConfigFile.path() }

    static var checksForUpdates: Bool {
        get { config.checkForUpdates }
        set { mutate { $0.checkForUpdates = newValue } }
    }

    static var checkTimes: [DayTime] { config.checkTimes }

    /// What the user asked for. `LoginItem` reports what macOS actually did,
    /// which is not always the same; this is the intent, recorded so the file
    /// describes the whole configuration.
    static var opensAtLogin: Bool {
        get { config.openAtLogin }
        set { mutate { $0.openAtLogin = newValue } }
    }

    static var alwaysVisible: Bool {
        get { config.alwaysShowDial }
        set { mutate { $0.alwaysShowDial = newValue } }
    }

    static let opacityRange = DialOpacity.range

    static var opacity: Double {
        get { config.clampedOpacity }
        set { mutate { $0.dialOpacity = DialOpacity.clamp(newValue) } }
    }

    static var persona: Persona {
        get { config.persona }
        set { mutate { $0.character = newValue.id } }
    }

    static var reactsToAudio: Bool {
        get { config.reactsToAudio }
        set { mutate { $0.reactsToAudio = newValue } }
    }

    static var wellness: Bool {
        get { config.wellness }
        set { mutate { $0.wellness = newValue } }
    }

    static var bubbleBelow: Bool {
        get { config.bubbleBelow }
        set { mutate { $0.bubbleBelow = newValue } }
    }

    static var speaksAloud: Bool {
        get { config.speaksAloud }
        set { mutate { $0.speaksAloud = newValue } }
    }

    static var voiceId: String {
        get { config.voiceId }
        set { mutate { $0.voiceId = newValue } }
    }

    static var phrasesWithModel: Bool {
        get { config.phrasesWithModel }
        set { mutate { $0.phrasesWithModel = newValue } }
    }

    static var phrasingModel: String {
        get { config.phrasingModel }
        set { mutate { $0.phrasingModel = newValue } }
    }

    static var listensForWakeWord: Bool {
        get { config.listensForWakeWord }
        set { mutate { $0.listensForWakeWord = newValue } }
    }

    static var pushToTalk: Bool {
        get { config.pushToTalk }
        set { mutate { $0.pushToTalk = newValue } }
    }

    static var logsListening: Bool {
        get { config.logsListening }
        set { mutate { $0.logsListening = newValue } }
    }

    static var answersQuestions: Bool {
        get { config.answersQuestions }
        set { mutate { $0.answersQuestions = newValue } }
    }

    static var weatherPlace: String { config.weatherPlace }

    static var makesSounds: Bool {
        get { config.makesSounds }
        set { mutate { $0.makesSounds = newValue } }
    }

    static var agentsMaySpeak: Bool {
        get { config.agentsMaySpeak }
        set { mutate { $0.agentsMaySpeak = newValue } }
    }

    static var lastGreeting: String {
        get { config.lastGreeting }
        set { mutate { $0.lastGreeting = newValue } }
    }

    static var breakReminderMinutes: Int {
        get { config.breakReminderMinutes }
        set { mutate { $0.breakReminderMinutes = max(0, newValue) } }
    }

    static var diameter: CGFloat {
        get { config.clampedDiameter }
        set { mutate { $0.dialDiameter = Double(DialGeometry.clamp(newValue)) } }
    }

    /// Carries settings over from the defaults domain the first time, so an
    /// existing install does not silently reset to defaults.
    static func migrateFromDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let keys = ["checkForUpdatesDaily", "dialOpacity", "dialDiameter",
                    "alwaysShowDial", "dialSize"]
        guard !FileManager.default.fileExists(atPath: ConfigFile.path()),
              keys.contains(where: { defaults.object(forKey: $0) != nil })
        else { return }

        var carried = SquawkConfig()
        carried.checkForUpdates = defaults.bool(forKey: "checkForUpdatesDaily")
        carried.alwaysShowDial = defaults.bool(forKey: "alwaysShowDial")
        if defaults.object(forKey: "dialOpacity") != nil {
            carried.dialOpacity = DialOpacity.clamp(defaults.double(forKey: "dialOpacity"))
        }
        if defaults.object(forKey: "dialDiameter") != nil {
            carried.dialDiameter = Double(DialGeometry.clamp(CGFloat(defaults.double(forKey: "dialDiameter"))))
        } else if let legacy = defaults.string(forKey: "dialSize") {
            carried.dialDiameter = Double(DialSize.named(legacy).diameter)
        }
        carried.openAtLogin = LoginItem.isEnabled

        ConfigFile.save(carried)
        config = carried
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
