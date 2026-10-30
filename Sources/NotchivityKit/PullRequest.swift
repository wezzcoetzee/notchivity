import Foundation

/// The same buckets pr-tracker used, in display order.
public enum PRCategory: String, Codable, CaseIterable {
    case failing, needsAction, ready, awaitingReview

    public var title: String {
        switch self {
        case .failing: return "Failing"
        case .needsAction: return "Needs action"
        case .ready: return "Ready"
        case .awaitingReview: return "Awaiting review"
        }
    }
}

public enum CIState: String, Codable { case success, failure, pending, none }

public struct PullRequest: Codable, Equatable, Identifiable {
    public var repo: String
    public var number: Int
    public var title: String
    public var url: URL
    public var branch: String
    public var draft: Bool
    public var updatedAt: Date
    public var ci: CIState
    public var conflicts: Bool
    public var unresolvedThreads: Int
    public var approvals: Int
    public var changesRequested: Bool
    /// True once someone other than a bot or the author has reviewed.
    public var reviewedByHuman: Bool

    public init(repo: String, number: Int, title: String, url: URL, branch: String, draft: Bool = false,
                updatedAt: Date, ci: CIState, conflicts: Bool = false, unresolvedThreads: Int = 0,
                approvals: Int = 0, changesRequested: Bool = false, reviewedByHuman: Bool = false) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.branch = branch
        self.draft = draft
        self.updatedAt = updatedAt
        self.ci = ci
        self.conflicts = conflicts
        self.unresolvedThreads = unresolvedThreads
        self.approvals = approvals
        self.changesRequested = changesRequested
        self.reviewedByHuman = reviewedByHuman
    }

    public var id: String { "\(repo)#\(number)" }
    public var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    public var shortRef: String { "\(repoName)#\(number)" }

    public var category: PRCategory {
        if ci == .failure || conflicts { return .failing }
        if unresolvedThreads > 0 || changesRequested { return .needsAction }
        if approvals > 0 && !draft && ci != .pending { return .ready }
        return reviewedByHuman ? .needsAction : .awaitingReview
    }

    /// Short status words for the row's right-hand column, most urgent first.
    public var flags: [(text: String, tone: Tone)] {
        var out: [(String, Tone)] = []
        if conflicts { out.append(("conflicts", .bad)) }
        if ci == .failure { out.append(("CI failed", .bad)) }
        if ci == .pending { out.append(("CI running", .dim)) }
        if changesRequested { out.append(("changes requested", .warn)) }
        if unresolvedThreads > 0 { out.append((plural(unresolvedThreads, "thread"), .warn)) }
        if approvals > 0 { out.append(("approved", .good)) }
        if ci == .success && !conflicts { out.append(("CI ✓", .good)) }
        if draft { out.append(("draft", .dim)) }
        return out
    }
}

public enum Tone { case bad, warn, good, dim, info }

public func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

// MARK: - GraphQL shape

extension PullRequest {
    public static let query = """
    query($q: String!) {
      viewer { login }
      search(query: $q, type: ISSUE, first: 100) {
        nodes {
          ... on PullRequest {
            number title url isDraft mergeable reviewDecision updatedAt headRefName
            repository { nameWithOwner }
            reviewThreads(first: 100) { nodes { isResolved } }
            reviews(last: 50) { nodes { state author { login } } }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
    }
    """

    struct Response: Decodable {
        struct Body: Decodable {
            struct Viewer: Decodable { let login: String }
            struct Search: Decodable { let nodes: [Raw] }
            let viewer: Viewer
            let search: Search
        }
        struct GQLError: Decodable { let message: String }
        let data: Body?
        let errors: [GQLError]?
    }

    struct Raw: Decodable {
        struct Repo: Decodable { let nameWithOwner: String }
        struct Thread: Decodable { let isResolved: Bool }
        struct Review: Decodable {
            struct Author: Decodable { let login: String }
            let state: String
            let author: Author?
        }
        struct Commit: Decodable {
            struct Inner: Decodable {
                struct Rollup: Decodable { let state: String }
                let statusCheckRollup: Rollup?
            }
            let commit: Inner
        }
        struct Nodes<T: Decodable>: Decodable { let nodes: [T] }

        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let mergeable: String
        let reviewDecision: String?
        let updatedAt: Date
        let headRefName: String
        let repository: Repo
        let reviewThreads: Nodes<Thread>
        let reviews: Nodes<Review>
        let commits: Nodes<Commit>
    }

    static let botSuffixes = ["[bot]", "copilot-pull-request-reviewer"]

    init(raw: Raw, me: String) {
        let humans = raw.reviews.nodes.filter { review in
            guard let login = review.author?.login, login != me else { return false }
            return !Self.botSuffixes.contains { login.hasSuffix($0) }
        }
        let ci: CIState
        switch raw.commits.nodes.first?.commit.statusCheckRollup?.state {
        case "SUCCESS": ci = .success
        case "FAILURE", "ERROR": ci = .failure
        case "PENDING", "EXPECTED": ci = .pending
        default: ci = .none
        }
        self.init(repo: raw.repository.nameWithOwner, number: raw.number, title: raw.title, url: raw.url,
                  branch: raw.headRefName, draft: raw.isDraft, updatedAt: raw.updatedAt, ci: ci,
                  conflicts: raw.mergeable == "CONFLICTING",
                  unresolvedThreads: raw.reviewThreads.nodes.filter { !$0.isResolved }.count,
                  approvals: Set(humans.filter { $0.state == "APPROVED" }.compactMap { $0.author?.login }).count,
                  changesRequested: raw.reviewDecision == "CHANGES_REQUESTED",
                  reviewedByHuman: !humans.isEmpty)
    }

    /// Decodes a `gh api graphql` response body.
    public static func decode(_ data: Data) throws -> (me: String, prs: [PullRequest]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(Response.self, from: data)
        guard let body = response.data else {
            throw ShellError(description: response.errors?.map(\.message).joined(separator: "; ") ?? "empty response")
        }
        let prs = body.search.nodes.map { PullRequest(raw: $0, me: body.viewer.login) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return (body.viewer.login, prs)
    }
}
