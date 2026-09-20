import Foundation

/// Every request currently waiting on a human, in arrival order. One arc on the
/// ring per entry. Pure state so the panel stays a rendering of it.
public struct Roster: Sendable, Equatable {
    public private(set) var entries: [Entry] = []

    public struct Entry: Sendable, Equatable, Identifiable {
        public let request: PendingRequest
        public let arrivedAt: Date
        public var id: String { request.id }

        public init(request: PendingRequest, arrivedAt: Date) {
            self.request = request
            self.arrivedAt = arrivedAt
        }
    }

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// A repeated id replaces the earlier entry rather than stacking. Claude Code
    /// retries a hook on reconnect and two arcs for one call would double count.
    @discardableResult
    public mutating func add(_ request: PendingRequest, now: Date = Date()) -> Bool {
        if let index = entries.firstIndex(where: { $0.id == request.id }) {
            entries[index] = Entry(request: request, arrivedAt: entries[index].arrivedAt)
            return false
        }
        entries.append(Entry(request: request, arrivedAt: now))
        return true
    }

    @discardableResult
    public mutating func remove(id: String) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Drops entries whose hook has already given up. Each one expires on the
    /// budget it declared, so a decision is never offered to a dead listener.
    @discardableResult
    public mutating func expire(now: Date = Date(), fallback: TimeInterval) -> [Entry] {
        func isStale(_ entry: Entry) -> Bool {
            let budget = entry.request.waitSeconds ?? fallback
            return now.timeIntervalSince(entry.arrivedAt) >= budget
        }
        let stale = entries.filter(isStale)
        entries.removeAll(where: isStale)
        return stale
    }

    public func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Distinct sessions represented, which is what the ring's centre counts.
    public var sessionCount: Int {
        Set(entries.map(\.request.sessionId)).count
    }

    /// The same entries with each session's kept together, sessions in the
    /// order they first arrived and entries inside one still in arrival order.
    ///
    /// Three agents interleaving put three projects' arcs around the ring in
    /// whatever order their calls happened to land, so nothing read as "this
    /// agent wants three things". Grouping is what makes the ring answerable
    /// at a glance rather than a list you have to read.
    public var grouped: [Entry] {
        var order: [String] = []
        var bySession: [String: [Entry]] = [:]
        for entry in entries {
            let key = entry.request.sessionId
            if bySession[key] == nil { order.append(key) }
            bySession[key, default: []].append(entry)
        }
        return order.flatMap { bySession[$0] ?? [] }
    }

    /// Indices into `grouped` where a new session begins, so the ring can set
    /// the gap between two agents wider than the gap between two of one
    /// agent's calls. Without that the grouping is an order nobody can see.
    public var sessionBreaks: Set<Int> {
        var breaks: Set<Int> = []
        var previous: String?
        for (index, entry) in grouped.enumerated() {
            if entry.request.sessionId != previous { breaks.insert(index) }
            previous = entry.request.sessionId
        }
        return breaks
    }

    /// What to select once `id` has been answered.
    ///
    /// Another call from the same agent first, because finishing one session
    /// beats being thrown to a different project on every click: answering is
    /// only half the loop, and the half that costs you is the context switch.
    public func next(after id: String) -> String? {
        guard let answered = entry(id: id) else { return grouped.first?.id }
        let session = answered.request.sessionId
        let remaining = grouped.filter { $0.id != id }
        return remaining.first { $0.request.sessionId == session }?.id
            ?? remaining.first?.id
    }

    /// How many sessions are waiting besides this one, for a card that has to
    /// say which agent you are answering.
    public func otherSessions(than id: String) -> Int {
        guard let entry = entry(id: id) else { return max(0, sessionCount) }
        return Set(entries.map(\.request.sessionId))
            .subtracting([entry.request.sessionId]).count
    }
}
