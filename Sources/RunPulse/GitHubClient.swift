import Foundation

enum GitHubError: Error, Equatable {
    case unauthorized
    case rateLimited(until: Date)
    case noAccess
    case http(Int)
    case unreachable
    case decoding
}

struct HTTPResponse {
    var data: Data
    var status: Int
    /// Lowercased header names.
    var headers: [String: String]
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

struct URLSessionTransport: HTTPTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData // ETags are handled by GitHubClient
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await Self.session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return HTTPResponse(data: data, status: http?.statusCode ?? 0, headers: headers)
    }
}

protocol GitHubFetching: Sendable {
    func viewer(token: String) async throws -> String
    func recentRepos(token: String) async throws -> [Repo]
    func runs(repo: String, actor: String, token: String) async throws -> [Run]
    func failedStep(repo: String, runID: Int, token: String) async throws -> FailedStep?
}

/// Conditional-request cache, keyed by token + URL so one account's body is never served to another.
actor ETagCache {
    private var entries: [String: (etag: String, body: Data)] = [:]

    func entry(_ key: String) -> (etag: String, body: Data)? { entries[key] }

    func store(_ key: String, etag: String, body: Data) { entries[key] = (etag, body) }
}

final class GitHubClient: GitHubFetching {
    static let viewerURL = url("/user")
    static let reposURL = url("/user/repos", [
        "sort": "pushed", "per_page": "50", "affiliation": "owner,collaborator,organization_member"
    ])

    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    private let cache = ETagCache()

    init(transport: HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    static func runsURL(repo: String, actor: String) -> URL {
        url("/repos/\(repo)/actions/runs", ["actor": actor, "per_page": "20"])
    }

    static func jobsURL(repo: String, runID: Int) -> URL {
        url("/repos/\(repo)/actions/runs/\(runID)/jobs", ["filter": "latest"])
    }

    func viewer(token: String) async throws -> String {
        try decode(Viewer.self, try await get(Self.viewerURL, token: token)).login
    }

    func recentRepos(token: String) async throws -> [Repo] {
        try decode([Repo].self, try await get(Self.reposURL, token: token))
    }

    func runs(repo: String, actor: String, token: String) async throws -> [Run] {
        try decode(RunsPage.self, try await get(Self.runsURL(repo: repo, actor: actor), token: token)).workflowRuns
    }

    func failedStep(repo: String, runID: Int, token: String) async throws -> FailedStep? {
        FailureDetail.parse(try await get(Self.jobsURL(repo: repo, runID: runID), token: token))
    }

    private static func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let key = "\(token)\n\(url.absoluteString)"
        let cached = await cache.entry(key)
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let response = try await send(request)
        switch response.status {
        case 200..<300:
            if let etag = response.headers["etag"] { await cache.store(key, etag: etag, body: response.data) }
            return response.data
        case 304:
            guard let cached else { throw GitHubError.http(304) }
            return cached.body
        case 401:
            throw GitHubError.unauthorized
        case 403, 404, 429:
            if let limited = rateLimit(response) { throw limited }
            if response.status == 429 { throw GitHubError.rateLimited(until: now().addingTimeInterval(60)) }
            throw GitHubError.noAccess
        default:
            throw GitHubError.http(response.status)
        }
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GitHubError.unreachable
        }
    }

    /// Primary limit: `x-ratelimit-remaining: 0` + reset epoch. Secondary limit: `retry-after` seconds.
    private func rateLimit(_ response: HTTPResponse) -> GitHubError? {
        if response.headers["x-ratelimit-remaining"] == "0" {
            let reset = response.headers["x-ratelimit-reset"].flatMap(TimeInterval.init)
            return .rateLimited(until: reset.map { Date(timeIntervalSince1970: $0) } ?? now().addingTimeInterval(60))
        }
        if let retry = response.headers["retry-after"].flatMap(TimeInterval.init) {
            return .rateLimited(until: now().addingTimeInterval(retry))
        }
        return nil
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONCoding.decoder.decode(type, from: data)
        } catch {
            throw GitHubError.decoding
        }
    }
}
