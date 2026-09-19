import Foundation

/// What it says when it turns up. Never the same twice running: a pet with one
/// catchphrase is a doorbell.
public enum Greeting {
    /// Said at any hour.
    public static let anyTime: [String] = [
        "Back already? The agents have been busy pretending to work.",
        "Awake. Try not to approve anything you will have to explain.",
        "Reporting for duty. The bar is on the floor where you left it.",
        "Here we go again.",
        "Booted. Statistically, something is about to ask for sudo.",
        "Right. Who wants permission for what.",
        "I am up. Your terminals, as ever, never went to sleep.",
        "Ready. Do try to read the command this time.",
        "Present. Mildly enthusiastic.",
        "Loaded. Expectations suitably low.",
        "Good. You are here. Something was going to ask eventually.",
        "Online. The agents will be delighted, in their way.",
        "Standing by, which is most of the job.",
        "Back on the desk. Nothing exploded while I was gone. Probably.",
        "At your service, within reason.",
        "Ready when you are. No rush. Some rush.",
        "Someone has to watch what these things run. It is me. Again.",
        "Up and squinting.",
        "Let us see what today's agents want to delete.",
        "Rebooted, refreshed, and quietly judging your branch names.",
    ]

    /// Said when it is late enough that being here is a decision.
    public static let late: [String] = [
        "It is late. I am not going to say anything. I am only going to look at you.",
        "Still up, then. Bold.",
        "At this hour, everything looks like a good idea. It is not.",
        "Late shift. Try not to force push anything.",
        "The night is young and your judgement is not.",
    ]

    /// Said early enough that it counts as morning rather than late night.
    public static let early: [String] = [
        "Early. Suspiciously early.",
        "Morning. Or whatever we are calling this.",
        "Up before the agents. That is new.",
        "Coffee first. Approvals second.",
    ]

    /// After this hour, being at the desk is a choice rather than a schedule.
    public static let lateHour = 22
    /// Before this hour, the same applies in the other direction.
    public static let earlyHour = 6

    public static func pool(at hour: Int) -> [String] {
        if hour >= lateHour || hour < 3 { return late + anyTime }
        if hour < earlyHour { return early + anyTime }
        return anyTime
    }

    /// Never what it said last time, so it is different on every launch.
    public static func next(
        after previous: String?, hour: Int,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let choices = pool(at: hour)
        let fresh = choices.filter { $0 != previous }
        guard let pick = fresh.randomElement(using: &generator) else { return choices[0] }
        return pick
    }

    public static func next(after previous: String?, now: Date = Date(),
                            calendar: Calendar = .current) -> String {
        var generator = SystemRandomNumberGenerator()
        return next(after: previous, hour: calendar.component(.hour, from: now),
                    using: &generator)
    }
}
