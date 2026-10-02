import Foundation

struct FinishedEvent: Equatable {
    var run: Run
}

struct RunTracker {
    static let ignoredEvents: Set<String> = ["pull_request", "pull_request_target", "schedule"]
    static let recentLimit = 10
    static let notifiedLimit = 500

    private(set) var baselineAt: Date
    private var runs: [Int: Run] = [:]
    private var notified: [String] = []

    init(baselineAt: Date) {
        self.baselineAt = baselineAt
    }

    var running: [Run] {
        runs.values.filter { !$0.state.isCompleted }.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    var recent: [Run] {
        Array(runs.values.filter { $0.state.isCompleted }.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
            .prefix(Self.recentLimit))
    }

    var reposWithActiveRuns: Set<String> {
        Set(runs.values.filter { !$0.state.isCompleted }.map(\.repo))
    }

    var notifiedCount: Int { notified.count }

    func hasActiveRuns(repo: String) -> Bool {
        runs.values.contains { $0.repo == repo && !$0.state.isCompleted }
    }

    mutating func rebaseline(at date: Date) {
        baselineAt = date
    }

    mutating func remove(repo: String) {
        runs = runs.filter { $0.value.repo != repo }
    }

    /// `incoming` is the newest page of `repo`'s runs; that repo's runs missing from it are dropped.
    mutating func merge(repo: String, runs incoming: [Run]) -> [FinishedEvent] {
        let relevant = incoming.filter { !Self.ignoredEvents.contains($0.event) }
        var events: [FinishedEvent] = []
        for run in relevant {
            let previous = runs[run.id]
            runs[run.id] = run
            guard run.state.isCompleted, !notified.contains(run.key) else { continue }
            let sawUnfinished = previous.map { $0.key != run.key || !$0.state.isCompleted } ?? false
            let finishedSinceBaseline = previous == nil && run.updatedAt > baselineAt
            guard sawUnfinished || finishedSinceBaseline else { continue }
            remember(run.key)
            events.append(FinishedEvent(run: run))
        }
        let pageIDs = Set(relevant.map(\.id))
        runs = runs.filter { $0.value.repo != repo || pageIDs.contains($0.value.id) }
        return events.sorted { ($0.run.updatedAt, $0.run.id) < ($1.run.updatedAt, $1.run.id) }
    }

    private mutating func remember(_ key: String) {
        notified.append(key)
        if notified.count > Self.notifiedLimit {
            notified.removeFirst(notified.count - Self.notifiedLimit)
        }
    }
}
