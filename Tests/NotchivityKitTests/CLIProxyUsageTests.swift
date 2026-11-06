import Foundation
import Testing

@testable import NotchivityKit

private let proxyPayload = #"""
    {"accounts":[
      {"auth_index":"grok-account","provider":"xai","status":"ok","observed_at":"2026-11-07T08:00:00.123Z","stale":false,
       "windows":[{"id":"weekly","used_percent":37.5,"remaining_percent":62.5,"resets_at":null,"period_seconds":604800}]},
      {"auth_index":"codex-account","provider":"codex","status":"ok","observed_at":"2026-11-07T08:00:00Z","stale":false,
       "windows":[{"id":"weekly","used_percent":42,"resets_at":"2026-11-13T00:00:00Z","period_seconds":604800}]},
      {"auth_index":"claude-a","provider":"claude","status":"ok","observed_at":"2026-11-07T08:00:00Z","stale":false,
       "windows":[{"id":"session","used_percent":12,"resets_at":"2026-11-07T11:00:00Z","period_seconds":18000},
                  {"id":"weekly","used_percent":27,"resets_at":"2026-11-13T00:00:00Z","period_seconds":604800}]},
      {"auth_index":"claude-b","provider":"claude","status":"pending","observed_at":null,"stale":true,"refreshing":true,"windows":[]},
      {"auth_index":"other","provider":"gemini","status":"unsupported","stale":true,"windows":[]}
    ]}
    """#

@Suite struct CLIProxyUsageTests {
    private let source = CLIProxyUsageSource(baseURL: "https://proxy.example.com")

    @Test func existingConfigRemainsLocalAndPreservesSlackWhenAddingProxy() throws {
        var config = try JSONDecoder().decode(Config.self, from: Data(#"{"slackChannel":"sample","slackBotToken":"sample-token"}"#.utf8))
        #expect(!config.usesCLIProxy)
        config.cliProxyURL = "https://proxy.example.com"
        let data = try JSONEncoder().encode(config)
        let saved = try JSONDecoder().decode(Config.self, from: data)
        #expect(saved.usesCLIProxy)
        #expect(saved.slackChannel == "sample")
        #expect(saved.slackBotToken == "sample-token")
    }

    @Test func normalizesAccountsWithoutAveragingOrInventingMissingWindows() throws {
        let readings = try source.readings(from: Data(proxyPayload.utf8))
        #expect(readings.map(\.provider) == [.claude, .claude, .codex, .grok])
        #expect(Set(readings.map(\.id)).count == 4)
        #expect(readings[0].sessionPct == 12)
        #expect(readings[0].weeklyPct == 27)
        #expect(readings[0].sessionResetsAt == UsageParsing.epochSeconds("2026-11-07T11:00:00Z"))
        #expect(readings[1].sessionPct == nil)
        #expect(readings[1].weeklyPct == nil)
        #expect(readings[1].failure != nil)
        #expect(readings[2].windows == [.weekly])
        #expect(readings[2].primaryPct == 42)
        #expect(readings[3].weeklyPct == 37.5)
        #expect(readings[3].weeklyResetsAt == nil)
        #expect(readings[3].monthlyPct == nil)
        #expect(readings[3].observedAt == UsageParsing.epochSeconds("2026-11-07T08:00:00.123Z"))
    }

    @Test func staleAndExpiredWindowsRetainTheirValues() throws {
        let payload = proxyPayload.replacingOccurrences(of: "\"stale\":false", with: "\"stale\":true")
        let readings = try source.readings(from: Data(payload.utf8))
        #expect(readings[0].sessionPct == 12)
        #expect(readings[0].sessionResetsAt != nil)
        #expect(readings.allSatisfy { $0.failure != nil })
    }

    @Test func pendingOrUnavailableAccountKeepsItsLastObservation() throws {
        let cached = try #require(source.readings(from: Data(proxyPayload.utf8)).first)
        for status in ["pending", "unavailable"] {
            let payload = """
                {"accounts":[{"auth_index":"claude-a","provider":"claude","status":"\(status)",
                "observed_at":null,"stale":true,"windows":[]}]}
                """
            let reading = try #require(source.readings(from: Data(payload.utf8), previous: [cached]).first)
            #expect(reading.sessionPct == cached.sessionPct)
            #expect(reading.observedAt == cached.observedAt)
            #expect(reading.failure != nil)
        }
    }

    @Test func classifiesGenericWindowsByDuration() throws {
        let payload = proxyPayload.replacingOccurrences(of: "\"id\":\"weekly\"", with: "\"id\":\"primary\"")
        let readings = try source.readings(from: Data(payload.utf8))
        #expect(readings[2].sessionPct == nil)
        #expect(readings[2].weeklyPct == 42)
    }

    @Test func rejectsMalformedDataAndInvalidPercentages() {
        for payload in [
            "{}", "not json", proxyPayload.replacingOccurrences(of: "37.5", with: "101"),
            proxyPayload.replacingOccurrences(of: "37.5", with: "null"),
            proxyPayload.replacingOccurrences(of: "2026-11-07T08:00:00Z", with: "bad-date"),
        ] {
            #expect(throws: UsageError.self) { try source.readings(from: Data(payload.utf8)) }
        }
    }

    @Test func emptyResponseRemovesOldAccountsAndIdentityIncludesProxy() throws {
        let cached = try source.readings(from: Data(proxyPayload.utf8))
        #expect(try source.readings(from: Data(#"{"accounts":[]}"#.utf8), previous: cached).isEmpty)
        let other = CLIProxyUsageSource(baseURL: "https://other.example.com")
        #expect(try other.readings(from: Data(proxyPayload.utf8)).first?.id != cached.first?.id)
        let trailingSlash = CLIProxyUsageSource(baseURL: " https://proxy.example.com/ ")
        #expect(try trailingSlash.readings(from: Data(proxyPayload.utf8)).first?.id == cached.first?.id)
    }

    @Test func validatesBaseURLAndPreservesDeploymentPath() throws {
        #expect(
            try CLIProxyUsageSource.endpoint(for: " https://proxy.example.com/subpath/ ").absoluteString
                == "https://proxy.example.com/subpath/v8/management/usage-limits")
        for url in [
            "", "proxy.example.com", "file:///tmp/config", "https://user:secret@proxy.example.com", "https://proxy.example.com?token=secret",
            "https://proxy.example.com#fragment",
        ] {
            #expect(throws: UsageError.self) { try CLIProxyUsageSource.endpoint(for: url) }
        }
    }

    @Test func blankURLUsesLocalSourcesAndInvalidConfiguredURLNeverDoes() async {
        let reader = UsageReader(localSources: [LocalSource()])
        for url in [nil, "", "  \n"] as [String?] {
            var config = Config()
            config.cliProxyURL = url
            #expect(await reader.fetch(previous: [], config: config).map(\.id) == ["local"])
        }
        var config = Config()
        config.cliProxyURL = "not-a-url"
        let readings = await reader.fetch(previous: [], config: config)
        #expect(readings.count == 1)
        #expect(readings[0].id.hasPrefix("cliproxy:"))
        #expect(readings[0].failure != nil)
    }

    @Test func proxySetupDoesNotRequireLocalClaudeSignIn() async throws {
        var config = Config()
        config.cliProxyURL = "https://proxy.example.com"
        let readings = try source.readings(from: Data(proxyPayload.utf8)).filter { $0.provider != .claude }
        let checks = await SetupDoctor().quotaChecks(usage: readings, config: config)
        #expect(checks.count == 2)
        #expect(checks.allSatisfy { $0.status == .pass })
        #expect(SetupDoctor().proxyChecks([]).first?.status == .warn)
        let failed = await CLIProxyUsageSource(baseURL: "invalid").fetch(previous: [])
        #expect(SetupDoctor().proxyChecks(failed).first?.blocking == true)
    }

    private struct LocalSource: UsageSource {
        let provider = UsageProvider.claude
        func fetch(previous: [AccountUsage]) async -> [AccountUsage] { [AccountUsage(id: "local", label: "local")] }
    }
}

@Suite struct CLIProxyRequestTests {
    private func source(path: String) -> CLIProxyUsageSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProxyProtocol.self]
        return CLIProxyUsageSource(
            baseURL: "https://proxy.example.com/\(path)", session: URLSession(configuration: configuration), token: { "scoped-test-token" })
    }

    @Test func sendsScopedBearerTokenAndDecodesResponse() async {
        let readings = await source(path: "good").fetch(previous: [])
        #expect(readings.count == 4)
        #expect(readings[0].failure == nil)
    }

    @Test func refusesRedirectsInsteadOfForwardingTheToken() async {
        let readings = await source(path: "redirect").fetch(previous: [])
        #expect(readings.first?.error == "CLI proxy HTTP 302")
    }

    @Test func requestFailuresPreserveOnlyThisProxysAccounts() async throws {
        for path in ["unauthorized", "malformed", "offline"] {
            let source = source(path: path)
            let cached = try source.readings(from: Data(proxyPayload.utf8))
            let local = AccountUsage(id: "local", label: "local", sessionPct: 90)
            let readings = await source.fetch(previous: cached + [local])
            #expect(readings.map(\.id) == cached.map(\.id))
            #expect(readings[0].sessionPct == 12)
            #expect(readings.allSatisfy { $0.failure != nil })
            #expect(readings.allSatisfy { $0.failure?.fix == nil })
            #expect(!readings.contains { $0.error?.contains("sensitive") == true })
            let firstFailure = await source.fetch(previous: [local])
            #expect(firstFailure.count == 1)
            #expect(firstFailure[0].id.hasSuffix(":connection"))
        }
    }

    @Test func missingOrUnreadableTokenDoesNotMakeRequest() async {
        let missing = CLIProxyUsageSource(baseURL: "https://proxy.example.com", token: { "" })
        #expect(await missing.fetch(previous: []).first?.error == "Set the CLI proxy read-only token in Settings")
        let unreadable = CLIProxyUsageSource(baseURL: "https://proxy.example.com", token: { throw UsageError.other("Keychain locked") })
        #expect(await unreadable.fetch(previous: []).first?.error == "Keychain locked")
    }

    private final class ProxyProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer scoped-test-token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.url?.path.hasSuffix("/v8/management/usage-limits") == true)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            let path = request.url!.path
            if path.hasPrefix("/redirect/") {
                let target = URL(string: "https://other.example.com/redirect-target")!
                let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            #expect(!path.contains("redirect-target"))
            if path.hasPrefix("/offline/") {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let status = path.hasPrefix("/unauthorized/") ? 401 : 200
            let body = path.hasPrefix("/good/") ? proxyPayload : "sensitive upstream response"
            client?.urlProtocol(
                self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
