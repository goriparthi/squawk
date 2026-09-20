import XCTest
@testable import SquawkCore

final class WorkPaceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Feeds a run of readings and gives back what it decided at the end.
    private func run(_ readings: [Int], from pace: WorkPace = WorkPace()) -> Bool {
        var pace = pace
        for reading in readings { pace.sample(arrivals: reading) }
        return pace.isWorking
    }

    func testItStartsSettled() {
        XCTAssertFalse(WorkPace().isWorking)
    }

    /// The whole point of the item: one burst must not set it working.
    func testOneBurstIsNotWork() {
        XCTAssertFalse(run([9]))
    }

    func testABusyRunStartsIt() {
        XCTAssertTrue(run(Array(repeating: 9, count: WorkPace.toStart)))
    }

    /// And one gap must not stop it. A build finishing before its tests start
    /// is a quiet sample in the middle of obvious work.
    func testOneQuietSampleDoesNotStopIt() {
        var pace = WorkPace()
        for _ in 0..<WorkPace.toStart { pace.sample(arrivals: 9) }
        XCTAssertTrue(pace.isWorking)
        pace.sample(arrivals: 0)
        XCTAssertTrue(pace.isWorking, "one gap ended it")
    }

    func testAQuietRunStopsIt() {
        var pace = WorkPace(isWorking: true)
        for _ in 0..<WorkPace.toStop { pace.sample(arrivals: 0) }
        XCTAssertFalse(pace.isWorking)
    }

    /// It leans in sooner than it settles back: noticing late looks broken,
    /// settling late just looks patient.
    func testItStartsSoonerThanItStops() {
        XCTAssertLessThan(WorkPace.toStart, WorkPace.toStop)
    }

    /// A single threshold turns the pet on and off every sample for a session
    /// sitting on the line. The gap between the two is what stops that.
    func testTheDeadBandDecidesNothing() {
        let between = WorkPace.quietBelow + 1
        XCTAssertLessThan(between, WorkPace.busyAbove, "there is no dead band to test")
        XCTAssertFalse(run(Array(repeating: between, count: 20)),
                       "readings between the thresholds started it")
        var working = WorkPace(isWorking: true)
        for _ in 0..<20 { working.sample(arrivals: between) }
        XCTAssertTrue(working.isWorking, "readings between the thresholds stopped it")
    }

    /// A run of disagreement has to be consecutive, or a busy sample every
    /// other tick would eventually add up to a state change.
    func testDisagreementMustBeConsecutive() {
        var pace = WorkPace()
        for _ in 0..<12 {
            pace.sample(arrivals: 9)
            pace.sample(arrivals: 0)
        }
        XCTAssertFalse(pace.isWorking)
    }

    func testAChangeIsReportedOnceAndOnlyOnce() {
        var pace = WorkPace()
        var changes = 0
        for _ in 0..<10 where pace.sample(arrivals: 9) { changes += 1 }
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(pace.isWorking)
    }

    // MARK: - The signal it reads

    /// Arrivals, not approvals: an auto approved call never reaches a decision,
    /// and that is exactly the traffic the pet used to sleep through.
    func testArrivalsAreCountedAndDecisionsAreNot() {
        var journal = Journal()
        for offset in [5.0, 20.0, 60.0] {
            journal.add(Journal.Entry(at: start.addingTimeInterval(-offset), kind: .arrived,
                                      project: "squawk", text: "Bash: swift build"), now: start)
        }
        journal.add(Journal.Entry(at: start.addingTimeInterval(-6), kind: .approved,
                                  project: "squawk", text: "Bash: swift build"), now: start)
        XCTAssertEqual(journal.arrivals(now: start), 3)
    }

    func testAnythingOlderThanTheWindowIsNotWork() {
        var journal = Journal()
        journal.add(Journal.Entry(at: start.addingTimeInterval(-(WorkPace.window + 10)),
                                  kind: .arrived, project: "squawk", text: "old"), now: start)
        XCTAssertEqual(journal.arrivals(now: start), 0)
    }

    // MARK: - What the face does with it

    /// The bug this exists to fix: twenty minutes of auto approved work with
    /// nothing ever reaching the dial, and a pet asleep through all of it.
    func testBusyAgentsOutrankTheIdleClock() {
        XCTAssertEqual(
            FaceMood.expression(waiting: 0, awaitingDecision: false, lastEvent: nil,
                                eventAge: .infinity, idleFor: FaceMood.sleepAfter * 2,
                                working: true),
            .working
        )
        XCTAssertEqual(
            FaceMood.expression(waiting: 0, awaitingDecision: false, lastEvent: nil,
                                eventAge: .infinity, idleFor: FaceMood.sleepAfter * 2,
                                working: false),
            .sleepy
        )
    }

    /// Working is work happening, not work asking. Anything actually waiting
    /// on a human still outranks it.
    func testAnythingWaitingOutranksWorking() {
        XCTAssertEqual(
            FaceMood.expression(waiting: 1, awaitingDecision: true, lastEvent: nil,
                                eventAge: .infinity, idleFor: 0, working: true),
            .alert
        )
    }

    func testAReactionStillGetsItsSecond() {
        XCTAssertEqual(
            FaceMood.expression(waiting: 0, awaitingDecision: false, lastEvent: .approved,
                                eventAge: 0.2, idleFor: 0, working: true),
            .happy
        )
    }

    func testWorkingReachesTheMoodDecision() {
        XCTAssertEqual(Mood.decide(MoodState(idleFor: 9_999, working: true)).expression, .working)
        XCTAssertEqual(Mood.decide(MoodState(idleFor: 9_999, working: false)).expression, .sleepy)
    }

    /// It must not look bored or asleep, which is the whole complaint, and it
    /// must not look like it wants something, which would be a false alarm.
    func testItLooksNeitherAsleepNorDemanding() {
        XCTAssertGreaterThan(FaceExpression.working.openness, FaceExpression.bored.openness)
        XCTAssertLessThan(FaceExpression.working.openness, FaceExpression.alert.openness)
        XCTAssertFalse(FaceExpression.working.demandsAttention)
        XCTAssertFalse(FaceExpression.working.isReaction)
        XCTAssertEqual(FaceExpression.working.gazeBias, 0, "it looks at its work, not away")
    }
}
