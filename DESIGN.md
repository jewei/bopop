# Bopop Design System — v2 "Minimal Mono"

Source: Claude design export `~/Downloads/next-generation-productivity-launcher` option **1a (Minimal Mono — dark glass, restrained)**. The palette is committed dark glass regardless of system appearance; the Settings window follows the system. Fonts are native equivalents: Inter → SF Pro (system), JetBrains Mono → SF Mono (`.monospacedSystemFont`). No bundled fonts.

## Color (palette surface — dark-committed, literal values)

| Token | Value | Usage |
|---|---|---|
| `accent` | `#7c5cff` | THE brand violet: selection tint/border, brand square, keycap emphasis, settings tint |
| `accentDeep` | `#5b3ff0` | Gradient partner (tiles, icon) |
| `accentSoft` | `#a48bff` | Gradient partner (brand square), icon dot |
| `panelTint` | `rgba(22,20,30,0.72)` | Overlay on the blur material |
| `panelBorder` | `white 10%` | 1px hairline edge |
| `hairline` | `white 7%` | Header/footer separators |
| `textPrimary` | `white` | Query text, selected title |
| `textStrong` | `white 85%` | Unselected titles |
| `textSecondary` | `white 45%` | Subtitles, footer, esc keycap |
| `tileNeutral` | `white 6%` | Symbol icon tiles |
| `keycapBorder` | `white 15%` | Keycap outlines |
| Selection | fill `#7c5cff` 14%, border 1px `#7c5cff` 30% | Selected row |

Settings window: system appearance + `.tint(#7c5cff)`. App icon: gradient `#7c5cff→#5b3ff0`, white rounded "b", `#a48bff` dot.

## Typography (SF Pro / SF Mono)

| Element | Spec |
|---|---|
| Query field | 34 heavy (`.heavy`), tracking −0.02em, white; placeholder white 35% |
| Row title | 14.5 semibold (selected) / 14 medium, textStrong |
| Row subtitle | 11.5 / 11 regular, textSecondary, 2pt below title |
| Footer + keycaps + chip | SF Mono medium 11 (keycap ↵ 10) |

## Layout & metrics

- Panel: width 620, radius 20 continuous, `NSVisualEffectView` (dark appearance forced) + `panelTint` overlay, 1px `panelBorder`, heavy shadow.
- Header: 76 tall, insets 24; contents: 20×20 radius-6 brand square (gradient `#7c5cff→#a48bff`, 135°) · query field · `esc` keycap (SF Mono 11, textSecondary, border keycapBorder, radius 6, padding 8×3). 1px hairline below.
- List: insets 8 top / 10 sides / 14 bottom; row height 52; 4pt gap between rows (intercell); row content padding 14 h; selection radius 10.
- Rows: 32×32 leading icon — real app/file icons raw; symbol results in a radius-8 tile (`tileNeutral`; selected row's tile: gradient `#7c5cff→#5b3ff0`, white symbol). Two-line text block (single line vertically centered when no subtitle). Selected row shows trailing `↵` keycap.
- Footer: 40 tall, insets 22, hairline above, SF Mono 11 textSecondary. Left: "Bopop" (or mode/status text). Right: `↑↓ navigate` · `⌘C copy` · `↵ select` (⌘K reserved until an actions menu exists) · trailing gearshape button (borderless, textSecondary → white 0.8 on hover) opening the Settings/Scripts/Quit menu — replaces the old menu-bar status item.
- Mode chip (Files/Clipboard/Emoji/Translation): SF Mono 11, accent text on accent 15% pill, radius 10, after the brand square.

## Hero answer card

Shown between the query field and the results list whenever the top-ranked result carries hero
content (calculator, currency, timezone, URL cleaner, translation); that result's normal row is
suppressed from the list to avoid duplication.

- Height 96 (`PaletteMetrics.heroHeight`), card background white 0.04, radius 10 (plain layer
  `cornerRadius` — this sits inside the already-masked panel, so gotcha #5's `maskImage` requirement
  doesn't apply here, only to the panel's own blur material).
- Horizontal three-pane split: left pane (input), center column, right pane (answer), separated by
  1px hairline (white 0.07) verticals.
- Left/right pane: value 22 pt monospaced medium, white 0.92; optional badge below as a rounded-rect
  chip, 11 pt, white 0.55 text on white 0.08 fill.
- Center: → glyph 20 pt white 0.55, with an optional note (e.g. "Updated 2 hours ago") 10 pt white
  0.35 underneath.
- Text is non-editable, single line, truncates in the middle (long URLs, long translations).
- Footer verb reflects the hero's action: "copy" for calculator/currency/timezone/emoji/translation,
  "open" for the URL cleaner (Return opens the cleaned link in the default browser instead of
  copying it).

## Motion

None. Instant show/hide.

## Accessibility

Dark-committed palette: all text tokens above pass ≥ 4.5:1 on the tinted glass (white 45% floor ≈ 4.6:1 on `#16141e`). VoiceOver labels unchanged; keycaps stay accessibility-hidden.
