import Foundation

/// Reads each signed-in account's OAuth token from the Keychain and polls the usage
/// endpoint behind Claude Code's `/usage`. Token refresh belongs to Claude Code / T3 Code;
/// a 401 here means neither has run for a while.
public enum UsageError: Error, CustomStringConvertible, Equatable, Codable {
    case keychain
    case http(Int)
    case unreadable
    case other(String)

    public var description: String {
        switch self {
        case .keychain: return "Keychain item not readable, click Always Allow in the macOS prompt"
        case .http(401): return "token expired, open Claude Code to refresh it"
        case .http(429): return "rate limited, is another usage poller running?"
        case .http(let status): return "usage endpoint HTTP \(status)"
        case .unreadable: return "unreadable usage response"
        case .other(let message): return message
        }
    }

    /// What the setup checklist can offer for this failure.
    public var fix: SetupCheck.Fix? {
        switch self {
        case .keychain: return .retry
        case .http(401): return .openClaudeCode
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
                stale.failure = error as? UsageError ?? .other("\(error)")
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
        return AccountUsage.parse(json, id: account.id, label: account.label)
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
