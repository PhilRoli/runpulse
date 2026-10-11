import AppKit
import MenuBarKit

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    var onChange: ((AppConfig) -> Void)?
    var onTokenSaved: (() -> Void)?

    var config: AppConfig
    let keychain: KeychainTokenStoring
    let loginItem: LoginItemController
    var pollerState = PollerState()
    var repoRows: [RepoRow] = []

    let accountLabel = NSTextField(labelWithString: "Not signed in")
    let tokenField = NSSecureTextField()
    let lookbackPopup = NSPopUpButton()
    let table = NSTableView()
    let notifyCheck = NSButton(checkboxWithTitle: "Notifications", target: nil, action: nil)
    let loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

    init(config: AppConfig, keychain: KeychainTokenStoring, loginItem: LoginItemController) {
        self.config = config
        self.keychain = keychain
        self.loginItem = loginItem
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "RunPulse"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildLayout()
        loadValues()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        loginCheck.state = loginItem.isEnabled ? .on : .off
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(state: PollerState) {
        pollerState = state
        accountLabel.stringValue = PreferencesLogic.accountLabel(state)
        reloadRepos()
    }

    /// Reloading mid-click would swap the checkbox under the cursor, so only reload on real changes.
    func reloadRepos() {
        let rows = PreferencesLogic.repoRows(discovered: pollerState.discovered, muted: config.muted,
                                             noAccess: pollerState.noAccess)
        guard rows != repoRows else { return }
        repoRows = rows
        table.reloadData()
    }

    /// Ends editing so the token field commits before the window goes away.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        repoRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let repo = repoRows[row]
        if tableColumn?.identifier.rawValue == "on" {
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(repoToggled(_:)))
            box.state = repo.enabled ? .on : .off
            box.isEnabled = !repo.noAccess
            box.identifier = NSUserInterfaceItemIdentifier(repo.name)
            return box
        }
        let label = NSTextField(labelWithString: repo.noAccess ? "\(repo.name)  no access" : repo.name)
        label.textColor = repo.noAccess ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
