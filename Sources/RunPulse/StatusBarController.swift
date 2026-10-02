import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onRefresh: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onMenuOpened: (() -> Void)?
    var rows: () -> [MenuRow] = { [] }
    var now: () -> Date = { Date() }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timedItems: [(item: NSMenuItem, row: RunRow)] = []
    private var ticker: Timer?

    override init() {
        super.init()
        let image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "RunPulse")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Never use `contentTintColor`: on current macOS it renders the whole status item black.
    /// Colour comes from a palette-coloured (non-template) symbol image; the idle state stays a template image
    /// with an uncoloured title so the menu bar's own vibrancy applies.
    func setTitle(_ title: StatusTitle) {
        guard let button = statusItem.button else { return }
        let color: NSColor? = switch title.tint {
        case .normal: nil
        case .green: .systemGreen
        case .red: .systemRed
        case .orange: .systemOrange
        }
        let base = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "RunPulse")
        if let color, let tinted = base?.withSymbolConfiguration(.init(paletteColors: [color])) {
            tinted.isTemplate = false
            button.image = tinted
        } else {
            base?.isTemplate = true
            button.image = base
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        if let color { attributes[.foregroundColor] = color }
        button.attributedTitle = NSAttributedString(string: title.text.isEmpty ? "" : " \(title.text)",
                                                    attributes: attributes)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    /// Menus run the event loop in `.eventTracking` mode, so the ticker must be scheduled in `.common`.
    func menuWillOpen(_ menu: NSMenu) {
        onMenuOpened?()
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Building

    private func rebuild() {
        menu.removeAllItems()
        timedItems = []
        rows().forEach(add)
        menu.addItem(.separator())
        menu.addItem(action("Refresh Now", #selector(refresh), key: "r"))
        menu.addItem(action("Preferences…", #selector(preferences), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func add(_ row: MenuRow) {
        switch row {
        case .section(let title):
            menu.addItem(info(NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor
            ])))
        case .run(let run):
            let item = action("", #selector(openURL(_:)))
            item.representedObject = run.url
            item.attributedTitle = runTitle(run)
            timedItems.append((item, run))
            menu.addItem(item)
            if let detail = run.detail {
                let detailItem = info(NSAttributedString(string: detail, attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
                ]))
                detailItem.indentationLevel = 2
                menu.addItem(detailItem)
            }
        case .message(let text):
            menu.addItem(info(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])))
        case .separator:
            menu.addItem(.separator())
        case .openActions(let repos):
            let item = NSMenuItem(title: "Open Actions", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for repo in repos {
                let entry = action(repo, #selector(openURL(_:)))
                entry.representedObject = MenuModel.actionsURL(repo)
                submenu.addItem(entry)
            }
            item.submenu = submenu
            menu.addItem(item)
        }
    }

    /// Enabled but action-less, so colours aren't dimmed the way disabled items are.
    private func info(_ title: NSAttributedString) -> NSMenuItem {
        let item = NSMenuItem(title: title.string, action: nil, keyEquivalent: "")
        item.attributedTitle = title
        item.isEnabled = true
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func tick() {
        for (item, row) in timedItems {
            item.attributedTitle = runTitle(row)
        }
    }

    private func runTitle(_ row: RunRow) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 250),
                          NSTextTab(textAlignment: .right, location: 430)]
        let (glyph, color): (String, NSColor) = switch row.glyph {
        case .queued, .running: ("◐", .systemOrange)
        case .success: ("✓", .systemGreen)
        case .failure: ("✗", .systemRed)
        case .cancelled: ("⊘", .systemGray)
        case .skipped: ("–", .systemGray)
        }
        let title = NSMutableAttributedString(string: "\(glyph) ", attributes: [
            .foregroundColor: color, .paragraphStyle: style
        ])
        title.append(NSAttributedString(string: row.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style
        ]))
        title.append(NSAttributedString(
            string: "\t\(row.branch)\t\(MenuModel.timingText(row.timing, now: now()))",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style
            ]))
        return title
    }

    // MARK: Actions

    @objc private func refresh() { onRefresh?() }

    @objc private func preferences() { onPreferences?() }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}
