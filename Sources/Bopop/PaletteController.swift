import AppKit

final class PaletteController: NSObject, NSTextFieldDelegate {
    private static let panelSize = NSSize(width: 640, height: 60)

    private let panel: PalettePanel
    private let queryField = NSTextField()
    private var isHiding = false

    override init() {
        panel = PalettePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let top = visibleFrame.maxY - (visibleFrame.height * 0.25)
        let origin = NSPoint(
            x: visibleFrame.midX - (Self.panelSize.width / 2),
            y: top - Self.panelSize.height
        )
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
    }

    func hide() {
        guard !isHiding else {
            return
        }

        isHiding = true
        defer { isHiding = false }
        panel.orderOut(nil)
        queryField.stringValue = ""
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.onResign = { [weak self] in
            self?.hide()
        }

        let contentView = NSVisualEffectView()
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        queryField.isEditable = true
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 22)
        queryField.placeholderString = "Search"
        queryField.delegate = self
        queryField.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(queryField)
        NSLayoutConstraint.activate([
            queryField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            queryField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            queryField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        panel.contentView = contentView
    }
}
