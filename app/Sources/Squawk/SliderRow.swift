import AppKit
import SquawkCore

/// A labelled slider sized to sit in the menu. Used for both dial size and
/// opacity, so the two rows line up and behave the same.
@MainActor
final class SliderRow: NSView {
    var onChange: ((Double) -> Void)?

    private let slider = NSSlider()
    private let caption = NSTextField(labelWithString: "")
    private let readout = NSTextField(labelWithString: "")

    private let format: (Double) -> String

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) {
        self.format = format
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 44))

        caption.stringValue = title
        caption.font = .menuFont(ofSize: 0)
        caption.textColor = .labelColor
        readout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        readout.textColor = .secondaryLabelColor
        readout.alignment = .right

        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.target = self
        slider.action = #selector(moved)
        slider.isContinuous = true
        slider.controlSize = .small

        let header = NSStackView(views: [caption, readout])
        header.orientation = .horizontal
        header.distribution = .fill
        caption.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [header, slider])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // The inset matches a standard menu row, so the slider lines up with the
        // titles above and below it.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        refreshReadout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    var value: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue; refreshReadout() }
    }

    @objc private func moved() {
        refreshReadout()
        onChange?(slider.doubleValue)
    }

    private func refreshReadout() {
        readout.stringValue = format(slider.doubleValue)
    }
}
