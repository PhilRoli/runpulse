import Foundation

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct Repo: Decodable, Equatable, Hashable {
    var fullName: String
    var pushedAt: Date?
    var htmlURL: URL
    var archived: Bool

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name", pushedAt = "pushed_at", htmlURL = "html_url", archived
    }
}

enum RunState: Equatable {
    case queued, inProgress, success, failure, cancelled, skipped, other

    var isCompleted: Bool {
        switch self {
        case .queued, .inProgress: return false
        case .success, .failure, .cancelled, .skipped, .other: return true
        }
    }
}

struct Run: Decodable, Equatable, Identifiable {
    var id: Int
    var attempt: Int
    var repo: String
    var workflow: String
    var event: String
    var branch: String?
    var title: String
    var status: String
    var conclusion: String?
    var createdAt: Date
    var startedAt: Date?
    var updatedAt: Date
    var htmlURL: URL

    static let failureConclusions: Set<String> = ["failure", "timed_out", "startup_failure"]

    var state: RunState {
        switch status {
        case "completed":
            switch conclusion ?? "" {
            case "success": return .success
            case let value where Self.failureConclusions.contains(value): return .failure
            case "cancelled": return .cancelled
            case "skipped", "neutral": return .skipped
            default: return .other
            }
        case "in_progress": return .inProgress
        default: return .queued // queued, waiting, pending, requested
        }
    }

    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    /// Identity of one attempt; a re-run keeps `id` but bumps `attempt`.
    var key: String { "\(id)#\(attempt)" }
}

// In an extension so the memberwise initializer is kept.
extension Run {
    private enum Keys: String, CodingKey {
        case id, name, event, status, conclusion, repository
        case attempt = "run_attempt", headBranch = "head_branch", displayTitle = "display_title"
        case createdAt = "created_at", runStartedAt = "run_started_at", updatedAt = "updated_at", htmlURL = "html_url"
    }

    private enum RepositoryKeys: String, CodingKey {
        case fullName = "full_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        attempt = try c.decodeIfPresent(Int.self, forKey: .attempt) ?? 1
        workflow = try c.decodeIfPresent(String.self, forKey: .name) ?? "Workflow"
        event = try c.decode(String.self, forKey: .event)
        branch = try c.decodeIfPresent(String.self, forKey: .headBranch)
        title = try c.decodeIfPresent(String.self, forKey: .displayTitle) ?? ""
        status = try c.decode(String.self, forKey: .status)
        conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .runStartedAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        repo = try c.nestedContainer(keyedBy: RepositoryKeys.self, forKey: .repository)
            .decode(String.self, forKey: .fullName)
    }
}

struct RunsPage: Decodable {
    var workflowRuns: [Run]

    private enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct Viewer: Decodable {
    var login: String
}

struct FailedStep: Equatable {
    var job: String
    var step: String?

    var label: String { step.map { "\(job) › \($0)" } ?? job }
}
