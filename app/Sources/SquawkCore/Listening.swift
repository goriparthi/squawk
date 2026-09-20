import Foundation

/// What was said to the pet. Speech arrives as a bare lowercase run of words
/// with no punctuation and the occasional wrong one, so everything here matches
/// on the words someone would actually say rather than on exact phrases.
public enum Intent: Equatable, Sendable {
    case status
    /// The rest of what was said, for picking out which session is meant.
    case approve(String)
    case deny(String)
    case open(String)
    case yes
    case no
    case quiet
    /// A question for it to answer, rather than an instruction about an agent.
    case ask(String)
    case unknown
}

public enum Listening {
    /// What it answers to. The persona's own name, and the app's, because
    /// people use both and neither is worth being pedantic about.
    public static func wakeWords(persona: String) -> [String] {
        [persona.lowercased(), "squawk", "squark", "squak"]
    }

    /// The words after its name, or nil when its name was not said. Matched
    /// anywhere in the run, because a recogniser hands back a rolling
    /// transcript and the name may sit well inside it.
    ///
    /// The **earliest** mention, not the latest, because the app's own name is
    /// also the name of a project people work in: "squawk, open squawk" has to
    /// keep the second one as the thing being asked for. Taking the last match
    /// left nothing after it, and every command naming this repo did nothing.
    public static func afterWake(_ transcript: String, wakeWords: [String]) -> String? {
        let spoken = normalise(transcript)
        var earliest: Range<String.Index>?
        for word in wakeWords {
            guard let range = spoken.range(of: word) else { continue }
            if earliest == nil || range.lowerBound < earliest!.lowerBound { earliest = range }
        }
        guard let earliest else { return nil }
        return String(spoken[earliest.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// Everything is judged on the words present, in this order, because
    /// "no, deny that" is a denial and not a "no" to some earlier question.
    public static func heard(_ transcript: String) -> Intent {
        let spoken = normalise(transcript)
        guard !spoken.isEmpty else { return .unknown }

        if contains(spoken, ["be quiet", "shut up", "stop talking", "quiet", "never mind",
                             "nevermind", "forget it"]) {
            return .quiet
        }
        if let rest = after(spoken, ["deny", "reject", "refuse", "block", "turn it down"]) {
            return .deny(rest)
        }
        if let rest = after(spoken, ["approve", "allow", "let it", "go ahead", "permit"]) {
            return .approve(rest)
        }
        if let rest = after(spoken, ["open", "show me", "show", "switch to", "take me to",
                                     "go to", "jump to"]) {
            return .open(rest)
        }
        if contains(spoken, ["waiting", "status", "what's going on", "whats going on",
                             "what is going on", "anything", "what have you got",
                             "how are we", "report"]) {
            return .status
        }
        // Bare agreement, only once nothing else has claimed it.
        if contains(spoken, ["yes", "yeah", "yep", "yup", "correct", "confirm", "do it",
                             "that's right", "thats right", "affirmative"]) {
            return .yes
        }
        if contains(spoken, ["no", "nope", "cancel", "don't", "dont", "do not", "stop"]) {
            return .no
        }
        // Anything else said to it deliberately is a question for it, as long
        // as it is a sentence: two words near a pet is someone else's talk.
        return Answers.isWorthAnswering(spoken) ? .ask(spoken) : .unknown
    }

    /// How much of a running transcript is worth reading. A continuous session
    /// keeps everything said near the machine in one growing string, and after
    /// a few minutes of conversation the name may sit thousands of characters
    /// back with an entire meeting after it. A command is a handful of words.
    public static let tailLimit = 160

    /// One transcript, turned into the thing to act on, or nothing.
    ///
    /// This is the whole of the decision the app used to make inline, which is
    /// where the one real bug lived: acting on a partial transcript fires
    /// "approve" against whatever is selected before "squawk" has been heard.
    ///
    /// - Parameters:
    ///   - requiresWake: false while a key is held, because holding it is
    ///     already having said the name.
    public static func command(from transcript: String, final: Bool,
                               wakeWords: [String], requiresWake: Bool) -> Intent? {
        let recent = String(transcript.suffix(tailLimit))
        let spoken = requiresWake ? afterWake(recent, wakeWords: wakeWords) : recent
        guard let spoken, !spoken.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let intent = heard(spoken)
        guard intent != .unknown else { return nil }
        // A decision waits for the end of the sentence; looking and listening
        // may act the moment they are understood.
        return final || !needsWholeSentence(intent) ? intent : nil
    }

    /// One transcript heard *while the pet is talking*.
    ///
    /// The ears stay open through an utterance so you can cut it off, which is
    /// the only way to stop a long answer without reaching for the keyboard.
    /// But an open microphone during speech is a microphone that may be hearing
    /// the pet, the room, or a colleague, so exactly one thing may come of it:
    /// stopping. Nothing said over the top of it can approve, deny, open a pane
    /// or ask a question.
    ///
    /// Acted on from a partial, deliberately. Waiting for the end of the
    /// sentence to honour "stop" means it has already finished saying the thing
    /// you were interrupting.
    public static func interruption(from transcript: String,
                                    wakeWords: [String]) -> Intent? {
        let recent = String(transcript.suffix(tailLimit))
        // Its name is optional here. Telling something to shut up while it is
        // talking at you does not want a form of address first, and the only
        // thing that can happen is silence.
        let spoken = afterWake(recent, wakeWords: wakeWords) ?? recent
        guard heard(spoken) == .quiet else { return nil }
        return .quiet
    }

    /// Whether this must wait for the end of the sentence. A decision, because
    /// acting early answers the wrong request; a question, because half a
    /// question is a different question.
    public static func needsWholeSentence(_ intent: Intent) -> Bool {
        switch intent {
        case .approve, .deny, .yes, .ask: true
        default: false
        }
    }

    /// Which of the projects on offer was meant. Everything that matches, so a
    /// caller can tell "the only one" from "either of these two" and refuse to
    /// guess between them.
    public static func match(_ spoken: String, against projects: [String]) -> [String] {
        let said = normalise(spoken)
        guard !said.isEmpty else { return [] }
        let words = said.split(separator: " ").map(String.init).filter { $0.count > 1 }
        return projects.filter { project in
            let plain = flattened(project)
            if said.contains(plain) { return true }
            // "collect db" for collect_db, and "ballot" for ballottrax.
            return words.contains { word in
                let flat = flattened(word)
                return flat.count > 2 && (plain.contains(flat) || flat.contains(plain))
            }
        }
    }

    /// Punctuation and case carry no meaning in a transcript, and separators
    /// inside a project name are never spoken.
    public static func normalise(_ text: String) -> String {
        let kept = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "'" ? character : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    private static func flattened(_ text: String) -> String {
        normalise(text).replacingOccurrences(of: " ", with: "")
    }

    private static func contains(_ spoken: String, _ phrases: [String]) -> Bool {
        phrases.contains { phrase in
            spoken == phrase || spoken.hasPrefix(phrase + " ")
                || spoken.hasSuffix(" " + phrase) || spoken.contains(" " + phrase + " ")
        }
    }

    /// Whatever followed the first of these words, which is where a target lives.
    private static func after(_ spoken: String, _ verbs: [String]) -> String? {
        for verb in verbs {
            guard spoken == verb || spoken.hasPrefix(verb + " ")
                    || spoken.contains(" " + verb + " ") || spoken.hasSuffix(" " + verb)
            else { continue }
            guard let range = spoken.range(of: verb) else { continue }
            return String(spoken[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
