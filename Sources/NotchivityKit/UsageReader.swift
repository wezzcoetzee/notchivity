import Foundation

public struct UsageReader {
    private let localSources: [any UsageSource]

    public init(localSources: [any UsageSource] = [UsageFetcher(), CodexUsageSource(), GrokUsageSource()]) {
        self.localSources = localSources
    }

    public func fetch(previous: [AccountUsage], config: Config = .load()) async -> [AccountUsage] {
        if config.usesCLIProxy {
            return await CLIProxyUsageSource(baseURL: config.cliProxyURL ?? "").fetch(previous: previous)
        }
        var readings: [AccountUsage] = []
        for source in localSources { readings += await source.fetch(previous: previous) }
        return readings
    }
}
