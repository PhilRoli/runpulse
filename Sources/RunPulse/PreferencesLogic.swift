import Foundation

enum TokenInput: Equatable {
    case keep
    case set(String)
}

struct RepoRow: Equatable {
    var name: String
    var enabled: Bool
    var noAccess: Bool
}

/// Pure rules behind the Preferences window, kept out of AppKit so they can be tested.
enum PreferencesLogic {
    /// An empty field means "unchanged": tabbing through must never delete a saved token.
    static func tokenInput(_ raw: String) -> TokenInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .keep : .set(trimmed)
    }

    static func accountLabel(_ state: PollerState) -> String {
        guard let account = state.account else { return "Not signed in" }
        switch state.tokenSource {
        case .gh?: return "\(account) · gh CLI"
        case .keychain?: return "\(account) · token"
        case nil: return account
        }
    }

    /// Muted repos stay listed even after they leave the lookback window, so they can be unmuted.
    static func repoRows(discovered: [String], muted: [String], noAccess: Set<String>) -> [RepoRow] {
        let mutedSet = Set(muted)
        return Set(discovered).union(mutedSet).sorted().map {
            RepoRow(name: $0, enabled: !mutedSet.contains($0), noAccess: noAccess.contains($0))
        }
    }

    static func muted(_ muted: [String], repo: String, enabled: Bool) -> [String] {
        var set = Set(muted)
        if enabled { set.remove(repo) } else { set.insert(repo) }
        return set.sorted()
    }
}
