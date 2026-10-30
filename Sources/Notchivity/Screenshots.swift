import AppKit
import NotchivityKit
import SwiftUI

/// `Notchivity --screenshots <dir>` renders each panel state offscreen with fixed sample
/// data, so store images never show real accounts or PRs. See "Screenshots" in README.md.
@MainActor
enum Screenshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        model.loadDemo(me: "wezzcoetzee", accounts: accounts(now: model.now), prs: prs(now: model.now), peek: peeks[2])

        let expanded = NotchGeometry()
        expanded.state = .expanded
        save(panel(ExpandedView(model: model, geometry: expanded)), "expanded", dir)
        let peekGeometry = NotchGeometry()
        peekGeometry.notchHeight = 0
        save(VStack(spacing: 24) {
            ForEach(peeks) { panel(PeekView(event: $0, geometry: peekGeometry)) }
        }, "peek", dir)
    }

    /// The black notch shape RootView draws behind every expanded state.
    private static func panel(_ view: some View) -> some View {
        view.foregroundStyle(.white)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(.black))
    }

    private static func save(_ view: some View, _ name: String, _ dir: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 3
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("✗ \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        print("✓ \(name).png")
    }

    private static let peeks = [
        Event(kind: .ciFailed, headline: "web#318 CI failed", detail: "fix(web): checkout total rounds twice", tone: .bad),
        Event(kind: .usageThreshold, headline: "Work session at 88%", detail: "resets in 47m", tone: .warn),
        Event(kind: .ready, headline: "notchivity#42 is ready to merge", detail: "approved · CI ✓", tone: .good),
    ]

    private static func accounts(now: Date) -> [AccountUsage] {
        let t = now.timeIntervalSince1970
        return [
            AccountUsage(id: "claude", label: "Claude", sessionPct: 42, weeklyPct: 61,
                         sessionResetsAt: t + 2 * 3600 + 14 * 60, weeklyResetsAt: t + 3 * 86_400),
            AccountUsage(id: "claude-work", label: "Work", sessionPct: 88, weeklyPct: 34,
                         sessionResetsAt: t + 47 * 60, weeklyResetsAt: t + 5 * 86_400),
            AccountUsage(id: "codex", label: "Codex", provider: .codex, sessionPct: 12, weeklyPct: 27,
                         sessionResetsAt: t + 4 * 3600, weeklyResetsAt: t + 2 * 86_400, observedAt: t - 60),
            AccountUsage(id: "grok", label: "Grok", provider: .grok, observedAt: t - 120,
                         monthlyPct: 18, monthlyResetsAt: t + 19 * 86_400),
        ]
    }

    private static func prs(now: Date) -> [PullRequest] {
        func pr(_ repo: String, _ number: Int, _ title: String, minutesAgo: Double, ci: CIState,
                conflicts: Bool = false, threads: Int = 0, approvals: Int = 0, human: Bool = false) -> PullRequest {
            PullRequest(repo: "acme/\(repo)", number: number, title: title,
                        url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!, branch: "feature",
                        updatedAt: now.addingTimeInterval(-minutesAgo * 60), ci: ci, conflicts: conflicts,
                        unresolvedThreads: threads, approvals: approvals, reviewedByHuman: human)
        }
        return [
            pr("web", 318, "fix(web): checkout total rounds twice", minutesAgo: 8, ci: .failure),
            pr("api", 1204, "feat(api): rate limit per workspace", minutesAgo: 95, ci: .success, threads: 2, human: true),
            pr("notchivity", 42, "feat: monitor Grok Build usage", minutesAgo: 22, ci: .success, approvals: 2),
            pr("mobile", 77, "chore: bump Expo to 55", minutesAgo: 300, ci: .success, approvals: 1),
            pr("infra", 9, "feat: preview environments per PR", minutesAgo: 40, ci: .pending),
        ]
    }
}
