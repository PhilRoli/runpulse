import AppKit

extension PreferencesWindowController {
    func buildLayout() {
        guard let window, let content = window.contentView else { return }
        let stack = NSStackView(views: [
            sectionLabel("Account"), accountGrid(), separator(),
            sectionLabel("Repos"), reposView(), separator(),
            sectionLabel("General"), notifyCheck, loginCheck
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.setContentSize(stack.fittingSize)
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
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        return label
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 380).isActive = true
        return box
    }
}
