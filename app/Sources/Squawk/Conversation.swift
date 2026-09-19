import Foundation
import SquawkCore

/// Looking something up, so an answer about a real thing comes from a record of
/// it rather than from what a three billion parameter model half remembers.
enum Lookup {
    /// What the question is about, looked up: the named thing if the question
    /// named one, otherwise the best article the question itself finds. Either
    /// way the article has to be about what was asked, or it is dropped.
    static func grounding(for question: String, completion: @escaping @Sendable (String?) -> Void) {
        if let subject = Question.subject(of: question) {
            summary(for: subject) { found in
                if let found { return completion(found) }
                // Named but not under that exact title: "ada lovelace" is an
                // article, "the royal society" is a redirect nobody guessed.
                search(question, orSubject: subject, completion: completion)
            }
            return
        }
        search(question, orSubject: nil, completion: completion)
    }

    /// Wikipedia's own search, used only when the title guess missed. Its
    /// ranking is poor for a plain question, so what it returns is checked
    /// against the question before any of it is believed.
    private static func search(_ question: String, orSubject subject: String?,
                               completion: @escaping @Sendable (String?) -> Void) {
        let terms = subject ?? question
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: terms),
            URLQueryItem(name: "srlimit", value: "3"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return completion(nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Squawk desk companion (github.com/goriparthi/squawk)",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = payload["query"] as? [String: Any],
                  let hits = query["search"] as? [[String: Any]]
            else { return completion(nil) }
            let titles = hits.compactMap { $0["title"] as? String }
            // Grounding on an article about something else is worse than none:
            // the model answers confidently about the wrong thing.
            guard let best = titles.first(where: { Question.isRelevant(title: $0, to: question) })
            else { return completion(nil) }
            summary(for: best, completion: completion)
        }.resume()
    }

    /// A short encyclopaedia summary, or nothing. Wikipedia only: it is free,
    /// needs no key, says where its words came from, and is a reasonable thing
    /// for a desk toy to read aloud from.
    static func summary(for subject: String, completion: @escaping @Sendable (String?) -> Void) {
        let title = subject.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "_")
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else { return completion(nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Squawk desk companion (github.com/goriparthi/squawk)",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let extract = payload["extract"] as? String, !extract.isEmpty,
                  (payload["type"] as? String) != "disambiguation"
            else { return completion(nil) }
            completion(String(extract.prefix(700)))
        }.resume()
    }
}

/// Talking to it. A short memory, so "and tomorrow?" means something, and a
/// model on this machine doing the talking.
///
/// This is the one part of Squawk that is allowed to make something up, and it
/// is kept away from everything that answers for your agents. Anything with a
/// right answer, the clock above all, is computed before this is reached.
@MainActor
final class Conversation {
    /// Turns kept. Enough for a follow up, short enough that a small model is
    /// not carrying a transcript it cannot use.
    static let remembered = 6
    /// Longer than the phrasing deadline: someone has asked a question and is
    /// waiting for the answer, rather than waiting for a status line to be
    /// tidied up.
    static let deadline: TimeInterval = 10

    private var history: [[String: String]] = []

    func clear() { history.removeAll() }

    func ask(_ question: String, model: String, situation: String? = nil,
             completion: @escaping @Sendable (String?) -> Void) {
        let turns = history
        Lookup.grounding(for: question) { [weak self] extract in
            Task { @MainActor in
                self?.send(question, model: model, turns: turns, grounding: extract,
                           situation: situation, completion: completion)
            }
        }
    }

    private func send(_ question: String, model: String, turns: [[String: String]],
                      grounding: String?, situation: String?,
                      completion: @escaping @Sendable (String?) -> Void) {
        var messages: [[String: String]] = [["role": "system", "content": Self.instruction]]
        // What is true right now, which is the one thing this assistant knows
        // that no other one does: their agents, their day, their desk.
        if let situation {
            messages.append(["role": "system", "content": situation])
        }
        if let grounding {
            messages.append([
                "role": "system",
                "content": "Use this, which is from Wikipedia and is more reliable than your "
                    + "own memory:\n\(grounding)",
            ])
        }
        messages += turns
        messages.append(["role": "user", "content": question])

        var request = URLRequest(url: Ollama.base.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.deadline
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "options": ["temperature": 0.6, "num_predict": 120, "num_ctx": 4096],
            "messages": messages,
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
            let answer = Phrasing.tidied(text)
            guard !answer.isEmpty, !answer.contains("<think") else { return completion(nil) }
            Task { @MainActor in
                // Remembered only once it has actually answered.
                completion(String(answer.prefix(400)))
            }
        }.resume()
    }

    /// Records a finished exchange, so a follow up has something to follow.
    func remember(question: String, answer: String) {
        history.append(["role": "user", "content": question])
        history.append(["role": "assistant", "content": answer])
        if history.count > Self.remembered * 2 {
            history.removeFirst(history.count - Self.remembered * 2)
        }
    }

    static let instruction = """
        You are a small robot that sits on someone's desk, watching the coding agents \
        they run and asking them to approve what those agents want to do. You are answering \
        out loud, so reply in one or two short spoken sentences and never with lists, \
        markdown or code.
        You may be told what is true right now. When they ask about themselves, their \
        day, their agents, what they have approved or what they have been working on, \
        answer from those facts and name the projects in them. Ignore them otherwise.
        Answer ordinary questions about the world from what you know, in the same short way.
        Say you do not know only when you really do not, or when it is something you could \
        not know, such as today's news or what is on their screen. Never refuse a question \
        you can answer.
        """
}
