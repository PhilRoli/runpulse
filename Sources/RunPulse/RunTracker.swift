import Foundation

struct FinishedEvent: Equatable {
    var run: Run
}

struct RunTracker {
    static let ignoredEvents: Set<String> = ["pull_request", "pull_request_target", "schedule"]
    static let recentLimit = 10
    static let notifiedLimit = 500
    static let firstSeenWindow: TimeInterval = 600

    private(set) var baselineAt: Date
    private var runs: [Int: Run] = [:]
    private var notified: [String] = []
    private var seenRepos: Set<String> = []

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
        baselineAt = max(baselineAt, date)
    }

    mutating func remove(repo: String) {
        runs = runs.filter { $0.value.repo != repo }
        seenRepos.remove(repo)
    }

    mutating func remove(runID: Int) {
        runs[runID] = nil
    }

    /// Tracked, unfinished runs of `repo` that the fetched `page` no longer contains.
    func unfinishedRuns(missingFrom page: [Run], repo: String) -> [Run] {
        let pageIDs = Set(page.map(\.id))
        return runs.values.filter { $0.repo == repo && !$0.state.isCompleted && !pageIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    /// `incoming` is the newest page of `repo`'s runs; that repo's finished runs missing from it are dropped,
    /// unfinished ones stay until they are fetched individually.
    mutating func merge(repo: String, runs incoming: [Run], now: Date) -> [FinishedEvent] {
        // A repo entering polling late must not announce everything that finished since launch.
        let baseline = seenRepos.contains(repo)
            ? baselineAt : max(baselineAt, now.addingTimeInterval(-Self.firstSeenWindow))
        seenRepos.insert(repo)
        let relevant = incoming.filter { !Self.ignoredEvents.contains($0.event) }
        var events = relevant.compactMap { apply($0, baseline: baseline) }
        let pageIDs = Set(relevant.map(\.id))
        runs = runs.filter { $0.value.repo != repo || !$0.value.state.isCompleted || pageIDs.contains($0.value.id) }
        events.sort { ($0.run.updatedAt, $0.run.id) < ($1.run.updatedAt, $1.run.id) }
        return events
    }

    mutating func mergeSingle(_ run: Run, now: Date) -> [FinishedEvent] {
        guard !Self.ignoredEvents.contains(run.event) else {
            runs[run.id] = nil // never leave an ignored run lingering as "unfinished"
            return []
        }
        return apply(run, baseline: baselineAt).map { [$0] } ?? []
    }

    private mutating func apply(_ run: Run, baseline: Date) -> FinishedEvent? {
        let previous = runs[run.id]
        runs[run.id] = run
        guard run.state.isCompleted, !notified.contains(run.key) else { return nil }
        let sawUnfinished = previous.map { $0.key != run.key || !$0.state.isCompleted } ?? false
        let finishedSinceBaseline = previous == nil && run.updatedAt > baseline
        guard sawUnfinished || finishedSinceBaseline else { return nil }
        remember(run.key)
        return FinishedEvent(run: run)
    }

    private mutating func remember(_ key: String) {
        notified.append(key)
        if notified.count > Self.notifiedLimit {
            notified.removeFirst(notified.count - Self.notifiedLimit)
        }
    }
}
