import XCTest
@testable import SquawkCore

final class IdlerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Past the seeding ask and far enough on that everything is off cooldown.
    private func ready(_ idler: inout Idler, at now: Date) {
        XCTAssertNil(idler.next(at: now, roll: 0), "the first ask should only seed")
    }

    func testTheFirstAskOnlySeeds() {
        var idler = Idler()
        XCTAssertNil(idler.next(at: start, roll: 0.5))
    }

    func testNothingHappensBeforeTheRest() {
        var idler = Idler()
        ready(&idler, at: start)
        XCTAssertNil(idler.next(at: start.addingTimeInterval(Idler.restBetween - 1), roll: 0.5))
        XCTAssertNotNil(idler.next(at: start.addingTimeInterval(Idler.restBetween), roll: 0.5))
    }

    /// Every entry has to be reachable, or it is a case nobody ever sees.
    func testEveryMoveCanBePicked() {
        var seen = Set<IdleMove>()
        for step in 0..<400 {
            var idler = Idler()
            ready(&idler, at: start)
            let roll = Double(step) / 400
            if let move = idler.next(at: start.addingTimeInterval(Idler.restBetween), roll: roll) {
                seen.insert(move)
            }
        }
        XCTAssertEqual(seen, Set(IdleMove.allCases))
    }

    func testTheRollIsClampedRatherThanFallingThrough() {
        for roll in [-1.0, 0.0, 1.0, 2.0] {
            var idler = Idler()
            ready(&idler, at: start)
            XCTAssertNotNil(idler.next(at: start.addingTimeInterval(Idler.restBetween), roll: roll),
                            "roll \(roll) picked nothing")
        }
    }

    /// The whole point of the catalogue. A weighted pick alone lets the
    /// heaviest entry come up three times running, which looks like a loop.
    func testAMoveIsOnCooldownAfterItPlays() {
        var idler = Idler()
        ready(&idler, at: start)
        var now = start.addingTimeInterval(Idler.restBetween)
        guard let first = idler.next(at: now, roll: 0.0) else { return XCTFail("picked nothing") }

        now = now.addingTimeInterval(first.duration + Idler.restBetween)
        let weights = Dictionary(uniqueKeysWithValues: idler.weights(at: now).map { ($0.move, $0.weight) })
        XCTAssertEqual(weights[first], 0, "\(first) was available again inside its cooldown")
    }

    func testCooldownLapses() {
        var idler = Idler()
        ready(&idler, at: start)
        let now = start.addingTimeInterval(Idler.restBetween)
        guard let first = idler.next(at: now, roll: 0.0) else { return XCTFail("picked nothing") }

        let later = now.addingTimeInterval(first.cooldown + 1)
        let weights = Dictionary(uniqueKeysWithValues: idler.weights(at: later).map { ($0.move, $0.weight) })
        XCTAssertGreaterThan(weights[first] ?? 0, 0)
    }

    /// Off cooldown but recently played is not the same as never played.
    func testTheLastFewAreCutRatherThanRestored() {
        var idler = Idler()
        ready(&idler, at: start)
        let now = start.addingTimeInterval(Idler.restBetween)
        guard let first = idler.next(at: now, roll: 0.0) else { return XCTFail("picked nothing") }

        let later = now.addingTimeInterval(first.cooldown + 1)
        let weights = Dictionary(uniqueKeysWithValues: idler.weights(at: later).map { ($0.move, $0.weight) })
        XCTAssertEqual(weights[first] ?? -1, first.weight * Idler.recentShare, accuracy: 0.0001)
    }

    func testTheMemoryIsOnlyAsLongAsItSays() {
        var idler = Idler()
        ready(&idler, at: start)
        var now = start.addingTimeInterval(Idler.restBetween)
        var played: [IdleMove] = []
        // Long gaps, so nothing is held back by a cooldown and the memory is
        // the only thing being measured.
        for step in 0..<(Idler.remembers + 3) {
            let roll = Double(step % 7) / 7
            if let move = idler.next(at: now, roll: roll) { played.append(move) }
            now = now.addingTimeInterval(600)
        }
        XCTAssertGreaterThan(played.count, Idler.remembers)

        let weights = Dictionary(uniqueKeysWithValues: idler.weights(at: now).map { ($0.move, $0.weight) })
        let cut = IdleMove.allCases.filter { (weights[$0] ?? 0) < $0.weight }
        XCTAssertLessThanOrEqual(cut.count, Idler.remembers,
                                 "more moves are held down than the memory is long")
    }

    /// Everything resting is a fine answer for a turn: the pet stands there and
    /// breathes, which is what it did before any of this existed. What would
    /// not be fine is staying that way, so a quiet spell is bounded by the
    /// shortest cooldown in the catalogue, whatever order the rolls fall in.
    func testAQuietSpellIsShortLived() {
        var seed: UInt64 = 0xD15EA5E
        func roll() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let shortest = IdleMove.allCases.map(\.cooldown).min() ?? 0
        var idler = Idler()
        ready(&idler, at: start)

        var now = start.addingTimeInterval(Idler.restBetween)
        var lastMoved = now
        var longestQuiet: TimeInterval = 0
        // Two hours, asked once a second, which is far more often than the app
        // asks and therefore a harder test of the gaps.
        for _ in 0..<7_200 {
            if idler.next(at: now, roll: roll()) != nil {
                longestQuiet = max(longestQuiet, now.timeIntervalSince(lastMoved))
                lastMoved = now
            }
            now = now.addingTimeInterval(1)
        }
        XCTAssertGreaterThan(longestQuiet, 0, "it never idled at all")
        XCTAssertLessThanOrEqual(
            longestQuiet, shortest + Idler.restBetween + 2,
            "it stood doing nothing for \(Int(longestQuiet))s"
        )
    }

    /// The anti-loop property as a number. Weight alone puts `watchCursor` at
    /// better than a quarter of every turn; the cooldown and the memory are
    /// what stop the pet running the same two moves all afternoon.
    func testNoMoveTakesOverALongRun() {
        var seed: UInt64 = 0x5EED
        func roll() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        var idler = Idler()
        ready(&idler, at: start)
        var now = start.addingTimeInterval(Idler.restBetween)
        var counts: [IdleMove: Int] = [:]
        let turns = 300
        for _ in 0..<turns {
            guard let move = idler.next(at: now, roll: roll()) else {
                now = now.addingTimeInterval(5)
                continue
            }
            counts[move, default: 0] += 1
            now = now.addingTimeInterval(move.duration + Idler.restBetween)
        }
        let played = counts.values.reduce(0, +)
        XCTAssertEqual(counts.count, IdleMove.allCases.count, "a move never came up at all")
        for (move, count) in counts {
            let share = Double(count) / Double(played)
            XCTAssertLessThan(share, 0.34, "\(move) took \(Int(share * 100))% of the run")
        }
    }

    /// Cooldowns are per move, so the same one twice running is impossible
    /// however the roll falls.
    func testItNeverRepeatsItself() {
        var seed: UInt64 = 0xC0FFEE
        func roll() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        var idler = Idler()
        ready(&idler, at: start)
        var now = start.addingTimeInterval(Idler.restBetween)
        var previous: IdleMove?
        for _ in 0..<200 {
            guard let move = idler.next(at: now, roll: roll()) else {
                now = now.addingTimeInterval(5)
                continue
            }
            XCTAssertNotEqual(move, previous, "it did the same thing twice running")
            previous = move
            now = now.addingTimeInterval(move.duration + Idler.restBetween)
        }
    }

    func testAMoveHoldsTheFloorForItsOwnDuration() {
        var idler = Idler()
        ready(&idler, at: start)
        let now = start.addingTimeInterval(Idler.restBetween)
        guard let move = idler.next(at: now, roll: 0.0) else { return XCTFail("picked nothing") }
        XCTAssertNil(idler.next(at: now.addingTimeInterval(move.duration), roll: 0.5),
                     "the next one started before the rest had passed")
        XCTAssertNotNil(
            idler.next(at: now.addingTimeInterval(move.duration + Idler.restBetween), roll: 0.5)
        )
    }

    /// Something started happening, so whatever it was doing is over and the
    /// next one waits its turn like any other.
    func testAnInterruptionPutsItBackToResting() {
        var idler = Idler()
        ready(&idler, at: start)
        let now = start.addingTimeInterval(Idler.restBetween)
        idler.interrupt(at: now)
        XCTAssertNil(idler.next(at: now, roll: 0.5))
        XCTAssertNotNil(idler.next(at: now.addingTimeInterval(Idler.restBetween), roll: 0.5))
    }

    // MARK: - The catalogue itself

    func testTheHeaviestIsTheOneThatNoticesYou() {
        let heaviest = IdleMove.allCases.max { $0.weight < $1.weight }
        XCTAssertEqual(heaviest, .watchCursor)
    }

    /// A big legible move repeated is a tic. The quick ones may come round
    /// often; the ones you cannot miss may not.
    func testTheBiggestMovesWaitLongest() {
        XCTAssertGreaterThan(IdleMove.stretch.cooldown, IdleMove.watchCursor.cooldown)
        XCTAssertGreaterThan(IdleMove.doze.cooldown, IdleMove.lookAround.cooldown)
        for move in IdleMove.allCases {
            XCTAssertGreaterThan(move.weight, 0, "\(move) can never be picked")
            XCTAssertGreaterThan(move.duration, 0, "\(move) takes no time")
            XCTAssertGreaterThan(move.cooldown, move.duration,
                                 "\(move) may start again before it has finished")
        }
    }
}

final class IdleShapeTests: XCTestCase {
    /// Anything that does not come back to zero leaves the pet permanently
    /// tilted, which is how `.arriving` once left it walking for a whole day.
    func testEveryMoveReturnsExactlyWhereItStarted() {
        let rest = Pose3D()
        for move in IdleMove.allCases {
            for progress in [-0.5, 0.0, 1.0, 1.5] {
                var pose = Pose3D()
                IdleShape.apply(move, progress: progress, toward: 1, to: &pose)
                XCTAssertEqual(pose, rest, "\(move) at \(progress) did not rest")
            }
        }
    }

    func testEveryMoveActuallyMovesSomething() {
        for move in IdleMove.allCases {
            var pose = Pose3D()
            IdleShape.apply(move, progress: 0.5, toward: 1, to: &pose)
            XCTAssertNotEqual(pose, Pose3D(), "\(move) does nothing at all")
        }
    }

    func testWatchingFollowsThePointerAndNotItsOwnMind() {
        var left = Pose3D(), right = Pose3D()
        IdleShape.apply(.watchCursor, progress: 0.5, toward: -1, to: &left)
        IdleShape.apply(.watchCursor, progress: 0.5, toward: 1, to: &right)
        XCTAssertLessThan(left.headYaw, 0)
        XCTAssertGreaterThan(right.headYaw, 0)
    }

    /// A pointer off the edge of the world must not wring its neck.
    func testAFarPointerIsClamped() {
        var far = Pose3D(), edge = Pose3D()
        IdleShape.apply(.watchCursor, progress: 0.5, toward: 40, to: &far)
        IdleShape.apply(.watchCursor, progress: 0.5, toward: 1, to: &edge)
        XCTAssertEqual(far.headYaw, edge.headYaw, accuracy: 0.0001)
    }

    func testGlancingUpLooksUp() {
        var pose = Pose3D()
        IdleShape.apply(.glanceUp, progress: 0.5, to: &pose)
        XCTAssertLessThan(pose.headPitch, 0, "it glanced at the floor")
    }

    /// Reach and hold, not a spike: watching something is mostly the holding.
    func testHoldingHoldsAndArcingDoesNot() {
        XCTAssertEqual(IdleShape.hold(0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(IdleShape.hold(0.6), 1, accuracy: 0.0001)
        XCTAssertLessThan(IdleShape.arc(0.75), IdleShape.arc(0.5))
        let shapes: [(String, (Double) -> Double)] = [
            ("arc", { IdleShape.arc($0) }), ("hold", { IdleShape.hold($0) }),
        ]
        for (name, shape) in shapes {
            for step in 0...20 {
                let value = shape(Double(step) / 20)
                XCTAssertGreaterThanOrEqual(value, 0, name)
                XCTAssertLessThanOrEqual(value, 1.0001, name)
            }
        }
    }
}

/// Settling down before saying anything unasked for, and slowing down the
/// longer nothing changes. Both from Live2DPet.
final class DwellTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testItSaysNothingBeforeYouHaveSettled() {
        var dwell = Dwell()
        dwell.entered("com.apple.dt.Xcode", at: start)
        XCTAssertFalse(dwell.mayVolunteer(at: start))
        XCTAssertFalse(dwell.mayVolunteer(at: start.addingTimeInterval(Dwell.settles - 1)))
        XCTAssertTrue(dwell.mayVolunteer(at: start.addingTimeInterval(Dwell.settles)))
    }

    /// Moving somewhere else starts the clock again, which is the whole point:
    /// a burst of window switching should not end in being talked at.
    func testChangingContextStartsAgain() {
        var dwell = Dwell()
        dwell.entered("a", at: start)
        let settled = start.addingTimeInterval(Dwell.settles)
        XCTAssertTrue(dwell.mayVolunteer(at: settled))
        dwell.entered("b", at: settled)
        XCTAssertFalse(dwell.mayVolunteer(at: settled))
    }

    /// Only a change restarts it. Fed on a clock, re-entering the same context
    /// every tick would mean nobody ever settles at all.
    func testStayingPutDoesNotRestartIt() {
        var dwell = Dwell()
        dwell.entered("a", at: start)
        for step in 0...30 { dwell.entered("a", at: start.addingTimeInterval(Double(step))) }
        XCTAssertTrue(dwell.mayVolunteer(at: start.addingTimeInterval(Dwell.settles)))
    }

    func testNothingFrontmostIsStillAContext() {
        var dwell = Dwell()
        dwell.entered(nil, at: start)
        XCTAssertTrue(dwell.mayVolunteer(at: start.addingTimeInterval(Dwell.settles)))
    }

    func testNeverAskedIsNeverSettled() {
        XCTAssertFalse(Dwell().mayVolunteer(at: start))
    }

    // MARK: - Slowing down

    func testTheGapStretchesAsThingsStayQuiet() {
        let base = Idler.restBetween
        XCTAssertEqual(Ambient.gap(base: base, quietFor: 0), base, accuracy: 0.001)
        let hour = Ambient.gap(base: base, quietFor: Ambient.fullyQuietAfter)
        XCTAssertEqual(hour, base * Ambient.slowestFactor, accuracy: 0.001)
    }

    /// The first few minutes barely slow at all; the long tail does the work.
    func testItBarelySlowsAtFirst() {
        let base = Idler.restBetween
        let early = Ambient.gap(base: base, quietFor: 120)
        XCTAssertLessThan(early, base * 1.1)
        XCTAssertGreaterThanOrEqual(early, base)
    }

    func testItNeverSpeedsUpAndNeverRunsAway() {
        let base = Idler.restBetween
        var previous = base
        for minutes in stride(from: 0.0, through: 120.0, by: 5) {
            let gap = Ambient.gap(base: base, quietFor: minutes * 60)
            XCTAssertGreaterThanOrEqual(gap, previous - 0.001, "it sped up at \(minutes) min")
            XCTAssertLessThanOrEqual(gap, base * Ambient.slowestFactor + 0.001)
            previous = gap
        }
    }
}
