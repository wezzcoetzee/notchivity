import Foundation

/// Lists the current user's open PRs through the `gh` CLI so auth and the corporate
/// proxy are gh's problem, not ours.
public struct PRFetcher {
    public init() {}

    public func fetch() async throws -> (me: String, prs: [PullRequest]) {
        let data = try await Shell.run(Shell.which("gh"), [
            "api", "graphql",
            "-F", "q=is:pr is:open author:@me archived:false",
            "-f", "query=\(PullRequest.query)",
        ])
        return try PullRequest.decode(data)
    }

    /// Whether a PR that left the open set was merged (true) or closed (false).
    public func wasMerged(_ pr: PullRequest) async -> Bool {
        let parts = pr.repo.split(separator: "/")
        guard parts.count == 2 else { return false }
        let data = try? await Shell.run(Shell.which("gh"), [
            "api", "repos/\(pr.repo)/pulls/\(pr.number)", "--jq", ".merged",
        ])
        return data.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "true" } ?? false
    }
}
