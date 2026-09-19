import Foundation

/// Turning a command into something a synthesiser can read.
///
/// The words Squawk says most are the ones every text to speech engine is
/// worst at: `psql`, `kubectl`, `chmod`, `-rf`. Read as written they come out
/// as noise, and the one time you need to hear a command clearly is the moment
/// you are deciding whether to allow it.
public enum Speakable {
    /// Said the way people say them, not the way they are typed. Only whole
    /// words are replaced, so a path containing one of these is left alone.
    /// Nothing here may map a word to itself: that changes nothing but the
    /// capitalisation, and "Bash" came back as "bash" in the bubble's own words.
    public static let saidAs: [String: String] = [
        "psql": "p s q l",
        "kubectl": "kube control",
        "npm": "n p m",
        "npx": "n p x",
        "chmod": "ch mod",
        "chown": "ch own",
        "ssh": "s s h",
        "scp": "s c p",
        "zsh": "z shell",
        "sudo": "sue doo",
        "jq": "j q",
        "cwd": "current directory",
        "tty": "t t y",
        "sql": "s q l",
        "json": "jason",
        "yaml": "yamel",
        "env": "e n v",
        "src": "source",
        "cli": "c l i",
        "api": "a p i",
        "url": "u r l",
        "uuid": "u u i d",
        "regex": "reg ex",
        "async": "a sync",
        "nginx": "engine x",
        "sqlite": "s q lite",
        "xcode": "x code",
        "macos": "mac o s",
        "ios": "i o s",
        "rf": "r f",
        "rm": "r m",
        "ls": "l s",
        "cd": "c d",
        "mv": "m v",
        "cp": "c p",
    ]

    /// Flags read as letters: "-rf" is "dash r f", not "erf".
    static let flag = try! NSRegularExpression(pattern: "(?<![\\w-])--?([A-Za-z]{1,4})(?![\\w-])")

    public static func spoken(_ text: String) -> String {
        var said = expandFlags(text)
        // Word by word, so `psql` is replaced and `psqlrc` is not.
        said = said.split(separator: " ", omittingEmptySubsequences: false)
            .map { piece -> String in
                let bare = piece.lowercased().trimmingCharacters(in: .punctuationCharacters)
                guard let plain = saidAs[bare] else { return String(piece) }
                // Whatever punctuation it carried stays, so a sentence still
                // has its full stops.
                let tail = piece.hasSuffix(".") || piece.hasSuffix(",") || piece.hasSuffix(":")
                    ? String(piece.suffix(1)) : ""
                return plain + tail
            }
            .joined(separator: " ")
        return said
    }

    /// "-rf" becomes "dash r f", which is how anyone reads a flag aloud.
    static func expandFlags(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var out = text
        for match in flag.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: text),
                  let letters = Range(match.range(at: 1), in: text)
            else { continue }
            let dashes = text[whole].prefix(while: { $0 == "-" }).count
            let spelled = text[letters].map { String($0) }.joined(separator: " ")
            out.replaceSubrange(whole, with: (dashes == 2 ? "dash dash " : "dash ") + spelled)
        }
        return out
    }
}
