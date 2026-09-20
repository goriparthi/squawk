import AppKit
import SquawkCore

/// The week, as something you can read and scroll rather than one line at a
/// time in a bubble. A real window, not a modal sheet: it is something you
/// leave open beside your work.
///
/// Built on a text view rather than a table, so a command can be selected and
/// copied straight out of it, which is the thing anyone actually wants from a
/// log of commands.
@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    static let shared = HistoryWindow()

    private var window: NSWindow?
    private let text = NSTextView()
    private var scroll: NSScrollView?

    var isOpen: Bool { window?.isVisible ?? false }

    func show(_ journal: Journal) {
        if window == nil { build() }
        fill(journal)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        scrollToEnd()
    }

    /// Kept current while it is open, so answering something on the dial shows
    /// up here without reopening it.
    func refresh(_ journal: Journal) {
        guard isOpen else { return }
        let wasAtEnd = isScrolledToEnd
        fill(journal)
        if wasAtEnd { scrollToEnd() }
    }

    func close() { window?.orderOut(nil) }

    private func build() {
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 18, height: 16)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.radarBlack
        scroll.documentView = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.scroll = scroll

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.radarBlack.cgColor
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "This Week"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.radarBlack
        window.contentView = content
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SquawkHistory")
        window.center()
        self.window = window
    }

    private func fill(_ journal: Journal) {
        let days = journal.byDay()
        let body = NSMutableAttributedString()
        guard !days.isEmpty else {
            body.append(line("Nothing yet. What your agents ask for, and what you "
                + "answer, will appear here and stay for a week.",
                colour: Palette.secondaryText, size: 12))
            text.textStorage?.setAttributedString(body)
            return
        }
        for (day, entries) in days {
            body.append(line(day.uppercased(), colour: Palette.secondaryText, size: 10,
                             weight: .semibold, spacingAbove: body.length == 0 ? 0 : 18))
            for entry in entries {
                body.append(row(entry))
            }
        }
        text.textStorage?.setAttributedString(body)
    }

    /// One entry: the time, what happened, where, and what it was.
    private func row(_ entry: Journal.Entry) -> NSAttributedString {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let stamp = formatter.string(from: entry.at)
        let out = NSMutableAttributedString()
        out.append(piece("\(stamp)  ", colour: Palette.secondaryText, size: 11,
                         font: .monospacedSystemFont(ofSize: 11, weight: .regular)))
        out.append(piece(Self.word(entry.kind).padding(toLength: 9, withPad: " ", startingAt: 0),
                         colour: Self.colour(entry.kind), size: 11,
                         font: .monospacedSystemFont(ofSize: 11, weight: .medium)))
        if let project = entry.project {
            out.append(piece("\(project)  ", colour: Palette.brand, size: 11))
        }
        out.append(piece(entry.text, colour: Palette.primaryText, size: 11))
        out.append(NSAttributedString(string: "\n"))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        // Wrapped text lines up under the first column rather than under the
        // clock, so a long command reads as one thing.
        paragraph.headIndent = 78
        out.addAttribute(.paragraphStyle, value: paragraph,
                         range: NSRange(location: 0, length: out.length))
        return out
    }

    private func line(_ string: String, colour: NSColor, size: CGFloat,
                      weight: NSFont.Weight = .regular,
                      spacingAbove: CGFloat = 0) -> NSAttributedString {
        let out = NSMutableAttributedString(
            string: string + "\n",
            attributes: [.foregroundColor: colour,
                         .font: NSFont.systemFont(ofSize: size, weight: weight)])
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = spacingAbove
        paragraph.paragraphSpacing = 6
        out.addAttribute(.paragraphStyle, value: paragraph,
                         range: NSRange(location: 0, length: out.length))
        return out
    }

    private func piece(_ string: String, colour: NSColor, size: CGFloat,
                       font: NSFont? = nil) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .foregroundColor: colour,
            .font: font ?? NSFont.systemFont(ofSize: size),
        ])
    }

    static func word(_ kind: Journal.Entry.Kind) -> String {
        switch kind {
        case .approved: "approved"
        case .denied: "denied"
        case .abandoned: "gave up"
        case .arrived: "asked"
        case .asked: "you said"
        case .answered: "said"
        case .spoke: "an agent said"
        }
    }

    static func colour(_ kind: Journal.Entry.Kind) -> NSColor {
        switch kind {
        case .approved: Palette.hex(0x5CE1A5)
        case .denied: Palette.hex(0xFF5B5B)
        case .abandoned: Palette.secondaryText
        case .arrived: Palette.hex(0x4FC7FF)
        case .asked: Palette.hex(0xF6B94E)
        case .answered: Palette.brand
        case .spoke: Palette.brand
        }
    }

    /// For the offscreen preview only.
    var contentViewForPreview: NSView? { window?.contentView }

    private var isScrolledToEnd: Bool {
        guard let scroll else { return true }
        let visible = scroll.contentView.documentVisibleRect
        let height = scroll.documentView?.bounds.height ?? 0
        return visible.maxY >= height - 40
    }

    private func scrollToEnd() {
        text.scrollToEndOfDocument(nil)
    }
}
