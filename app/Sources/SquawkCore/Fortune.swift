import Foundation

/// Fortunes for the tummy rub. Bundled rather than fetched: a companion that
/// needs the network to be charming is not charming.
public enum Fortune {
    public static let all: [String] = [
        "The bug you are chasing is one line above where you are looking.",
        "A branch left unmerged grows heavier every day.",
        "Today is a good day to delete something.",
        "The test you skip is the one that would have caught it.",
        "Someone will thank you for a comment you almost did not write.",
        "You will find the answer shortly after you stop looking for it.",
        "The simplest fix is usually the one you rejected first.",
        "Rest is not a reward for finishing. It is part of finishing.",
        "A short review today saves a long weekend later.",
        "What you name it is what it will become.",
        "The second attempt is where the good version lives.",
        "Read the error message. All of it.",
        "Your future self is the user you keep forgetting about.",
        "Nothing is as permanent as a temporary workaround.",
        "The code you are proudest of will be deleted, and that is fine.",
        "If it is hard to test, it is probably hard to use.",
        "Ship the small thing. The big thing never arrives.",
        "A good question is worth more than a confident answer.",
        "Someone is waiting on you for something tiny. Go and unblock them.",
        "The log line you add today pays for itself at 2am.",
        "Trust the failing test over the working theory.",
        "You are further along than you think.",
        "Write it down. Memory is not a storage layer.",
        "The meeting could have been a message, and the message could have been a link.",
        "Fix the thing that annoys you every day. It is not a distraction.",
        "Clever code is a debt with interest.",
        "The hardest part is deciding what not to build.",
        "Look away from the screen for a minute. It will still be there.",
        "A rollback is a plan, not a failure.",
        "Small commits make brave engineers.",
        "The problem is almost never where the stack trace points first.",
        "You cannot refactor your way out of an unclear requirement.",
        "Say no to one thing today so you can finish another.",
        "Old code is not bad code. It is code that survived.",
        "If you are not sure it works, it does not work.",
        "The next person to read this will be you, on a worse day.",
        "Good fences make good interfaces.",
        "Measure before you optimise, or you are just decorating.",
        "A quiet system is not always a healthy one.",
        "Every dependency is a promise someone else has to keep.",
        "Done is a state you have to defend.",
        "The right abstraction shows up on the third use, not the first.",
    ]

    /// Never the same one twice running, which is what makes it feel like it
    /// picked rather than cycled.
    public static func next(
        after previous: String?,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let pool = all.filter { $0 != previous }
        guard let pick = pool.randomElement(using: &generator) else { return all[0] }
        return pick
    }

    public static func next(after previous: String?) -> String {
        var generator = SystemRandomNumberGenerator()
        return next(after: previous, using: &generator)
    }
}
