import AppKit
import TrimshotCore

/// The contents of the floating toolbar: drawing tools, colour, stroke width, undo, and
/// the actions that end the session.
final class ToolbarView: NSVisualEffectView {

    private weak var delegate: ToolbarDelegate?

    private var activeTool: AnnotationTool?
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var widthButtons: [NSButton] = []
    private var undoButton: NSButton?

    /// Tool palette. Kept deliberately small — these are the marks people actually make
    /// on a screenshot during review.
    private static let tools: [(AnnotationTool, String, String)] = [
        (.pen, "pencil.tip", "Freehand"),
        (.line, "line.diagonal", "Line"),
        (.arrow, "arrow.up.right", "Arrow"),
        (.rectangle, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.highlighter, "highlighter", "Highlighter"),
        (.text, "textformat", "Text"),
        (.pixelate, "square.grid.3x3.fill", "Pixelate — hide sensitive content"),
        (.image, "photo", "Place an image — from the clipboard, or pick a file"),
    ]

    private static let palette: [PixelColor] = [
        PixelColor(red: 255, green: 59, blue: 48),
        PixelColor(red: 255, green: 204, blue: 0),
        PixelColor(red: 52, green: 199, blue: 89),
        PixelColor(red: 10, green: 132, blue: 255),
        PixelColor(red: 255, green: 255, blue: 255),
        PixelColor(red: 0, green: 0, blue: 0),
    ]

    private static let widths: [(CGFloat, String)] = [(2, "Thin"), (4, "Medium"), (8, "Thick")]

    init(delegate: ToolbarDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        // Pin the bar to a dark appearance rather than following the system theme. The HUD
        // material is dark either way, so in light mode the symbols were being drawn in
        // `labelColor` — near-black on near-black. Forcing vibrantDark makes every
        // system-derived colour resolve light, which is what this surface needs.
        appearance = NSAppearance(named: .vibrantDark)

        let stack = NSStackView(views: buildSections())
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Construction

    private func buildSections() -> [NSView] {
        var views: [NSView] = []

        for (tool, symbol, tooltip) in Self.tools {
            let button = iconButton(symbol: symbol, tooltip: tooltip, action: #selector(toolTapped))
            button.tag = Self.tools.firstIndex { $0.0 == tool } ?? 0
            toolButtons[tool] = button
            views.append(button)
        }

        views.append(separator())

        for (index, color) in Self.palette.enumerated() {
            let button = swatchButton(color: color)
            button.tag = index
            colorButtons.append(button)
            views.append(button)
        }

        views.append(separator())

        for (index, entry) in Self.widths.enumerated() {
            let button = widthButton(width: entry.0, tooltip: entry.1)
            button.tag = index
            widthButtons.append(button)
            views.append(button)
        }

        views.append(separator())

        let undo = iconButton(
            symbol: "arrow.uturn.backward",
            tooltip: "Undo (⌘Z)",
            action: #selector(undoTapped)
        )
        undoButton = undo
        views.append(undo)

        views.append(
            iconButton(
                symbol: "text.viewfinder",
                tooltip: "Copy text with OCR",
                action: #selector(ocrTapped)
            )
        )

        views.append(separator())

        views.append(
            iconButton(symbol: "doc.on.doc", tooltip: "Copy (⌘C)", action: #selector(copyTapped))
        )
        views.append(
            iconButton(
                symbol: "square.and.arrow.down",
                tooltip: "Save (⌘S)",
                action: #selector(saveTapped)
            )
        )
        views.append(
            iconButton(symbol: "xmark", tooltip: "Cancel (esc)", action: #selector(closeTapped))
        )

        return views
    }

    private func iconButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.contentTintColor = .white
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    private func swatchButton(color: PixelColor) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.toolTip = color.hexString
        button.target = self
        button.action = #selector(colorTapped)
        button.wantsLayer = true
        button.layer?.backgroundColor = CGColor(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalToConstant: 16),
        ])
        return button
    }

    private func widthButton(width: CGFloat, tooltip: String) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.toolTip = "\(tooltip) stroke"
        button.target = self
        button.action = #selector(widthTapped)
        button.wantsLayer = true

        // A filled dot whose size tracks the stroke it selects.
        let dot = CALayer()
        let diameter = 4 + width
        dot.backgroundColor = NSColor.white.cgColor
        dot.cornerRadius = diameter / 2
        dot.frame = CGRect(x: (22 - diameter) / 2, y: (22 - diameter) / 2, width: diameter, height: diameter)
        button.layer?.addSublayer(dot)
        button.layer?.cornerRadius = 5

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 20),
        ])
        return line
    }

    // MARK: - State

    func update(tool: AnnotationTool?, color: PixelColor, width: CGFloat, canUndo: Bool) {
        activeTool = tool
        for (candidate, button) in toolButtons {
            highlight(button, on: candidate == tool)
        }
        for (index, button) in colorButtons.enumerated() {
            let selected = Self.palette[index] == color
            button.layer?.borderWidth = selected ? 2.5 : 1
            button.layer?.borderColor = selected
                ? NSColor.white.cgColor
                : NSColor.white.withAlphaComponent(0.25).cgColor
        }
        for (index, button) in widthButtons.enumerated() {
            highlight(button, on: Self.widths[index].0 == width)
        }

        undoButton?.isEnabled = canUndo
        undoButton?.contentTintColor = canUndo ? .white : NSColor.white.withAlphaComponent(0.3)
    }

    private func highlight(_ button: NSButton, on: Bool) {
        button.layer?.backgroundColor = on
            ? NSColor.white.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor
    }

    // MARK: - Actions

    /// Tapping the active tool turns it off, back to plain selection adjustment.
    @objc private func toolTapped(_ sender: NSButton) {
        let tool = Self.tools[sender.tag].0
        delegate?.toolbarDidSelect(tool: tool == activeTool ? nil : tool)
    }

    @objc private func colorTapped(_ sender: NSButton) {
        delegate?.toolbarDidSelect(color: Self.palette[sender.tag])
    }

    @objc private func widthTapped(_ sender: NSButton) {
        delegate?.toolbarDidSelect(width: Self.widths[sender.tag].0)
    }

    /// Every button in the bar, for the diagnostic that checks they are all wired up.
    func allButtons() -> [NSButton] {
        func collect(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        return collect(self)
    }

    @objc private func undoTapped() { delegate?.toolbarDidTapUndo() }
    @objc private func ocrTapped() { delegate?.toolbarDidTapRecognizeText() }
    @objc private func copyTapped() { delegate?.toolbarDidTapCopy() }
    @objc private func saveTapped() { delegate?.toolbarDidTapSave() }
    @objc private func closeTapped() { delegate?.toolbarDidTapClose() }
}
