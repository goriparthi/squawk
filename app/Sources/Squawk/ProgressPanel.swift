import AppKit
import SquawkCore

/// A progress window that does not block the main thread.
///
/// `NSAlert.runModal` spins a nested run loop, and work hopping back to the main
/// actor is not reliably serviced there, so a completion could never arrive and
/// the sheet sat forever. Nothing here blocks: the caller shows it, and the
/// completion closes it.
@MainActor
final class ProgressPanel: NSObject {
    private let window: NSWindow
    private let bar = NSProgressIndicator()
    private var onCancel: (() -> Void)?

    init(title: String, message: String) {
        let width: CGFloat = 330

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center

        let bodyLabel = NSTextField(wrappingLabelWithString: message)
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.alignment = .center
        bodyLabel.preferredMaxLayoutWidth = width - 48

        bar.style = .bar
        bar.isIndeterminate = true
        bar.controlSize = .small

        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [icon, titleLabel, bodyLabel, bar, cancel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(16, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()

        cancel.target = self
        cancel.action = #selector(cancelTapped)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            bar.widthAnchor.constraint(equalToConstant: width - 60),
            cancel.widthAnchor.constraint(equalToConstant: 110),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            content.widthAnchor.constraint(equalToConstant: width),
        ])

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
    }

    func show(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        bar.startAnimation(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        bar.stopAnimation(nil)
        window.orderOut(nil)
        onCancel = nil
    }

    @objc private func cancelTapped() {
        let cancel = onCancel
        close()
        cancel?()
    }
}
