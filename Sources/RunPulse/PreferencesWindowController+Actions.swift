import AppKit

extension PreferencesWindowController {
    private static let savedTokenPlaceholder = "••••••••"

    func loadValues() {
        lookbackPopup.selectItem(at: AppConfig.lookbackChoices.firstIndex(of: config.lookbackDays) ?? 2)
        notifyCheck.state = config.notificationsEnabled ? .on : .off
        loginCheck.state = loginItem.isEnabled ? .on : .off
        let store = keychain
        Task { [weak self] in
            let hasToken = await Task.detached { (try? store.read()) != nil }.value
            self?.tokenField.placeholderString = hasToken ? Self.savedTokenPlaceholder : nil
        }
    }

    @objc func tokenEdited() {
        guard case .set(let token) = PreferencesLogic.tokenInput(tokenField.stringValue) else { return }
        tokenField.stringValue = ""
        let store = keychain
        Task { [weak self] in
            let saved = await Task.detached { (try? store.save(token)) != nil }.value
            guard let self else { return }
            if saved {
                self.tokenField.placeholderString = Self.savedTokenPlaceholder
                self.onTokenSaved?()
            } else {
                NSSound.beep()
            }
        }
    }

    @objc func lookbackChanged() {
        config.lookbackDays = AppConfig.lookbackChoices[max(0, lookbackPopup.indexOfSelectedItem)]
        onChange?(config)
    }

    @objc func notificationsChanged() {
        config.notificationsEnabled = notifyCheck.state == .on
        onChange?(config)
    }

    @objc func repoToggled(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue, repoRows.contains(where: { $0.name == name }) else { return }
        config.muted = PreferencesLogic.muted(config.muted, repo: name, enabled: sender.state == .on)
        onChange?(config)
        reloadRepos()
    }

    @objc func loginToggled() {
        if !loginItem.setEnabled(loginCheck.state == .on) { NSSound.beep() }
        loginCheck.state = loginItem.isEnabled ? .on : .off
    }
}
