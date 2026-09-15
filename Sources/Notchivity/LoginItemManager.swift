import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    @Published private(set) var isEnabled: Bool
    private let service = SMAppService.mainApp

    init() { isEnabled = service.status == .enabled }

    func setEnabled(_ enabled: Bool) {
        try? enabled ? service.register() : service.unregister()
        isEnabled = service.status == .enabled
    }
}
