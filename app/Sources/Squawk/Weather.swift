import Foundation
import SquawkCore

/// What it is like outside. Open-Meteo, which needs no key and no account, and
/// a place taken from the Mac's own time zone rather than from the location
/// service: a desk pet saying the weather does not need to know which room it
/// is in, and asking for that permission to answer "is it raining" is a poor
/// trade. Set `weatherPlace` in the config to say somewhere else.
enum Weather {
    struct Place: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    struct Report: Sendable {
        let place: String
        let now: Double
        let high: Double
        let low: Double
        let code: Int
        let unit: String
    }

    /// The city out of "America/Denver". Crude, free, and right often enough
    /// for a pet that is being asked whether to take a coat.
    static var placeFromTimeZone: String {
        let identifier = TimeZone.current.identifier
        let tail = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return tail.replacingOccurrences(of: "_", with: " ")
    }

    /// Looked up once and kept: a city does not move.
    private nonisolated(unsafe) static var known: Place?
    private nonisolated(unsafe) static var lastReport: (Report, Date)?
    private static let lock = NSLock()
    /// Weather changes slowly enough that asking twice in ten minutes is asking
    /// the same question.
    static let freshFor: TimeInterval = 10 * 60

    static func spoken(place override: String?, completion: @escaping @Sendable (String?) -> Void) {
        lock.lock()
        if let (report, when) = lastReport, Date().timeIntervalSince(when) < freshFor,
           override == nil || override == report.place {
            lock.unlock()
            return completion(describe(report))
        }
        let cached = known
        lock.unlock()

        let wanted = override ?? placeFromTimeZone
        if let cached, cached.name.caseInsensitiveCompare(wanted) == .orderedSame {
            return forecast(for: cached, completion: completion)
        }
        locate(wanted) { place in
            guard let place else { return completion(nil) }
            lock.lock(); known = place; lock.unlock()
            forecast(for: place, completion: completion)
        }
    }

    private static func locate(_ name: String, completion: @escaping @Sendable (Place?) -> Void) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        fetch(components.url) { payload in
            guard let results = payload?["results"] as? [[String: Any]], let first = results.first,
                  let latitude = first["latitude"] as? Double,
                  let longitude = first["longitude"] as? Double
            else { return completion(nil) }
            completion(Place(name: (first["name"] as? String) ?? name,
                             latitude: latitude, longitude: longitude))
        }
    }

    private static func forecast(for place: Place, completion: @escaping @Sendable (String?) -> Void) {
        // Fahrenheit where the machine's region uses it, which is the same rule
        // every other temperature on this Mac follows.
        let fahrenheit = Locale.current.measurementSystem == .us
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(place.latitude)"),
            URLQueryItem(name: "longitude", value: "\(place.longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        fetch(components.url) { payload in
            guard let payload,
                  let current = payload["current"] as? [String: Any],
                  let daily = payload["daily"] as? [String: Any],
                  let now = current["temperature_2m"] as? Double,
                  let highs = daily["temperature_2m_max"] as? [Double], let high = highs.first,
                  let lows = daily["temperature_2m_min"] as? [Double], let low = lows.first
            else { return completion(nil) }
            let report = Report(place: place.name, now: now, high: high, low: low,
                                code: (current["weather_code"] as? Int) ?? -1,
                                unit: fahrenheit ? "degrees" : "degrees")
            lock.lock(); lastReport = (report, Date()); lock.unlock()
            completion(describe(report))
        }
    }

    private static func fetch(_ url: URL?,
                              completion: @escaping @Sendable ([String: Any]?) -> Void) {
        guard let url else { return completion(nil) }
        var request = URLRequest(url: url)
        // Nobody waits longer than this for small talk about the sky.
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return completion(nil) }
            completion(payload)
        }.resume()
    }

    static func describe(_ report: Report) -> String {
        let sky = sky(report.code)
        return "\(sky) and \(Int(report.now.rounded())) \(report.unit) in \(report.place), "
            + "between \(Int(report.low.rounded())) and \(Int(report.high.rounded())) today."
    }

    /// The WMO codes Open-Meteo reports, in the words someone would use.
    static func sky(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Mostly clear"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51, 53, 55, 56, 57: "Drizzling"
        case 61, 63, 65, 66, 67, 80, 81, 82: "Raining"
        case 71, 73, 75, 77, 85, 86: "Snowing"
        case 95, 96, 99: "Thunderstorms"
        default: "Hard to say"
        }
    }
}
