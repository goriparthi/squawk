import Foundation

/// Handing the briefing to a model on the machine to say more naturally, and
/// refusing what comes back when it is not what was asked for.
///
/// The model only rephrases. It never decides anything, never sees a command it
/// was not given, and anything it returns that drops or renames what it was
/// told is thrown away for the plain sentence instead. A wrong word in a
/// summary about approving commands is worse than a stiff one.
public enum Phrasing {
    /// Said aloud, so length is time. Past this it stops being a summary.
    public static let maxLength = 240

    public static let instruction = """
        You rephrase a short status report that a small desk robot says out loud.
        Reply with one or two short spoken sentences and nothing else.
        Use only the facts given. Never add advice, greetings, questions, \
        markdown, quotes or names that are not in the facts.
        Keep every project name exactly as written.
        """

    /// The facts, as lines rather than JSON: a small model follows plain text
    /// more reliably, and there is nothing here worth a schema.
    public static func facts(_ briefing: Briefing) -> String {
        guard briefing.waiting > 0 else { return "Nothing is waiting." }
        var lines = ["\(briefing.waiting) waiting, \(briefing.decisions) needing a decision."]
        for item in briefing.items.prefix(Utterance.namedLimit) {
            var line = "project \(item.project)"
            if item.awaitsDecision {
                line += ", tool \(item.tool), command \(Utterance.trimmed(item.summary))"
                if item.risky { line += ", risky" }
            } else {
                line += ", wants attention, no decision needed"
            }
            lines.append(line)
        }
        if briefing.waiting > Utterance.namedLimit {
            lines.append("and \(briefing.waiting - Utterance.namedLimit) more not described")
        }
        return lines.joined(separator: "\n")
    }

    /// What the model said, if it can be trusted, else nil. Everything here is
    /// a way of catching it having invented, dropped or decorated something.
    public static func accept(_ candidate: String, for briefing: Briefing) -> String? {
        let text = tidied(candidate)
        guard !text.isEmpty, text.count <= maxLength else { return nil }
        // Reasoning, formatting and links are all signs it answered something
        // other than the question.
        let banned = ["<think", "```", "http", "*", "#", "[", "{"]
        guard !banned.contains(where: text.contains) else { return nil }
        // Every project it was told about has to survive, spelled the same.
        let spoken = text.lowercased()
        for item in briefing.items.prefix(Utterance.namedLimit) {
            guard spoken.contains(item.project.lowercased()) else { return nil }
        }
        // And the count has to be there, as a word or a figure, or it is a
        // summary that has quietly lost the number you needed.
        guard mentionsCount(briefing.waiting, in: spoken) else { return nil }
        // Risk is the one thing this app exists to put in front of you. A
        // rephrasing that reads more nicely by dropping it is worse than the
        // stiff sentence, and a model did exactly that on the second try.
        let named = briefing.items.prefix(Utterance.namedLimit)
        if named.contains(where: \.risky), !mentionsRisk(in: spoken) { return nil }
        return text
    }

    static let riskWords = ["risky", "risk", "danger", "careful", "caution", "watch out"]

    private static func mentionsRisk(in text: String) -> Bool {
        riskWords.contains(where: text.contains)
    }

    private static func mentionsCount(_ number: Int, in text: String) -> Bool {
        if number == 0 {
            return ["nothing", "no ", "none", "nobody", "empty", "clear"]
                .contains(where: text.contains)
        }
        return text.contains("\(number)") || text.contains(Utterance.count(number))
    }

    /// One paragraph, no wrapping quotes, no trailing label. Models like to
    /// return their answer in quotation marks, which is not a reason to bin it.
    public static func tidied(_ candidate: String) -> String {
        var text = candidate
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, let last = text.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'"),
              text.count > 1 {
            text = String(text.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Collapse the double spaces the newline swap leaves behind.
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text
    }
}
