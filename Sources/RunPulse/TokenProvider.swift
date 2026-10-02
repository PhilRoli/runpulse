import Foundation

enum TokenSource: Equatable {
    case gh, keychain
}

struct Token: Equatable {
    var value: String
    var source: TokenSource
}

enum TokenError: Error, Equatable {
    case missing
}

/// Blocking by design (it may spawn `gh`); callers run it off the main actor.
protocol TokenProviding: AnyObject, Sendable {
    func token() throws -> Token
    func invalidate()
}

protocol ProcessRunning: Sendable {
    /// nil when the executable doesn't exist or can't be launched.
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)?
}

struct SystemProcessRunner: ProcessRunning {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }
}

/// GUI apps don't inherit the shell PATH, so look for gh in the standard Homebrew prefixes.
struct GhCLITokenSource: Sendable {
    static let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    var runner: ProcessRunning = SystemProcessRunner()

    func token() -> String? {
        for path in Self.paths {
            guard let result = runner.run(path, ["auth", "token"]) else { continue }
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.status == 0, !value.isEmpty { return value }
        }
        return nil
    }
}

/// gh CLI first, then the PAT saved in Preferences; cached until `invalidate()` (e.g. after a 401).
final class CompositeTokenProvider: TokenProviding, @unchecked Sendable {
    private let gh: GhCLITokenSource
    private let keychain: KeychainTokenStoring
    private let lock = NSLock()
    private var cached: Token?

    init(gh: GhCLITokenSource = GhCLITokenSource(), keychain: KeychainTokenStoring) {
        self.gh = gh
        self.keychain = keychain
    }

    func token() throws -> Token {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let resolved: Token
        if let value = gh.token() {
            resolved = Token(value: value, source: .gh)
        } else if let value = try? keychain.read() {
            resolved = Token(value: value, source: .keychain)
        } else {
            throw TokenError.missing
        }
        cached = resolved
        return resolved
    }

    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}
