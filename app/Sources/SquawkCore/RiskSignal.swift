import Foundation

/// Whether a pending command looks like one you would want to read twice.
/// Deliberately crude and deliberately not a security control: it decides how
/// the dial looks, never what is allowed. Anything it misses is still a prompt.
public enum RiskSignal {
    /// Matched against the summary, lowercased, whitespace collapsed.
    static let patterns: [String] = [
        "rm -rf", "rm -fr", "sudo rm",
        "git push --force", "git push -f", "git reset --hard", "git clean -fd",
        "drop table", "drop database", "truncate table", "delete from",
        "mkfs", "diskutil erase", "dd if=", "dd of=",
        "chmod 777", "chown -r",

        "kubectl delete", "terraform destroy", "aws s3 rb", "--force-with-lease",
    ]

    /// Production is not destructive by itself, but it is worth a second look.
    static let environments: [String] = ["prod", "production"]

    /// Shells named as the target of a pipe. Matched on the segment rather than
    /// as a substring, so `grep | shuf` is not mistaken for `curl x | sh`.
    static let shells: Set<String> = ["sh", "bash", "zsh", "fish"]

    static func pipesIntoAShell(_ text: String) -> Bool {
        text.split(separator: "|").dropFirst().contains { segment in
            guard let word = segment.split(whereSeparator: \.isWhitespace).first
            else { return false }
            return shells.contains(String(word))
        }
    }

    public static func isRisky(tool: String, summary: String) -> Bool {
        let text = summary.lowercased()
        if patterns.contains(where: text.contains) { return true }
        if pipesIntoAShell(text) { return true }
        // A prod marker only counts alongside something that changes state.
        guard environments.contains(where: text.contains) else { return false }
        return ["delete", "drop", "restart", "deploy", "apply", "destroy", "rm "]
            .contains(where: text.contains)
    }
}
