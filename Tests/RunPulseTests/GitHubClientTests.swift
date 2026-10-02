import XCTest
@testable import RunPulse

private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    var responses: [Result<HTTPResponse, Error>] = []
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return try responses.removeFirst().get()
    }
}

private func ok(_ body: String, etag: String? = nil) -> Result<HTTPResponse, Error> {
    .success(HTTPResponse(data: Data(body.utf8), status: 200, headers: etag.map { ["etag": $0] } ?? [:]))
}

private func status(_ code: Int, _ headers: [String: String] = [:]) -> Result<HTTPResponse, Error> {
    .success(HTTPResponse(data: Data(), status: code, headers: headers))
}

final class GitHubClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var transport: ScriptedTransport!
    private var client: GitHubClient!

    override func setUp() {
        transport = ScriptedTransport()
        let fixed = now
        client = GitHubClient(transport: transport, now: { fixed })
    }

    private func assertThrows(_ expected: GitHubError, file: StaticString = #filePath, line: UInt = #line,
                              _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GitHubError, expected, file: file, line: line)
        }
    }

    func testURLs() {
        XCTAssertEqual(GitHubClient.viewerURL.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(GitHubClient.reposURL.absoluteString,
                       "https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member"
                       + "&per_page=50&sort=pushed")
        XCTAssertEqual(GitHubClient.runsURL(repo: "me/app", actor: "PhilRoli").absoluteString,
                       "https://api.github.com/repos/me/app/actions/runs?actor=PhilRoli&per_page=20")
        XCTAssertEqual(GitHubClient.jobsURL(repo: "me/app", runID: 42).absoluteString,
                       "https://api.github.com/repos/me/app/actions/runs/42/jobs?filter=latest")
    }

    func testHeadersAndViewer() async throws {
        transport.responses = [ok(#"{"login":"PhilRoli","id":1}"#)]
        let login = try await client.viewer(token: "t0k")
        XCTAssertEqual(login, "PhilRoli")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testDecodesReposAndRuns() async throws {
        transport.responses = [ok(JSONFixtures.repos), ok(JSONFixtures.runsPage)]
        let repos = try await client.recentRepos(token: "t")
        let runs = try await client.runs(repo: "PhilRoli/claudeusage", actor: "PhilRoli", token: "t")
        XCTAssertEqual(repos.count, 2)
        XCTAssertEqual(runs.map(\.workflow), ["Release", "CI"])
    }

    func testETagReuseOn304() async throws {
        transport.responses = [ok(JSONFixtures.repos, etag: "W/\"1\""), status(304)]
        let first = try await client.recentRepos(token: "t")
        let second = try await client.recentRepos(token: "t")
        XCTAssertEqual(first, second)
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "If-None-Match"), "W/\"1\"")
    }

    func testETagCacheIsPerToken() async throws {
        transport.responses = [ok(JSONFixtures.repos, etag: "W/\"1\""), ok("[]")]
        _ = try await client.recentRepos(token: "account-a")
        let other = try await client.recentRepos(token: "account-b")
        XCTAssertNil(transport.requests[1].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(other, [])
    }

    func test304WithoutCacheIsHTTPError() async {
        transport.responses = [status(304)]
        await assertThrows(.http(304)) { _ = try await self.client.recentRepos(token: "t") }
    }

    func testErrorMapping() async {
        transport.responses = [status(401), status(403), status(404), status(500), ok("<html>"),
                               .failure(URLError(.timedOut))]
        await assertThrows(.unauthorized) { _ = try await self.client.viewer(token: "t") }
        await assertThrows(.noAccess) { _ = try await self.client.runs(repo: "a/b", actor: "me", token: "t") }
        await assertThrows(.noAccess) { _ = try await self.client.runs(repo: "a/b", actor: "me", token: "t") }
        await assertThrows(.http(500)) { _ = try await self.client.recentRepos(token: "t") }
        await assertThrows(.decoding) { _ = try await self.client.recentRepos(token: "t") }
        await assertThrows(.unreachable) { _ = try await self.client.recentRepos(token: "t") }
    }

    func testPrimaryRateLimit() async {
        transport.responses = [status(403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000900"])]
        await assertThrows(.rateLimited(until: Date(timeIntervalSince1970: 1_800_000_900))) {
            _ = try await self.client.recentRepos(token: "t")
        }
    }

    func testRetryAfterIsRateLimit() async {
        transport.responses = [status(403, ["x-ratelimit-remaining": "12", "retry-after": "30"])]
        await assertThrows(.rateLimited(until: now.addingTimeInterval(30))) {
            _ = try await self.client.runs(repo: "a/b", actor: "me", token: "t")
        }
    }

    func test429WithoutHeadersWaitsAMinute() async {
        transport.responses = [status(429)]
        await assertThrows(.rateLimited(until: now.addingTimeInterval(60))) {
            _ = try await self.client.recentRepos(token: "t")
        }
    }

    func testCancellationPropagates() async {
        transport.responses = [.failure(URLError(.cancelled))]
        do {
            _ = try await client.recentRepos(token: "t")
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testFailedStepUsesJobsEndpoint() async throws {
        transport.responses = [ok(JSONFixtures.jobsFailed)]
        let step = try await client.failedStep(repo: "me/app", runID: 42, token: "t")
        XCTAssertEqual(step, FailedStep(job: "build", step: "Run tests"))
        XCTAssertEqual(transport.requests.first?.url, GitHubClient.jobsURL(repo: "me/app", runID: 42))
    }
}
