import Foundation

/// Lines it will certainly say, rendered before anyone asks for them, and the
/// one that warms the engine up.
///
/// The roadmap had this at two and a half seconds of dead air before any neural
/// line. Measured on 2026-09-19 across all four installed voices it is 520 to
/// 730 ms, warm, and steady: the model is 60 MB and the OS keeps it. So there
/// is no streaming problem to solve here. What is left is the *first* line
/// after a launch, which pays whatever the first run of a downloaded binary
/// costs, and that is absorbed by rendering something nobody is waiting for.
///
/// Only fixed lines belong here. A line built from a project name or a command
/// is different every time, so pre-rendering it would fill the cache with
/// entries nothing ever reads.
public enum Warmup {
    /// What it says most, in the order it is most likely to need them.
    /// Answering leads: the gap between saying "approve it" and hearing
    /// "Approved" is the one that reads as the app having missed you.
    public static let fixedLines = [
        "Approved.",
        "Denied.",
        "No!",
        "Nothing waiting.",
    ]

    /// Rendered as the synthesiser will actually be given them, or the cache
    /// key is a line that is never asked for.
    public static var lines: [String] {
        var seen = Set<String>()
        return fixedLines
            .map(Speakable.spoken)
            .filter { seen.insert($0).inserted && !$0.isEmpty }
    }
}
