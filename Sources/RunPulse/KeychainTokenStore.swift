import Foundation
import MenuBarKit

typealias KeychainError = SecurityCLIKeychainError

/// Blocking by design; callers run it off the main actor.
protocol KeychainTokenStoring: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

struct KeychainTokenStore: KeychainTokenStoring {
    var service = "RunPulse"
    var account = "pat"

    private var keychain: SecurityCLIKeychain { SecurityCLIKeychain(service: service, account: account) }

    func read() throws -> String? { try keychain.read() }
    func save(_ token: String) throws { try keychain.save(token) }
    func delete() throws { try keychain.delete() }
}
