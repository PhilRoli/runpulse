import ServiceManagement

protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

struct SMAppServiceLoginItemManager: LoginItemManaging {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func register() throws { try SMAppService.mainApp.register() }

    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController {
    private let manager: LoginItemManaging

    init(manager: LoginItemManaging = SMAppServiceLoginItemManager()) {
        self.manager = manager
    }

    var isEnabled: Bool { manager.isEnabled }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled { try manager.register() } else { try manager.unregister() }
            return true
        } catch {
            return false
        }
    }
}
