import Foundation
import MenuBarKit

struct AppConfig: Codable, Equatable {
    static let lookbackChoices = [1, 3, 7, 14]

    var lookbackDays = 7
    var muted: [String] = []
    var notificationsEnabled = true

    private enum CodingKeys: String, CodingKey {
        case lookbackDays, muted, notificationsEnabled
    }
}

// In an extension so the default initializer is kept.
extension AppConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = AppConfig()
        lookbackDays = try c.decodeIfPresent(Int.self, forKey: .lookbackDays) ?? base.lookbackDays
        muted = try c.decodeIfPresent([String].self, forKey: .muted) ?? base.muted
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)
            ?? base.notificationsEnabled
    }
}

extension AppConfig: DefaultInitializable {}
typealias AppConfigStore = JSONDefaultsStore<AppConfig>
