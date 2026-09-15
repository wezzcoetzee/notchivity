import AppKit
import NotchivityKit

// Kept synchronous on purpose: a top-level `await` turns this file into an async task,
// and once `app.run()` blocks inside it no other main-actor task gets to run.
if CommandLine.arguments.contains("--doctor") {
    let done = DispatchSemaphore(value: 0)
    var checks: [SetupCheck] = []
    Task.detached {
        checks = await SetupDoctor().run()
        done.signal()
    }
    done.wait()
    print(SetupDoctor.report(checks))
    exit(checks.contains(where: \.blocking) ? 1 : 0)
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
