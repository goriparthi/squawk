import Foundation

/// Everything the face and body are decided from. One value, so the decision
/// is a function and not the order six early returns happened to be in.
public struct MoodState: Sendable {
    public var waiting: Int
    public var awaitingDecision: Bool
    public var risky: Bool
    /// The break nudge is on.
    public var restless: Bool
    public var speech: Speech?
    public var hearingMusic: Bool
    public var lastEvent: FaceEvent?
    public var eventAge: TimeInterval
    public var idleFor: TimeInterval
    /// The full style: a modelled body that paints its own face and speaks from a bubble.
    public var modelled: Bool
    /// Something is selected on the ring, so the card has a request to show.
    public var selected: Bool
    /// The agents are churning, as `WorkPace` judges it. Nothing is waiting on
    /// you: this is work happening, not work asking.
    public var working: Bool

    public init(waiting: Int = 0, awaitingDecision: Bool = false, risky: Bool = false,
                restless: Bool = false, speech: Speech? = nil, hearingMusic: Bool = false,
                lastEvent: FaceEvent? = nil, eventAge: TimeInterval = .infinity,
                idleFor: TimeInterval = 0, modelled: Bool = true, selected: Bool = false,
                working: Bool = false) {
        self.waiting = waiting
        self.awaitingDecision = awaitingDecision
        self.risky = risky
        self.restless = restless
        self.speech = speech
        self.hearingMusic = hearingMusic
        self.lastEvent = lastEvent
        self.eventAge = eventAge
        self.idleFor = idleFor
        self.modelled = modelled
        self.selected = selected
        self.working = working
    }
}

public struct MoodDecision: Equatable, Sendable {
    public var expression: FaceExpression
    /// Whether the groove may blend over the pose.
    public var grooves: Bool
    /// The flat face; the modelled body paints its own.
    public var showsFace: Bool
    public var showsCard: Bool
    public var showsBubble: Bool
}

public enum Mood {
    /// Nudge, then speech, then music, then whatever the work and the clock say.
    public static func decide(_ state: MoodState) -> MoodDecision {
        let quiet = state.waiting == 0
        // The nudge outranks the resting face, but never anything waiting.
        if state.restless, quiet {
            return MoodDecision(expression: .restless, grooves: true,
                                showsFace: !state.modelled, showsCard: false, showsBubble: false)
        }
        if let speech = state.speech, quiet || !speech.yieldsToWork {
            return MoodDecision(expression: speech.face, grooves: !speech.holdsStill,
                                showsFace: !state.modelled, showsCard: true,
                                showsBubble: state.modelled)
        }
        // Music with nothing waiting is the one state worth being pleased about
        // on its own, once any reaction has had its second.
        let reacting = state.lastEvent != nil && state.eventAge < FaceMood.reactionDuration
        if quiet, state.hearingMusic, !reacting, state.modelled {
            return MoodDecision(expression: .grooving, grooves: true,
                                showsFace: false, showsCard: false, showsBubble: false)
        }
        let expression = FaceMood.expression(
            waiting: state.waiting, awaitingDecision: state.awaitingDecision,
            lastEvent: state.lastEvent, eventAge: state.eventAge,
            idleFor: state.idleFor, risky: state.risky, working: state.working)
        // With a body the card speaks from the bubble and the face keeps emoting.
        // Without one they share the middle, and work outranks the face.
        let showsCard = state.selected && (state.modelled || !quiet)
        return MoodDecision(expression: expression, grooves: true,
                            showsFace: !state.modelled && quiet, showsCard: showsCard,
                            showsBubble: state.modelled && showsCard)
    }
}
