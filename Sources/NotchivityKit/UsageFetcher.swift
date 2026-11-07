import Foundation

/// Reads each signed-in account's OAuth token from the Keychain and polls the usage
/// endpoint behind Claude Code's `/usage`. Token refresh belongs to Claude Code / T3 Code;
/// a 401 here means neither has run for a while.
public enum UsageError: Error, CustomStringConvertible, Equatable, Codable {
    case keychain
    case http(Int)
    case unreachable

    /// The one mapping from a thrown error, shared by the poller and `--doctor`.
    public init(_ error: Error) {
        if let usage = error as? UsageError {
            self = usage
        } else {
            self = error is URLError ? .unreachable : .other("usage fetch failed")
        }
    }
    case unreadable
    case other(String)

    public var description: String {
        switch self {
        case .keychain: return "keychain item not readable, click Always Allow in the macOS prompt"
        case .http(401): return "token expired, open Claude Code to refresh it"
        case .http(429): return "rate limited, is another usage poller running?"
        case .http(let status): return "usage endpoint HTTP \(status)"
        case .unreachable: return "usage endpoint unreachable"
        case .unreadable: return "unreadable usage response"
        case .other(let message): return message
        }
    }

    /// Failures that clear on their own or by a fix elsewhere (an expired token refreshed by
    /// Claude Code, the network coming back), so a quick retry can pick up the recovery.
    /// Not a rate limit, and not the keychain, whose retry would raise the macOS prompt again.
    public var isTransient: Bool {
        switch self {
        case .http(401), .unreachable: return true
        case .http(let status): return status >= 500
        default: return false
        }
    }

    /// A few words for the notch's narrow usage column; `description` is the full sentence for
    /// setup, `--doctor` and the tooltip.
    public var short: String {
        switch self {
        case .keychain: return "keychain not readable"
        case .http(401): return "token expired"
        case .http(429): return "rate limited"
        case .http(let status): return "usage endpoint HTTP \(status)"
        case .unreachable: return "unreachable"
        case .unreadable: return "unreadable usage response"
        case .other(let message): return message
        }
    }

    /// What the setup checklist can offer for this failure.
    public var fix: SetupCheck.Fix? {
        switch self {
        case .keychain: return .retry
        case .http(401): return .openClaudeCode()
        case .unreachable: return .retry
        case .http(let status) where status >= 500: return .retry
        default: return nil
        }
    }
}

public struct UsageFetcher: UsageSource {
    public let provider = UsageProvider.claude
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init() {}

    /// Polls every discovered account. A failing account keeps its previous reading and
    /// carries the error so the UI can say so.
    public func fetch(previous: [AccountUsage]) async -> [AccountUsage] {
        let accounts = ClaudeAccountDiscovery.discover()
        var results: [AccountUsage] = []
        for account in accounts {
            do {
                results.append(try await usage(for: account))
            } catch {
                var stale = previous.first { $0.id == account.id } ?? AccountUsage(id: account.id, label: account.label)
                stale.failure = UsageError(error)
                stale.configDirectory = account.configDirectory
                results.append(stale)
            }
        }
        return results
    }

    public func usage(for account: ClaudeAccount) async throws -> AccountUsage {
        let token = try await accessToken(service: account.keychainService)
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UsageError.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageError.unreadable }
        var usage = AccountUsage.parse(json, id: account.id, label: account.label)
        usage.configDirectory = account.configDirectory
        return usage
    }

    func accessToken(service: String) async throws -> String {
        let data: Data
        do {
            data = try await Shell.run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"])
        } catch {
            throw UsageError.keychain
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let oauth = root?["claudeAiOauth"] as? [String: Any] ?? root
        guard let token = oauth?["accessToken"] as? String else { throw UsageError.keychain }
        return token
    }
}
