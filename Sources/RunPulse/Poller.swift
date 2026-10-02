import Foundation

enum PollStatus: Equatable {
    case loading, ok, stale, authMissing, authFailed, unreachable
    case rateLimited(until: Date)
}

struct PollerState: Equatable {
    var account: String?
    var tokenSource: TokenSource?
    var status: PollStatus = .loading
    var running: [Run] = []
    var recent: [Run] = []
    /// Keyed by `Run.key`.
    var failures: [String: FailedStep] = [:]
    var discovered: [String] = []
    var noAccess: Set<String> = []
    var activeRepos: [String] = []
}

@MainActor
final class Poller {
    static let tickInterval: TimeInterval = 5
    static let idleInterval: TimeInterval = 60
    static let activeInterval: TimeInterval = 10
    static let noAccessCooldown: TimeInterval = 3_600
    static let wakeLookback: TimeInterval = 600

    private let client: GitHubFetching
    private let tokens: TokenProviding
    private let now: () -> Date
    private var config: AppConfig
    private var tracker: RunTracker
    private var repos: [Repo] = []
    private var login: String?
    private var lastRepoFetch: Date?
    private var lastRunFetch: [String: Date] = [:]
    private var cooldown: [String: Date] = [:]
    private var pausedUntil: Date?
    private var lastAuthAttempt: Date?
    private var failureCount = 0
    private var isTicking = false
    private var loop: Task<Void, Never>?

    private(set) var state = PollerState()
    var onUpdate: ((PollerState) -> Void)?
    var onFinished: (([FinishedEvent], [String: FailedStep]) -> Void)?

    init(client: GitHubFetching, tokens: TokenProviding, config: AppConfig, now: @escaping () -> Date = { Date() }) {
        self.client = client
        self.tokens = tokens
        self.config = config
        self.now = now
        self.tracker = RunTracker(baselineAt: now())
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
            }
        }
    }

    func refreshNow() {
        Task { await tick(force: true) }
    }

    func apply(_ newConfig: AppConfig) {
        let newlyMuted = Set(newConfig.muted).subtracting(config.muted)
        config = newConfig
        newlyMuted.forEach { tracker.remove(repo: $0) }
        refreshLists(at: now())
        publish()
    }

    func tokenChanged() {
        tokens.invalidate()
        login = nil
        state.account = nil
        lastAuthAttempt = nil
        refreshNow()
    }

    /// Runs that finished while asleep only notify if they ended in the last 10 minutes.
    func prepareForWake() {
        tracker.rebaseline(at: now().addingTimeInterval(-Self.wakeLookback))
    }

    func didWake() {
        prepareForWake()
        refreshNow()
    }

    func tick(force: Bool = false) async {
        guard !isTicking else { return }
        isTicking = true
        defer {
            isTicking = false
            publish()
        }
        let at = now()
        guard force || isAllowed(at) else { return }
        guard let token = await readToken() else {
            lastAuthAttempt = at
            state.status = .authMissing
            return
        }
        do {
            let used = try await cycleRetryingAuth(token, at: at, force: force)
            state.tokenSource = used.source
            failureCount = 0
            pausedUntil = nil
            lastAuthAttempt = nil
            state.status = .ok
        } catch is CancellationError {
            return
        } catch {
            fail(error as? GitHubError ?? .unreachable, at: at)
        }
    }

    // MARK: Cycle

    private func isAllowed(_ at: Date) -> Bool {
        if let pausedUntil, at < pausedUntil { return false }
        if state.status == .authMissing || state.status == .authFailed, let last = lastAuthAttempt {
            return at.timeIntervalSince(last) >= Self.idleInterval
        }
        return true
    }

    /// A 401 drops the cached token and retries once with a freshly read one.
    private func cycleRetryingAuth(_ token: Token, at: Date, force: Bool) async throws -> Token {
        do {
            try await cycle(token: token.value, at: at, force: force)
            return token
        } catch GitHubError.unauthorized {
            tokens.invalidate()
            guard let fresh = await readToken(), fresh.value != token.value else { throw GitHubError.unauthorized }
            try await cycle(token: fresh.value, at: at, force: true)
            return fresh
        }
    }

    private func cycle(token: String, at: Date, force: Bool) async throws {
        if login == nil {
            login = try await client.viewer(token: token)
            state.account = login
        }
        guard let login else { return }
        if force || isDue(lastRepoFetch, Self.idleInterval, at) {
            repos = try await client.recentRepos(token: token)
            lastRepoFetch = at
        }
        for repo in activeRepos(at: at) {
            let interval = tracker.hasActiveRuns(repo: repo) ? Self.activeInterval : Self.idleInterval
            guard force || isDue(lastRunFetch[repo], interval, at) else { continue }
            do {
                let runs = try await client.runs(repo: repo, actor: login, token: token)
                lastRunFetch[repo] = at
                state.noAccess.remove(repo)
                await report(tracker.merge(repo: repo, runs: runs), repo: repo, token: token)
            } catch GitHubError.noAccess {
                cooldown[repo] = at.addingTimeInterval(Self.noAccessCooldown)
                state.noAccess.insert(repo)
            } catch GitHubError.http(_), GitHubError.decoding {
                lastRunFetch[repo] = at // one broken repo must not stale the rest
            }
        }
        refreshLists(at: at)
    }

    private func fail(_ error: GitHubError, at: Date) {
        switch error {
        case .unauthorized:
            lastAuthAttempt = at
            state.status = .authFailed
        case .rateLimited(let until):
            pausedUntil = until
            state.status = .rateLimited(until: until)
        case .noAccess, .http, .unreachable, .decoding:
            failureCount += 1
            guard failureCount >= 2 else { return }
            state.status = lastRepoFetch == nil ? .unreachable : .stale
        }
    }

    // MARK: Repos and lists

    private func isDue(_ last: Date?, _ interval: TimeInterval, _ at: Date) -> Bool {
        guard let last else { return true }
        return at.timeIntervalSince(last) >= interval - 1 // tolerate tick jitter
    }

    private func discovered(at: Date) -> [String] {
        let cutoff = at.addingTimeInterval(-Double(config.lookbackDays) * 86_400)
        return repos.filter { !$0.archived && ($0.pushedAt ?? .distantPast) >= cutoff }.map(\.fullName)
    }

    private func activeRepos(at: Date) -> [String] {
        let muted = Set(config.muted)
        var result = discovered(at: at).filter { repo in
            !muted.contains(repo) && (cooldown[repo].map { at >= $0 } ?? true)
        }
        for repo in tracker.reposWithActiveRuns.sorted() where !result.contains(repo) && !muted.contains(repo) {
            result.append(repo)
        }
        return result
    }

    private func refreshLists(at: Date) {
        state.discovered = discovered(at: at)
        state.activeRepos = activeRepos(at: at)
        state.running = tracker.running
        state.recent = tracker.recent
        let keys = Set(state.recent.map(\.key))
        state.failures = state.failures.filter { keys.contains($0.key) }
    }

    private func report(_ events: [FinishedEvent], repo: String, token: String) async {
        guard !events.isEmpty else { return }
        var details: [String: FailedStep] = [:]
        for event in events where event.run.state == .failure {
            if let step = try? await client.failedStep(repo: repo, runID: event.run.id, token: token) {
                details[event.run.key] = step
            }
        }
        state.failures.merge(details) { $1 }
        onFinished?(events, details)
    }

    private func publish() {
        onUpdate?(state)
    }

    /// Spawning `gh` and reading the Keychain block, so keep them off the main actor.
    private func readToken() async -> Token? {
        let provider = tokens
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: try? provider.token())
            }
        }
    }
}
