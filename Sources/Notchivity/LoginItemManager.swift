import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    @Published private(set) var isEnabled: Bool
    private let service = SMAppService.mainApp

    /// Launch at login needs the bundle in /Applications; Settings and the setup check both ask.
    static var inApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    init() { isEnabled = service.status == .enabled }

    /// macOS may hold a new login item for approval; then its Login Items pane opens, so the
    /// switch snapping back is not left unexplained.
    func setEnabled(_ enabled: Bool) {
        try? enabled ? service.register() : service.unregister()
        if enabled, service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        isEnabled = service.status == .enabled
    }
}
