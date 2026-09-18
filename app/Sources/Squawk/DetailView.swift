import AppKit
import SquawkCore

/// What the selected agent wants, and the three things you can do about it.
final class DetailView: NSView {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onOpenPane: (() -> Void)?

    private let projectLabel = NSTextField(labelWithString: "")
    private let toolLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let allowButton = FirstMouseButton()
    private let denyButton = FirstMouseButton()
    private let paneButton = FirstMouseButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func build() {
        projectLabel.font = Palette.ui(size: 12, weight: .semibold)
        projectLabel.textColor = Palette.primaryText
        toolLabel.font = Palette.ui(size: 11, weight: .medium)
        toolLabel.textColor = Palette.secondaryText
        summaryLabel.font = Palette.telemetry(size: 11)
        summaryLabel.textColor = Palette.primaryText
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.maximumNumberOfLines = 2

        configure(allowButton, title: "Approve", key: "a", color: Palette.allow, action: #selector(allowTapped))
        configure(denyButton, title: "Deny", key: "d", color: Palette.deny, action: #selector(denyTapped))
        configure(paneButton, title: "Open pane", key: "o", color: Palette.secondaryText, action: #selector(paneTapped))

        let buttons = NSStackView(views: [allowButton, denyButton, paneButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        let stack = NSStackView(views: [projectLabel, toolLabel, summaryLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            buttons.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func configure(_ button: NSButton, title: String, key: String, color: NSColor, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.keyEquivalent = key
        button.target = self
        button.action = action
        button.contentTintColor = color
    }

    func show(_ entry: Roster.Entry?) {
        guard let entry else {
            projectLabel.stringValue = "Nothing waiting"
            toolLabel.stringValue = ""
            summaryLabel.stringValue = ""
            setButtons(enabled: false)
            return
        }
        projectLabel.stringValue = entry.request.project
        toolLabel.stringValue = entry.request.tool
        summaryLabel.stringValue = entry.request.summary
        setButtons(enabled: true)
        paneButton.isEnabled = entry.request.tty != nil
    }

    private func setButtons(enabled: Bool) {
        allowButton.isEnabled = enabled
        denyButton.isEnabled = enabled
        paneButton.isEnabled = enabled
    }

    // The panel is meant to be answered while another app is focused, so a click
    // must act on the first press instead of being spent raising the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func allowTapped() { onAllow?() }
    @objc private func denyTapped() { onDeny?() }
    @objc private func paneTapped() { onOpenPane?() }
}
