import AppKit
import NotchivityKit
import UserNotifications

/// Runs the setup checklist on launch and every few seconds while it is on screen.
/// The expanded panel shows the checklist instead of the dashboard until every required
/// check has passed once; later failures surface inline on the dashboard instead. The
/// right-click menu can bring the checklist back any time.
@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var checks: [SetupCheck] = []
    @Published private(set) var running = false
    /// User asked for the checklist even though nothing is blocking.
    @Published var pinned = false
    /// Every required check passed at least once, so the dashboard owns the panel from here on.
    @Published private(set) var everPassed = false

    static let recheckInterval: TimeInterval = 10

    var blocking: Int { checks.filter(\.blocking).count }
    var required: [SetupCheck] { checks.filter(\.required) }
    var hasRun: Bool { !checks.isEmpty }
    /// Show the checklist while first-run setup is incomplete, or on request.
    var visible: Bool { pinned || (hasRun && blocking > 0 && !everPassed) }

    /// Supply the app's latest readings so the checks do not poll the APIs on their own.
    var usageProvider: () async -> [AccountUsage] = { [] }
    var prsProvider: () async -> SetupDoctor.PRResult? = { nil }

    func run() async {
        guard !running else { return }
        running = true
        checks = await SetupDoctor().run(usage: await usageProvider(), prs: await prsProvider(), extra: await appChecks())
        if blocking == 0 { everPassed = true }
        running = false
    }

    /// Keep rechecking while visible so fixes show up on their own.
    func startRechecking() {
        Task {
            while !Task.isCancelled {
                if visible { await run() }
                try? await Task.sleep(for: .seconds(Self.recheckInterval))
            }
        }
    }

    private func appChecks() async -> [SetupCheck] {
        var checks: [SetupCheck] = []
        if Notifier.shared.available {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                checks.append(SetupCheck(id: "notifications", title: "notifications allowed", status: .pass, required: false))
            case .denied:
                checks.append(SetupCheck(id: "notifications", title: "notifications denied", status: .warn,
                                         detail: "optional, peeks still work", required: false, fix: .openNotificationSettings))
            default:
                checks.append(SetupCheck(id: "notifications", title: "notifications not yet allowed", status: .warn,
                                         detail: "optional, peeks still work", required: false, fix: .allowNotifications))
            }
        } else {
            checks.append(SetupCheck(id: "notifications", title: "notifications unavailable", status: .off,
                                     detail: "run the .app bundle from make-app.sh", required: false))
        }
        let inApplications = Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        if LoginItemManager.shared.isEnabled {
            checks.append(SetupCheck(id: "login", title: "launch at login on", status: .pass, required: false))
        } else if inApplications {
            checks.append(SetupCheck(id: "login", title: "launch at login", status: .off, detail: "optional", required: false, fix: .enableLoginItem))
        } else {
            checks.append(SetupCheck(id: "login", title: "launch at login", status: .off,
                                     detail: "optional, needs the app in /Applications", required: false,
                                     fix: Notifier.shared.available ? .moveToApplications : nil))
        }
        return checks
    }

    func apply(_ fix: SetupCheck.Fix) {
        switch fix {
        case .openClaudeCode:
            let script = "tell application \"Terminal\" to do script \"claude\"\ntell application \"Terminal\" to activate"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        case .retry:
            break
        case .copy(let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        case .allowNotifications:
            Notifier.shared.requestAuthorization()
        case .openNotificationSettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        case .createSlackConfig:
            NSWorkspace.shared.open(SetupDoctor.createSlackConfigTemplate())
        case .enableLoginItem:
            LoginItemManager.shared.setEnabled(true)
        case .moveToApplications:
            moveToApplications()
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await run()
        }
    }

    private func moveToApplications() {
        let source = Bundle.main.bundleURL
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            NSWorkspace.shared.openApplication(at: target, configuration: .init()) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            NSSound.beep()
        }
    }
}
