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
}
