import AppKit
import BopopKit

/// Self-contained scroll view wrapping the emoji tile grid's
/// `NSCollectionView` — mirrors the (scrollView, tableView) pair the list
/// uses, bundled into one type since the flow-layout configuration below
/// is grid-specific and has no other caller. `PaletteController` owns one
/// instance, wires `collectionView`'s data source/delegate to itself
/// (same pattern as `tableView`), and toggles `isHidden` opposite the
/// table's scroll view — the two never show simultaneously.
final class EmojiGridView: NSScrollView {
    let collectionView = PaletteCollectionView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func configureView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(
            width: PaletteMetrics.gridTileSize,
            height: PaletteMetrics.gridTileSize
        )
        layout.minimumInteritemSpacing = PaletteMetrics.gridSpacing
        layout.minimumLineSpacing = PaletteMetrics.gridSpacing
        layout.sectionInset = NSEdgeInsets()

        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            EmojiTileItem.self,
            forItemWithIdentifier: EmojiTileItem.reuseIdentifier
        )

        documentView = collectionView
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(
            top: PaletteMetrics.listTopInset,
            left: PaletteMetrics.listSideInset,
            bottom: PaletteMetrics.listBottomInset,
            right: PaletteMetrics.listSideInset
        )
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
    }
}

/// Keyboard focus must never leave the query field (same reasoning as
/// `tableView.refusesFirstResponder` in PaletteLayout) — a tile click
/// would otherwise make the collection view first responder and Return
/// would stop reaching the field editor's doCommandBySelector.
/// `NSCollectionView` has no `refusesFirstResponder` convenience property
/// like `NSTableView`, so this subclass overrides `acceptsFirstResponder`
/// directly.
final class PaletteCollectionView: NSCollectionView {
    override var acceptsFirstResponder: Bool { false }
}

final class EmojiTileItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("EmojiTileItem")

    // A `lazy var` rather than an IBOutlet: AppKit can toggle `isSelected`
    // during collection-view reuse/prepare before `loadView()` has been
    // triggered (HANDOVER gotcha #4's analog for table rows — item state
    // can be asked for before layout). Accessing this property is itself
    // what forces first creation, so there is no nil-outlet window to
    // guard against.
    private lazy var tileContentView = EmojiTileContentView()

    override func loadView() {
        view = tileContentView
    }

    override var isSelected: Bool {
        didSet {
            tileContentView.setSelected(isSelected)
        }
    }

    func configure(with result: SearchResult) {
        tileContentView.configure(with: result)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(result.title)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tileContentView.resetForReuse()
    }
}

/// The tile's visuals: a centered 28pt glyph over a rounded-10 background
/// that switches between three states — idle (clear), hover (white 6%,
/// matching the row icon tile's `tileNeutral` token), and selected (accent
/// 14% fill + 1px accent 30% border, the same selection tokens
/// `PaletteRowView.drawSelection` uses for the list).
private final class EmojiTileContentView: NSView {
    private let glyphLabel = NSTextField(labelWithString: "")
    private var isSelectedTile = false
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateStyle()
    }

    func configure(with result: SearchResult) {
        // EmojiProvider's `id` is the raw emoji character itself (see
        // `EmojiProvider.makeResult`) — the tile shows just the glyph,
        // unlike the list row's "glyph  name" title.
        glyphLabel.stringValue = result.id
    }

    func setSelected(_ selected: Bool) {
        isSelectedTile = selected
        updateStyle()
    }

    func resetForReuse() {
        isSelectedTile = false
        isHovered = false
        updateStyle()
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerRadius = PaletteMetrics.gridTileRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        glyphLabel.font = .systemFont(ofSize: PaletteMetrics.gridGlyphSize)
        glyphLabel.alignment = .center
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyphLabel)

        NSLayoutConstraint.activate([
            glyphLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateStyle()
    }

    private func updateStyle() {
        if isSelectedTile {
            layer?.backgroundColor = NSColor.bopopAccent.withAlphaComponent(0.14).cgColor
            layer?.borderColor = NSColor.bopopAccent.withAlphaComponent(0.30).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.clear.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
        }
    }
}
