import Foundation
import SquawkCore

/// Asking a model already running on this machine to say the briefing more
/// naturally. Entirely optional: Squawk pulls nothing, installs nothing, and
/// speaks the plain sentence whenever this is off, absent, slow or wrong.
///
/// Only models on the machine are used. The briefing says what your agents are
/// about to run, so it does not go to a server: anything whose name marks it as
/// cloud hosted is filtered out even when Ollama offers it.
enum Ollama {
    static let base = URL(string: "http://localhost:11434")!

    /// Small instruct models that answer with the sentence asked for. Measured
    /// rather than guessed: reasoning models (qwen3 among them) narrate their
    /// working into the reply whatever they are told, and every one of those
    /// replies is thrown away by `Phrasing.accept`.
    /// Order is preference, measured rather than assumed. The seven billion
    /// instruct models answer questions about the journal noticeably better
    /// than the three billion ones and still come back inside two seconds;
    /// the small ones are kept as the cheap option for a smaller Mac.
    static let preferred = ["qwen2.5:7b-instruct", "qwen2.5:7b", "llama3.1:8b",
                            "llama3.2:3b", "llama3.2", "qwen2.5:3b-instruct",
                            "qwen2.5:3b", "gemma3:4b", "phi4-mini", "mistral:7b"]

    /// What to pull when there is nothing suitable, named in the menu.
    static let suggested = "qwen2.5:7b-instruct"

    /// Long enough for a warm model, short enough that nobody waits on it. A
    /// cold model takes far longer than this and simply loses to the template.
    static let deadline: TimeInterval = 2.5

    /// Models on this machine, best first, cloud ones dropped.
    static func local(completion: @escaping @Sendable ([String]) -> Void) {
        var request = URLRequest(url: base.appending(path: "api/tags"))
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = payload["models"] as? [[String: Any]]
            else { return completion([]) }
            let names = models.compactMap { $0["name"] as? String }
                .filter { !$0.hasSuffix(":cloud") }
            let ranked = names.sorted { left, right in
                (preferred.firstIndex(where: left.hasPrefix) ?? .max)
                    < (preferred.firstIndex(where: right.hasPrefix) ?? .max)
            }
            completion(ranked)
        }.resume()
    }

    /// The best installed model worth using, or nil when there is none. A
    /// model not on the list is used only when the user named it themselves.
    static func choose(from installed: [String], configured: String) -> String? {
        if !configured.isEmpty { return installed.contains(configured) ? configured : nil }
        return installed.first { name in preferred.contains(where: name.hasPrefix) }
    }

    /// Rephrases, or hands back nil and lets the plain sentence do it.
    static func phrase(_ briefing: Briefing, model: String,
                       completion: @escaping @Sendable (String?) -> Void) {
        var request = URLRequest(url: base.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = deadline
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            // Reasoning belongs nowhere near a sentence read aloud.
            "think": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 70,
                // The facts are a few lines, and a large context is what makes
                // a model load slowly and hold memory it has no use for.
                "num_ctx": 2048,
                "stop": ["\n\n"],
            ],
            "messages": messages(for: briefing),
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else {
            return completion(nil)
        }
        request.httpBody = encoded
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = payload["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { return completion(nil) }
            completion(Phrasing.accept(text, for: briefing))
        }.resume()
    }

    /// One worked example, because a small model shown the shape of the answer
    /// gives it, and told the shape of the answer explains it instead.
    private static func messages(for briefing: Briefing) -> [[String: String]] {
        [
            ["role": "system", "content": Phrasing.instruction],
            ["role": "user", "content": "1 waiting, 1 needing a decision.\nproject ballot, tool Bash, command rm -rf build, risky"],
            ["role": "assistant", "content": "One waiting. ballot wants to run rm -rf build, and that one looks risky."],
            ["role": "user", "content": Phrasing.facts(briefing)],
        ]
    }

    /// A model is slow the first time and quick afterwards, so it is woken when
    /// the setting is turned on rather than when someone is waiting to hear it.
    static func warm(_ model: String) {
        var request = URLRequest(url: base.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let body: [String: Any] = [
            "model": model, "stream": false, "think": false,
            "options": ["num_predict": 1, "num_ctx": 2048],
            "messages": [["role": "user", "content": "hi"]],
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = encoded
        URLSession.shared.dataTask(with: request).resume()
    }
}
