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
    var timeout: TimeInterval = 10

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
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
    /// Serialises resolution (which may spawn `gh`); never taken by `invalidate()`.
    private let resolveLock = NSLock()
    /// Guards `cached` and `generation`; only held briefly.
    private let cacheLock = NSLock()
    private var cached: Token?
    private var generation = 0

    init(gh: GhCLITokenSource = GhCLITokenSource(), keychain: KeychainTokenStoring) {
        self.gh = gh
        self.keychain = keychain
    }

    func token() throws -> Token {
        if let hit = cacheLock.withLock({ cached }) { return hit }
        resolveLock.lock()
        defer { resolveLock.unlock() }
        let start: (Token?, Int) = cacheLock.withLock { (cached, generation) }
        if let hit = start.0 { return hit }
        let resolved: Token
        if let value = gh.token() {
            resolved = Token(value: value, source: .gh)
        } else if let value = try? keychain.read() {
            resolved = Token(value: value, source: .keychain)
        } else {
            throw TokenError.missing
        }
        cacheLock.withLock { if generation == start.1 { cached = resolved } }
        return resolved
    }

    func invalidate() {
        cacheLock.withLock {
            cached = nil
            generation += 1
        }
    }
}
