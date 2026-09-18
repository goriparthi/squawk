// Update check against the GitHub releases API, from the menu or once a day when
// the user opts in. Squawk otherwise makes no network calls at all.
import Foundation
import SquawkCore

enum Updates {
    /// Baked in so the source and the releases are reachable from the app itself,
    /// not only from wherever someone found the download.
    static let repoURL = URL(string: "https://github.com/goriparthi/squawk")!
    static let issuesURL = URL(string: "https://github.com/goriparthi/squawk/issues")!
    static let homepageURL = URL(string: "https://goriparthi.github.io/squawk/")!
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

/// The user's choices, kept in UserDefaults because losing them is harmless.
enum Settings {
    private static let dailyKey = "checkForUpdatesDaily"
    private static let opacityKey = "dialOpacity"

    static var checksDaily: Bool {
        get { UserDefaults.standard.bool(forKey: dailyKey) }
        set { UserDefaults.standard.set(newValue, forKey: dailyKey) }
    }

    static let opacityRange = DialOpacity.range

    static var opacity: Double {
        get {
            guard UserDefaults.standard.object(forKey: opacityKey) != nil
            else { return DialOpacity.default }
            return DialOpacity.clamp(UserDefaults.standard.double(forKey: opacityKey))
        }
        set { UserDefaults.standard.set(DialOpacity.clamp(newValue), forKey: opacityKey) }
    }
}
