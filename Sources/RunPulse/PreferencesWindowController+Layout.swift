import AppKit
import MenuBarKit

extension PreferencesWindowController {
    func buildLayout() {
        guard let window else { return }
        let stack = NSStackView(views: [
            sectionLabel("Account"), accountGrid(), separator(),
            sectionLabel("Repos"), reposView(), separator(),
            sectionLabel("General"), notifyCheck, loginCheck
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        PreferencesLayout.pinAndFit(stack, in: window)
    }

    private func accountGrid() -> NSView {
        tokenField.target = self
        tokenField.action = #selector(tokenEdited)
        tokenField.cell?.sendsActionOnEndEditing = true
        tokenField.usesSingleLineMode = true
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        tokenField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let grid = NSGridView(views: [[label("Account"), accountLabel], [label("Token"), tokenField]])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }

    private func reposView() -> NSView {
        lookbackPopup.addItems(withTitles: AppConfig.lookbackChoices.map { $0 == 1 ? "1 day" : "\($0) days" })
        lookbackPopup.target = self
        lookbackPopup.action = #selector(lookbackChanged)
        let lookbackRow = NSStackView(views: [label("Lookback"), lookbackPopup])

        for (id, width) in [("on", 24.0), ("name", 330.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.width = width
            table.addTableColumn(column)
        }
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.selectionHighlightStyle = .none
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 380).isActive = true

        notifyCheck.target = self
        notifyCheck.action = #selector(notificationsChanged)
        loginCheck.target = self
        loginCheck.action = #selector(loginToggled)

        let column = NSStackView(views: [lookbackRow, scroll])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        return column
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        PreferencesLayout.sectionLabel(text)
    }

    private func label(_ text: String) -> NSTextField {
        PreferencesLayout.label(text)
    }

    private func separator() -> NSView {
        PreferencesLayout.separator(width: 380)
    }
}
