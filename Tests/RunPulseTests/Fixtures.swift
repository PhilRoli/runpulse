import Foundation
@testable import RunPulse

extension Run {
    static func fixture(id: Int = 1, attempt: Int = 1, repo: String = "me/app", workflow: String = "CI",
                        event: String = "push", branch: String? = "main", status: String = "completed",
                        conclusion: String? = "success", created: Date, started: Date? = nil,
                        updated: Date? = nil) -> Run {
        Run(id: id, attempt: attempt, repo: repo, workflow: workflow, event: event, branch: branch,
            title: "commit", status: status, conclusion: conclusion, createdAt: created,
            startedAt: started ?? created, updatedAt: updated ?? created,
            htmlURL: URL(string: "https://github.com/\(repo)/actions/runs/\(id)")!)
    }
}

extension Repo {
    static func fixture(_ fullName: String, pushedAt: Date, archived: Bool = false) -> Repo {
        Repo(fullName: fullName, pushedAt: pushedAt, htmlURL: URL(string: "https://github.com/\(fullName)")!,
             archived: archived)
    }
}

/// Unique, self-cleaning UserDefaults suite for tests.
final class TestDefaults {
    let name = "RunPulseTests-\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    func tearDown() { defaults.removePersistentDomain(forName: name) }
}

enum JSONFixtures {
    static let runsPage = """
    {"total_count":2,"workflow_runs":[
     {"id":37021588860,"run_attempt":1,"name":"Release","event":"push","head_branch":"v1.0.1",
      "display_title":"feat: write limits","status":"completed","conclusion":"success",
      "created_at":"2026-10-02T14:41:10Z","run_started_at":"2026-10-02T14:41:10Z",
      "updated_at":"2026-10-02T14:42:32Z",
      "html_url":"https://github.com/PhilRoli/claudeusage/actions/runs/37021588860",
      "repository":{"full_name":"PhilRoli/claudeusage"}},
     {"id":37021588861,"name":"CI","event":"push","head_branch":"main","display_title":"feat: write limits",
      "status":"in_progress","conclusion":null,"created_at":"2026-10-02T14:41:10Z","run_started_at":null,
      "updated_at":"2026-10-02T14:41:20Z",
      "html_url":"https://github.com/PhilRoli/claudeusage/actions/runs/37021588861",
      "repository":{"full_name":"PhilRoli/claudeusage"}}]}
    """

    static let repos = """
    [{"full_name":"PhilRoli/homebrew-tap","pushed_at":"2026-10-02T14:42:28Z",
      "html_url":"https://github.com/PhilRoli/homebrew-tap","archived":false},
     {"full_name":"KBastianK/CADS","pushed_at":null,"html_url":"https://github.com/KBastianK/CADS","archived":true}]
    """

    static let jobsFailed = """
    {"total_count":2,"jobs":[
     {"name":"lint","status":"completed","conclusion":"success","steps":[{"name":"Lint","conclusion":"success"}]},
     {"name":"build","status":"completed","conclusion":"failure","steps":[
       {"name":"Set up job","conclusion":"success"},{"name":"Run tests","conclusion":"failure"},
       {"name":"Post","conclusion":"skipped"}]}]}
    """

    static let jobsTimedOutNoSteps = """
    {"total_count":1,"jobs":[{"name":"deploy","status":"completed","conclusion":"timed_out","steps":[]}]}
    """

    static let jobsOK = """
    {"total_count":1,"jobs":[{"name":"release","status":"completed","conclusion":"success","steps":[]}]}
    """
}

final class FakeGitHub: GitHubFetching, @unchecked Sendable {
    var login: Result<String, GitHubError> = .success("me")
    var repos: Result<[Repo], GitHubError> = .success([])
    var runs: [String: Result<[Run], GitHubError>] = [:]
    var steps: [Int: FailedStep] = [:]
    var unauthorizedTokens: Set<String> = []
    var beforeViewer: (() async -> Void)?
    private(set) var calls: [String] = []

    func viewer(token: String) async throws -> String {
        calls.append("viewer")
        try check(token)
        let result = login
        await beforeViewer?()
        return try result.get()
    }

    func recentRepos(token: String) async throws -> [Repo] {
        calls.append("repos")
        try check(token)
        return try repos.get()
    }

    func runs(repo: String, actor: String, token: String) async throws -> [Run] {
        calls.append("runs \(repo)")
        try check(token)
        return try (runs[repo] ?? .success([])).get()
    }

    func failedStep(repo: String, runID: Int, token: String) async throws -> FailedStep? {
        calls.append("jobs \(runID)")
        return steps[runID]
    }

    func resetCalls() { calls = [] }

    private func check(_ token: String) throws {
        if unauthorizedTokens.contains(token) { throw GitHubError.unauthorized }
    }
}

/// Returns `next` values in order on each fresh read (the last one repeats); caches like the real provider.
final class FakeTokens: TokenProviding, @unchecked Sendable {
    var next: [Token?] = [Token(value: "tok", source: .gh)]
    private var current: Token?
    private(set) var reads = 0
    private(set) var invalidations = 0

    func token() throws -> Token {
        if let current { return current }
        reads += 1
        let value = next.count > 1 ? next.removeFirst() : (next.first ?? nil)
        guard let value else { throw TokenError.missing }
        current = value
        return value
    }

    func invalidate() {
        invalidations += 1
        current = nil
    }
}
