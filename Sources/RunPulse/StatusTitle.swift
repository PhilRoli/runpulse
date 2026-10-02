import Foundation

enum StatusTint: Equatable {
    case normal, green, red, orange
}

struct TitleInput: Equatable {
    var status: PollStatus
    var runningCount: Int
    var lastSuccessAt: Date?
    /// A run failed and the menu hasn't been opened since.
    var failureUnacknowledged: Bool
}

struct StatusTitle: Equatable {
    static let successVisible: TimeInterval = 300

    var text: String
    var tint: StatusTint

    static func make(_ input: TitleInput, now: Date) -> StatusTitle {
        var title: StatusTitle
        if input.status == .authMissing || input.status == .authFailed {
            title = StatusTitle(text: "!", tint: .orange)
        } else if input.runningCount > 0 {
            title = StatusTitle(text: "\(input.runningCount)", tint: .normal)
        } else if input.failureUnacknowledged {
            title = StatusTitle(text: "✗", tint: .red)
        } else if let success = input.lastSuccessAt, now.timeIntervalSince(success) < successVisible {
            title = StatusTitle(text: "✓", tint: .green)
        } else {
            title = StatusTitle(text: "", tint: .normal)
        }
        if input.status == .stale { title.text += "*" }
        return title
    }
}
