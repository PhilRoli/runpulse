import Foundation

enum Glyph: Equatable {
    case queued, running, success, failure, cancelled, skipped
}

enum Timing: Equatable {
    case queued
    case elapsed(since: Date)
    case finished(at: Date, duration: TimeInterval)
    case cancelled(at: Date)
}

struct RunRow: Equatable {
    var glyph: Glyph
    var title: String
    var branch: String
    var timing: Timing
    var detail: String?
    var url: URL
}

enum MenuRow: Equatable {
    case section(String)
    case run(RunRow)
    case message(String)
    case separator
    case openActions([String])
}

/// Value-type description of the dropdown; StatusBarController only renders it.
enum MenuModel {
    static func rows(state: PollerState, timeZone: TimeZone = .current) -> [MenuRow] {
        if let message = blockingMessage(state.status, timeZone: timeZone) { return [.message(message)] }
        var rows: [MenuRow] = []
        if state.status == .stale { rows.append(.message("⚠︎ stale")) }
        if !state.running.isEmpty {
            rows.append(.section("Running"))
            rows += state.running.map { .run(row($0, detail: nil)) }
            rows.append(.separator)
        }
        rows.append(.section("Recent"))
        if state.recent.isEmpty {
            rows.append(.message("No recent runs"))
        } else {
            rows += state.recent.map { .run(row($0, detail: state.failures[$0.key]?.label)) }
        }
        if !state.activeRepos.isEmpty {
            rows += [.separator, .openActions(state.activeRepos)]
        }
        return rows
    }

    static func row(_ run: Run, detail: String?) -> RunRow {
        let started = run.startedAt ?? run.createdAt
        let finished = Timing.finished(at: run.updatedAt, duration: run.updatedAt.timeIntervalSince(started))
        let glyph: Glyph
        let timing: Timing
        switch run.state {
        case .queued: (glyph, timing) = (.queued, .queued)
        case .inProgress: (glyph, timing) = (.running, .elapsed(since: started))
        case .success: (glyph, timing) = (.success, finished)
        case .failure: (glyph, timing) = (.failure, finished)
        case .cancelled: (glyph, timing) = (.cancelled, .cancelled(at: run.updatedAt))
        case .skipped, .other: (glyph, timing) = (.skipped, finished)
        }
        return RunRow(glyph: glyph, title: "\(run.repoName) · \(run.workflow)", branch: run.branch ?? "",
                      timing: timing, detail: run.state == .failure ? detail : nil, url: run.htmlURL)
    }

    static func timingText(_ timing: Timing, now: Date) -> String {
        switch timing {
        case .queued: return "queued"
        case .elapsed(let since): return Format.clock(now.timeIntervalSince(since))
        case let .finished(at, duration): return "\(Format.age(since: at, now: now)) · \(Format.duration(duration))"
        case .cancelled(let at): return "\(Format.age(since: at, now: now)) · cancelled"
        }
    }

    static func actionsURL(_ repo: String) -> URL {
        URL(string: "https://github.com/\(repo)/actions")!
    }

    private static func blockingMessage(_ status: PollStatus, timeZone: TimeZone) -> String? {
        switch status {
        case .loading: return "Connecting…"
        case .authMissing: return "⚠︎ Run gh auth login"
        case .authFailed: return "⚠︎ Token rejected"
        case .unreachable: return "⚠︎ GitHub unreachable"
        case .rateLimited(let until): return "⚠︎ Rate limited until \(Format.time(until, timeZone: timeZone))"
        case .ok, .stale: return nil
        }
    }
}
