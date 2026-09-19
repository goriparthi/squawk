import Foundation

/// Working out what a question is *about*, so it can be looked up before it is
/// answered. Pure, because this is where the whole thing quietly broke once:
/// ungrounded and told to admit ignorance, a small model answered "who wrote
/// Dracula" with "I have no information about that".
public enum Question {
    /// The thing being asked about, when the question names one.
    ///
    /// Worth casting wide. Grounded, a small model answers "who wrote Dracula"
    /// with Bram Stoker; ungrounded, and told to admit what it does not know,
    /// it says it has no information and is useless.
    public static func subject(of question: String) -> String? {
        let asked = Listening.normalise(question)
        // Openings that name a thing directly.
        let direct = ["who is", "who was", "what is", "what was", "what are",
                      "tell me about", "who are", "what's a", "what is a",
                      "where is", "where was", "when is", "when was", "how big is",
                      "how old is", "how tall is"]
        for opening in direct where asked.hasPrefix(opening + " ") {
            return trimmed(String(asked.dropFirst(opening.count + 1)))
        }
        // "who wrote dracula", "who invented the telephone": the thing is what
        // follows the verb, and the article in front of it is not part of it.
        let verbs = ["who wrote", "who invented", "who created", "who founded",
                     "who directed", "who painted", "who discovered", "who built",
                     "who plays", "who played", "who won"]
        for verb in verbs where asked.hasPrefix(verb + " ") {
            return trimmed(String(asked.dropFirst(verb.count + 1)))
        }
        return nil
    }

    /// The bare thing, without the article, and only when it is short enough to
    /// be a name rather than a sentence.
    static func trimmed(_ rest: String) -> String? {
        var subject = rest
        for article in ["the ", "a ", "an "] where subject.hasPrefix(article) {
            subject = String(subject.dropFirst(article.count))
        }
        // "what is the weather" is not a thing to look up, and neither is a
        // question with only a pronoun left in it.
        guard subject.split(separator: " ").count <= 6, subject.count > 2 else { return nil }
        return subject
    }

}
