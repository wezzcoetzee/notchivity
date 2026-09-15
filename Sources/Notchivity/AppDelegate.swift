import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var notch: NotchPanels!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        notch = NotchPanels(model: model)
        Notifier.shared.requestAuthorization()
        model.start()
        notch.show()
        installMainMenu()
        if ProcessInfo.processInfo.environment["NOTCHIVITY_SETTINGS"] != nil { openSettings() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.notch.relayout() }
        }
    }

    /// Only exists so Cmd-, Cmd-Q and the standard edit shortcuts (paste, undo…) work
    /// while the Settings window is key. Accessory apps get no menu bar otherwise.
    private func installMainMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        app.submenu?.addItem(withTitle: "Quit Notchivity", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(app)

        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        let items: [(String, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, key) in items { edit.submenu?.addItem(withTitle: title, action: action, keyEquivalent: key) }
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(model: model)
    }
}
