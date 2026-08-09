import AppKit

/// A brief message over the desktop, in the palette's own styling.
///
/// This exists instead of a user notification. Bopop is a local launcher, and
/// asking for the Notifications permission the first time a script finishes is
/// a poor trade for a message about something the user just did themselves —
/// and a denied prompt made script results invisible for good.
///
/// Non-activating and non-key, like the actions panel, so showing one never
/// steals focus from whatever the action just opened.
@MainActor
final class MessageHUDController {
    private var panel: NSPanel?
    var panelForTesting: NSPanel? { panel }
    private var dismissTask: Task<Void, Never>?

    private static let width: CGFloat = 380
    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 14

    /// Longer for failures: they carry a path or a reason worth reading, and
    /// the user has no other record of them.
    func show(_ message: String, isFailure: Bool) {
        hide()
        guard let screen = NSScreen.main else {
            return
        }

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = Self.width - Self.horizontalPadding * 2

        let container = MessageHUDBackgroundView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: Self.horizontalPadding
            ),
            label.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            label.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: Self.verticalPadding
            ),
            label.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -Self.verticalPadding
            )
        ])

        let height = label.intrinsicContentSize.height + Self.verticalPadding * 2
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - Self.width / 2,
            y: visible.minY + visible.height * 0.12,
            width: Self.width,
            height: max(height, 44)
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // The same style every other Bopop overlay uses. Hand-rolling this was
        // the bug that made the HUD invisible: without `.canJoinAllSpaces` and
        // `.fullScreenAuxiliary` it only appears on the Space it was created
        // on, and `.floating` sits below a full-screen app.
        panel.applyBopopOverlayStyle()
        panel.ignoresMouseEvents = true
        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isFailure ? 5 : 2.5))
            guard !Task.isCancelled else {
                return
            }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Matches the actions panel: near-opaque, since a HUD over arbitrary desktop
/// content has no behind-window blur to lean on.
private final class MessageHUDBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            srgbRed: 22 / 255,
            green: 20 / 255,
            blue: 30 / 255,
            alpha: 0.97
        ).cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}

extension MessageHUDController {
    /// The panel currently on screen, for tests. There is no other way to
    /// observe a borderless non-key panel from outside.
    var visiblePanelForTesting: NSPanel? { panelForTesting }
}
