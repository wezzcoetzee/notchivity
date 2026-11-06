import Foundation

public struct CLIProxyUsageSource {
    private let baseURL: String
    private let session: URLSession
    private let token: () throws -> String

    public init(baseURL: String, session: URLSession = .shared, token: @escaping () throws -> String = CLIProxyToken.load) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }

    public static func endpoint(for baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
            let url = components.url
        else { throw UsageError.other("Enter an HTTP or HTTPS CLI proxy base URL without credentials, query, or fragment") }
        return url.appendingPathComponent("v8/management/usage-limits")
    }

    public func fetch(previous: [AccountUsage]) async -> [AccountUsage] {
        do {
            let endpoint = try Self.endpoint(for: baseURL)
            let secret = try token().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secret.isEmpty else { throw UsageError.other("Set the CLI proxy read-only token in Settings") }
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request, delegate: NoRedirects())
            guard let response = response as? HTTPURLResponse else { throw UsageError.other("Unreadable CLI proxy response") }
            guard response.statusCode == 200 else {
                throw UsageError.other("CLI proxy HTTP \(response.statusCode)")
            }
            return try readings(from: data, previous: previous)
        } catch {
            let failure = error as? UsageError ?? .other("CLI proxy request failed")
            let cached = previous.filter { $0.id.hasPrefix(accountPrefix) }
            if cached.isEmpty {
                return [AccountUsage(id: accountPrefix + "connection", label: "CLI proxy", failure: failure)]
            }
            return cached.map {
                var stale = $0
                stale.failure = failure
                return stale
            }
        }
    }

    private var accountPrefix: String {
        let url = (try? Self.endpoint(for: baseURL))?.absoluteString ?? "invalid"
        return "cliproxy:\(url):"
    }

    func readings(from data: Data, previous: [AccountUsage] = []) throws -> [AccountUsage] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: Response
        do { response = try decoder.decode(Response.self, from: data) } catch { throw UsageError.other("Unreadable CLI proxy response") }
        var seen: Set<String> = []
        return try response.accounts.compactMap { account in
            let provider: UsageProvider
            switch account.provider {
            case "claude": provider = .claude
            case "codex": provider = .codex
            case "xai": provider = .grok
            default: return nil
            }
            guard account.status != "unsupported" else { return nil }
            let id = accountPrefix + provider.rawValue + ":" + account.authIndex
            guard !account.authIndex.isEmpty, seen.insert(id).inserted else { throw UsageError.other("Unreadable CLI proxy accounts") }
            var reading = AccountUsage(id: id, label: "\(provider.name) \(account.authIndex.prefix(8))", provider: provider)
            if account.windows.isEmpty, account.status != "ok", let cached = previous.first(where: { $0.id == id }) {
                reading = cached
            }
            if let observed = account.observedAt {
                guard let timestamp = UsageParsing.epochSeconds(observed) else { throw UsageError.other("Unreadable CLI proxy timestamp") }
                reading.observedAt = timestamp
            }
            for window in account.windows {
                guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else {
                    throw UsageError.other("Unreadable CLI proxy percentage")
                }
                let reset = window.resetsAt.flatMap { UsageParsing.epochSeconds($0) }
                if window.resetsAt != nil, reset == nil { throw UsageError.other("Unreadable CLI proxy reset time") }
                switch window.id {
                case "session": reading.sessionPct = window.usedPercent; reading.sessionResetsAt = reset
                case "weekly": reading.weeklyPct = window.usedPercent; reading.weeklyResetsAt = reset
                case "primary", "secondary":
                    if window.periodSeconds == 18000 { reading.sessionPct = window.usedPercent; reading.sessionResetsAt = reset }
                    if window.periodSeconds == 604800 { reading.weeklyPct = window.usedPercent; reading.weeklyResetsAt = reset }
                default: break
                }
            }
            if account.status == "pending" {
                reading.failure = .other("CLI proxy is refreshing usage")
            } else if account.status != "ok" {
                reading.failure = .other("CLI proxy usage unavailable")
            } else if account.stale {
                reading.failure = .other("CLI proxy usage is stale")
            } else if reading.sessionPct == nil && reading.weeklyPct == nil {
                reading.failure = .other("CLI proxy has no supported quota windows")
            } else {
                reading.failure = nil
            }
            return reading
        }.sorted { lhs, rhs in
            let providers = UsageProvider.allCases
            let left = providers.firstIndex(of: lhs.provider)!
            let right = providers.firstIndex(of: rhs.provider)!
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    private struct Response: Decodable {
        let accounts: [Account]
    }

    private struct Account: Decodable {
        let authIndex: String
        let provider: String
        let status: String
        let observedAt: String?
        let stale: Bool
        let windows: [Window]
    }

    private struct Window: Decodable {
        let id: String
        let usedPercent: Double
        let resetsAt: String?
        let periodSeconds: Int?
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
