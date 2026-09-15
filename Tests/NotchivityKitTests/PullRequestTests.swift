import Foundation
import Testing
@testable import NotchivityKit

private func pr(number: Int = 1, ci: CIState = .success, conflicts: Bool = false, threads: Int = 0, approvals: Int = 0,
                changesRequested: Bool = false, draft: Bool = false, human: Bool = false) -> PullRequest {
    PullRequest(repo: "org/repo", number: number, title: "t", url: URL(string: "https://x/\(number)")!, branch: "b",
                draft: draft, updatedAt: .now, ci: ci, conflicts: conflicts, unresolvedThreads: threads,
                approvals: approvals, changesRequested: changesRequested, reviewedByHuman: human || approvals > 0)
}

@Suite struct PullRequestTests {
    @Test func categoriesMatchPrTracker() {
        #expect(pr(ci: .failure).category == .failing)
        #expect(pr(conflicts: true, approvals: 2).category == .failing)
        #expect(pr(threads: 1, approvals: 1).category == .needsAction)
        #expect(pr(changesRequested: true).category == .needsAction)
        #expect(pr(approvals: 1).category == .ready)
        #expect(pr(ci: .pending, approvals: 1).category == .needsAction)
        #expect(pr(approvals: 1, draft: true).category == .needsAction)
        #expect(pr(human: true).category == .needsAction)
        #expect(pr().category == .awaitingReview)
    }

    @Test func decodesGraphQLAndFiltersBotReviews() throws {
        let json = """
        {"data":{"viewer":{"login":"me"},"search":{"nodes":[{"number":7,"title":"T","url":"https://github.com/o/r/pull/7",
        "isDraft":false,"mergeable":"MERGEABLE","reviewDecision":null,"updatedAt":"2026-09-09T22:49:34Z","headRefName":"b",
        "repository":{"nameWithOwner":"o/r"},"reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":true}]},
        "reviews":{"nodes":[{"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer"}},{"state":"APPROVED","author":{"login":"me"}},
        {"state":"APPROVED","author":{"login":"pat"}},{"state":"APPROVED","author":{"login":"pat"}}]},
        "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}]}}}
        """
        let (me, prs) = try PullRequest.decode(Data(json.utf8))
        #expect(me == "me")
        #expect(prs.count == 1)
        #expect(prs[0].approvals == 1)
        #expect(prs[0].unresolvedThreads == 1)
        #expect(prs[0].ci == .success)
        #expect(prs[0].shortRef == "r#7")
        #expect(prs[0].category == .needsAction)
    }

    @Test func decodeSurfacesErrors() {
        let json = #"{"errors":[{"message":"bad token"}]}"#
        #expect(throws: ShellError.self) { try PullRequest.decode(Data(json.utf8)) }
    }
}

@Suite struct EventDiffTests {
    @Test func prTransitionsRaiseEvents() {
        let old = [pr(number: 1), pr(number: 2, threads: 1), pr(number: 3, human: true)]
        let new = [pr(number: 1, ci: .failure), pr(number: 2, threads: 3), pr(number: 3, approvals: 1)]
        let kinds = EventDiff.prs(old: old, new: new).map(\.kind)
        #expect(kinds == [.ciFailed, .newThreads, .approved, .ready])
    }

    @Test func unchangedAndNewPRsAreQuiet() {
        let old = [pr(number: 1, ci: .failure)]
        let new = [pr(number: 1, ci: .failure), pr(number: 9, ci: .failure)]
        #expect(EventDiff.prs(old: old, new: new).isEmpty)
        #expect(EventDiff.departed(old: old, new: []).map(\.number) == [1])
    }

    @Test func usageThresholdsFireOnceAndSuggestSpareAccount() {
        let old = [AccountUsage(id: "a", label: "idexx", sessionPct: 70, weeklyPct: 40),
                   AccountUsage(id: "b", label: "ezyvet", sessionPct: 5, weeklyPct: 5)]
        let new = [AccountUsage(id: "a", label: "idexx", sessionPct: 92, weeklyPct: 40),
                   AccountUsage(id: "b", label: "ezyvet", sessionPct: 5, weeklyPct: 5)]
        let events = EventDiff.usage(old: old, new: new)
        #expect(events.count == 1)
        #expect(events[0].kind == .usageThreshold)
        #expect(events[0].headline == "idexx session at 90%")
        #expect(events[0].detail?.contains("ezyvet has 95% free") == true)
        #expect(EventDiff.usage(old: new, new: new).isEmpty)
    }

    @Test func largeDropIsAReset() {
        let old = [AccountUsage(id: "a", label: "idexx", sessionPct: 88, weeklyPct: 40)]
        let new = [AccountUsage(id: "a", label: "idexx", sessionPct: 2, weeklyPct: 40)]
        #expect(EventDiff.usage(old: old, new: new).map(\.kind) == [.limitReset])
    }

    @Test func staleAccountsAreIgnored() {
        let old = [AccountUsage(id: "a", label: "idexx", sessionPct: 10, weeklyPct: 40)]
        let new = [AccountUsage(id: "a", label: "idexx", sessionPct: 95, weeklyPct: 40, failure: .http(401))]
        #expect(EventDiff.usage(old: old, new: new).isEmpty)
    }

    @Test func batchMessageListsEveryPR() {
        let text = SlackNudger.batchMessage([pr(number: 1), pr(number: 2)])
        #expect(text == ":eyes: 2 PRs waiting for review please:\n• <https://x/1|repo#1> t\n• <https://x/2|repo#2> t")
    }
}
