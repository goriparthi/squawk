import AppKit
import SquawkCore

/// What the selected agent wants, and the three things you can do about it.
final class DetailView: NSView {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onOpenPane: (() -> Void)?
    var onAllowSession: (() -> Void)?
    var onAllowAlways: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// How much of the card fits at the current dial size.
    var tier: CardTier = .full

    private let countLabel = NSTextField(labelWithString: "")
    /// Cover art, when a player hands it over.
    private let coverView = NSImageView()
    /// What it says when it is not relaying a request, which today is a fortune.
    private let fortuneLabel = NSTextField(wrappingLabelWithString: "")
    private let projectLabel = NSTextField(labelWithString: "")
    private let toolLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let allowButton = FirstMouseButton()
    private let denyButton = FirstMouseButton()
    private let paneButton = FirstMouseButton()
    private let sessionButton = FirstMouseButton()
    private let alwaysButton = FirstMouseButton()
    private let dismissButton = FirstMouseButton()
    /// The full width pane button an attention entry gets, as opposed to the
    /// small one a decision tucks in beside Session and Always.
    private let openPaneButton = FirstMouseButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func build() {
        countLabel.font = Palette.ui(size: 10, weight: .medium)
        countLabel.textColor = Palette.waiting
        countLabel.alignment = .center
        projectLabel.font = Palette.ui(size: 12, weight: .semibold)
        projectLabel.textColor = Palette.primaryText
        toolLabel.font = Palette.ui(size: 11, weight: .medium)
        toolLabel.textColor = Palette.secondaryText
        summaryLabel.font = Palette.telemetry(size: 11)
        summaryLabel.textColor = Palette.primaryText
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.maximumNumberOfLines = 2
        for label in [countLabel, projectLabel, toolLabel, summaryLabel] {
            label.alignment = .center
            // A long command must truncate inside the panel. Left at the default
            // priority the label wins against the width constraint and drags the
            // whole window wider than its own frame.
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.cell?.truncatesLastVisibleLine = true
        }

        configure(allowButton, title: "Approve", key: "\r", color: Palette.allow, action: #selector(allowTapped))
        configure(denyButton, title: "Deny", key: "\u{1b}", color: Palette.deny, action: #selector(denyTapped))
        configure(paneButton, title: "Pane", key: "o", color: Palette.secondaryText, action: #selector(paneTapped))
        configure(dismissButton, title: "Dismiss", key: "\u{1b}", color: Palette.secondaryText, action: #selector(dismissTapped))
        configure(openPaneButton, title: "Open pane", key: "o", color: Palette.running, action: #selector(paneTapped))
        configure(sessionButton, title: "Session", key: "s", color: Palette.brand, action: #selector(sessionTapped))
        configure(alwaysButton, title: "Always", key: "l", color: Palette.brand, action: #selector(alwaysTapped))
        // These grant standing permission, so they have to be readable rather
        // than a row of grey hints under the real buttons.
        for small in [sessionButton, alwaysButton] {
            small.isBordered = false
            small.font = Palette.ui(size: 12, weight: .medium)
            small.contentTintColor = Palette.primaryText
        }

        // Approve and Deny are the frequent actions and get the full width;
        // opening the pane is rarer and sits under them as a plain link.
        let buttons = NSStackView(views: [allowButton, denyButton, openPaneButton, dismissButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        // The labels live in their own stack so hiding them collapses cleanly and
        // the gap above the buttons survives; custom spacing after a hidden view
        // is ignored, which left the cleared state cramped.
        let cardWidth: CGFloat = 260
        summaryLabel.preferredMaxLayoutWidth = cardWidth

        fortuneLabel.font = Palette.ui(size: 12, weight: .medium)
        fortuneLabel.textColor = Palette.primaryText
        fortuneLabel.alignment = .center
        fortuneLabel.maximumNumberOfLines = 4
        fortuneLabel.isHidden = true

        coverView.imageScaling = .scaleProportionallyUpOrDown
        coverView.wantsLayer = true
        coverView.layer?.cornerRadius = 6
        coverView.layer?.masksToBounds = true
        coverView.isHidden = true
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.heightAnchor.constraint(equalToConstant: 56).isActive = true
        coverView.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let labels = NSStackView(views: [coverView, countLabel, projectLabel, toolLabel,
                                         summaryLabel, fortuneLabel])
        labels.orientation = .vertical
        labels.alignment = .centerX
        labels.spacing = 4

        // One row of small actions rather than more rows: the card has to stay
        // inside the ring at every dial size.
        let secondary = NSStackView(views: [sessionButton, alwaysButton, paneButton])
        secondary.orientation = .horizontal
        secondary.spacing = 14

        let stack = NSStackView(views: [labels, buttons, secondary])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            // Without this the view's height is under determined, so its content
            // spilled past the frame the enclosing column centred.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            labels.widthAnchor.constraint(equalTo: stack.widthAnchor),
            projectLabel.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
            toolLabel.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
            summaryLabel.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor),
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

    /// The narrowest the card can be without truncating what it is showing, so
    /// a one line notice gets a small bubble and a long command gets a wide one.
    /// Measured rather than taken from a fitting size, which leaves the stack's
    /// own insets out.
    @discardableResult
    func fitWidth(within limit: CGFloat) -> CGFloat {
        var widest: CGFloat = 0
        for label in [countLabel, projectLabel, toolLabel, summaryLabel, fortuneLabel]
        where !label.isHidden {
            // A cell lays its text out inside a small inset the measured string
            // knows nothing about, and one point short truncates the line.
            widest = max(widest, label.attributedStringValue.size().width.rounded(.up) + 6)
        }
        // A row of buttons cannot be squeezed the way a line of text can. The
        // first row fills equally, so every button is as wide as the widest.
        let primary = [allowButton, denyButton, openPaneButton, dismissButton]
            .filter { !$0.isHidden }
        if !primary.isEmpty {
            let each = primary.map { $0.intrinsicContentSize.width.rounded(.up) }.max() ?? 0
            widest = max(widest, each * CGFloat(primary.count) + 8 * CGFloat(primary.count - 1))
        }
        let secondary = [sessionButton, alwaysButton, paneButton].filter { !$0.isHidden }
        if !secondary.isEmpty {
            let total = secondary.map { $0.intrinsicContentSize.width.rounded(.up) }.reduce(0, +)
            widest = max(widest, total + 14 * CGFloat(secondary.count - 1))
        }
        let width = min(widest, limit)
        // Whatever we settled on is what a long command wraps inside.
        summaryLabel.preferredMaxLayoutWidth = width
        fortuneLabel.preferredMaxLayoutWidth = width
        return width
    }

    /// Everything the pointer is meant to be able to reach right now. Only the
    /// reachability check uses it, and only because a dead button looks exactly
    /// like a live one in a screenshot.
    var liveControls: [NSView] {
        [allowButton, denyButton, openPaneButton, dismissButton,
         paneButton, sessionButton, alwaysButton].filter { !$0.isHidden }
    }

    /// Says something of its own, in place of a request. Same card, so the
    /// bubble sizes itself around a fortune exactly as it does around a command.
    func speak(_ text: String) {
        for view in [countLabel, projectLabel, toolLabel, summaryLabel] { view.isHidden = true }
        for button in [allowButton, denyButton, openPaneButton, dismissButton,
                       paneButton, sessionButton, alwaysButton] {
            button.isHidden = true
        }
        coverView.isHidden = true
        fortuneLabel.stringValue = text
        fortuneLabel.isHidden = false
    }

    /// What is playing, on the card it already has: title, artist and whatever
    /// the tap has worked out about it. Rich in the sense that matters, which
    /// is that it says several true things rather than one.
    func showNowPlaying(title: String?, artist: String?, detail: String,
                        artwork: NSImage? = nil) {
        coverView.image = artwork
        coverView.isHidden = artwork == nil
        for button in [allowButton, denyButton, openPaneButton, dismissButton,
                       paneButton, sessionButton, alwaysButton] {
            button.isHidden = true
        }
        fortuneLabel.isHidden = true
        countLabel.stringValue = "now playing"
        countLabel.isHidden = false
        projectLabel.stringValue = title ?? "Something is playing"
        projectLabel.isHidden = false
        toolLabel.stringValue = artist ?? ""
        toolLabel.isHidden = (artist ?? "").isEmpty
        summaryLabel.stringValue = detail
        summaryLabel.isHidden = detail.isEmpty
    }

    func show(_ entry: Roster.Entry?, waiting: Int = 0) {
        coverView.isHidden = true
        fortuneLabel.isHidden = true
        projectLabel.isHidden = false
        countLabel.stringValue = waiting > 1 ? "\(waiting) waiting" : ""
        countLabel.isHidden = waiting <= 1 || !tier.showsCount
        guard let entry else {
            projectLabel.stringValue = "Nothing waiting"
            toolLabel.isHidden = true
            summaryLabel.isHidden = true
            setButtons(enabled: false)
            return
        }
        projectLabel.stringValue = entry.request.project
        toolLabel.stringValue = entry.request.tool
        summaryLabel.stringValue = entry.request.summary

        // A question has nothing to allow or deny; the pane is the only answer.
        let decidable = entry.request.awaitsDecision
        allowButton.isHidden = !decidable
        denyButton.isHidden = !decidable
        // When it is the only action, it looks like one: a real button, not a
        // word under the buttons that matter.
        paneButton.isBordered = false
        paneButton.font = Palette.ui(size: 12, weight: .medium)
        paneButton.contentTintColor = Palette.primaryText
        // A smaller dial sheds rows rather than overflowing its own ring. What
        // is dropped here is still reachable by pointing at the dial.
        let secondary = decidable && tier.showsSecondaryActions
        sessionButton.isHidden = !secondary
        alwaysButton.isHidden = !secondary
        // When there is nothing to decide, the pane is the only action there is,
        // so it is never what gets dropped to make the dial smaller.
        paneButton.isHidden = !decidable || !tier.showsSecondaryActions
        // Nothing is blocked on an attention entry, so nothing times out to
        // clear it. Without a dismiss there is no way to make it go away.
        openPaneButton.isHidden = decidable
        dismissButton.isHidden = decidable
        // A truncated label says nothing, so the words shorten with the dial
        // rather than being clipped to "Ope..." and "Dis...".
        let roomy = tier == .full
        openPaneButton.title = roomy ? "Open pane" : "Pane"
        dismissButton.title = roomy ? "Dismiss" : "Clear"
        toolLabel.isHidden = !tier.showsCommand
        summaryLabel.isHidden = !tier.showsCommand
        // Say what the button will actually wave through, so nobody grants
        // something wider than they read.
        let scope = PermissionRule.key(
            tool: entry.request.tool, summary: entry.request.summary
        ).describedScope
        // The shortcut is named in the tooltip; the buttons are too small to
        // carry it, and a shortcut nobody can discover is not a shortcut.
        openPaneButton.toolTip = "Bring the agent's terminal pane forward  (O)"
        dismissButton.toolTip = "Clear this from the dial  (Escape)"
        allowButton.toolTip = "Approve once  (Return)"
        denyButton.toolTip = "Deny  (Escape)"
        sessionButton.toolTip = "Allow \(scope) for the rest of this session  (S)"
        alwaysButton.toolTip = "Always allow \(scope)  (L)"
        paneButton.toolTip = "Bring the agent's terminal pane forward  (O)"
        setButtons(enabled: true)
        paneButton.isEnabled = entry.request.ancestors?.isEmpty == false
    }

    private func setButtons(enabled: Bool) {
        for button in [allowButton, denyButton, paneButton, sessionButton,
                       alwaysButton, dismissButton, openPaneButton] {
            button.isEnabled = enabled
        }
    }

    // The panel is meant to be answered while another app is focused, so a click
    // must act on the first press instead of being spent raising the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func allowTapped() { onAllow?() }
    @objc private func denyTapped() { onDeny?() }
    @objc private func paneTapped() { onOpenPane?() }
    @objc private func sessionTapped() { onAllowSession?() }
    @objc private func alwaysTapped() { onAllowAlways?() }
    @objc private func dismissTapped() { onDismiss?() }
}
