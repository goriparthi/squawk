import AppKit
import SquawkCore

/// Squawk's own message panel. NSAlert reserves a leading icon column and rows
/// for its own title and body, so an accessory view centred inside one leaves a
/// band of empty space above it. This is a plain window instead, sized to what
/// it actually contains.
@MainActor
enum InfoPanel {
    private static let opener = Opener()

    /// A reference card: headings and paragraphs, laid out ragged right. A list
    /// of things you can do is read down the left edge, and centring it made
    /// every line start somewhere different.
    static func show(title: String, sections: [(heading: String, body: String)]) {
        let text = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 12

        for (index, section) in sections.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n")) }
            text.append(NSAttributedString(string: section.heading + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
            text.append(NSAttributedString(string: section.body, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]))
        }
        show(title: title, attributed: text, linkVersion: false)
    }

    static func show(title: String, message: String, linkVersion: Bool = true) {
        show(title: title,
             attributed: NSAttributedString(string: message),
             linkVersion: linkVersion,
             centred: true)
    }

    private static func show(
        title: String, attributed: NSAttributedString,
        linkVersion: Bool = true, centred: Bool = false
    ) {
        let width: CGFloat = centred ? 320 : 400

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center

        let bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.attributedStringValue = attributed
        if centred {
            bodyLabel.font = .systemFont(ofSize: 12)
            bodyLabel.textColor = .secondaryLabelColor
            bodyLabel.alignment = .center
        }
        bodyLabel.preferredMaxLayoutWidth = width - 48

        let stack = NSStackView(views: [icon, titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        // A left aligned block still has to be as wide as the panel, or the
        // stack centres a narrow column and the ragged edge wanders.
        bodyLabel.widthAnchor.constraint(equalToConstant: width - 48).isActive = true
        stack.spacing = 10
        stack.setCustomSpacing(14, after: icon)

        if linkVersion {
            let link = NSButton()
            link.isBordered = false
            link.bezelStyle = .inline
            link.attributedTitle = NSAttributedString(
                string: "Squawk \(Updates.bundleVersion)",
                attributes: [
                    .foregroundColor: Palette.brand,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                ]
            )
            link.target = opener
            link.action = #selector(Opener.open)
            link.toolTip = Updates.repoURL.absoluteString
            stack.addArrangedSubview(link)
        }

        if linkVersion {
            let site = NSButton()
            site.isBordered = false
            site.bezelStyle = .inline
            site.attributedTitle = NSAttributedString(
                string: "squawk website",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .font: NSFont.systemFont(ofSize: 11),
                ]
            )
            site.target = opener
            site.action = #selector(Opener.openSite)
            site.toolTip = Updates.siteURL.absoluteString
            stack.addArrangedSubview(site)
        }

        let ok = NSButton(title: "OK", target: opener, action: #selector(Opener.dismiss))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        stack.addArrangedSubview(ok)
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            ok.widthAnchor.constraint(equalToConstant: 120),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            content.widthAnchor.constraint(equalToConstant: width),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()

        opener.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
    }

    /// A target for the buttons; NSButton needs an object, not a closure.
    @MainActor
    final class Opener: NSObject {
        weak var window: NSWindow?
        @objc func open() { NSWorkspace.shared.open(Updates.repoURL) }
        @objc func openSite() { NSWorkspace.shared.open(Updates.siteURL) }
        @objc func dismiss() { NSApp.stopModal() }
    }
}
