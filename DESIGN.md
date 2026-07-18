# Bopop Design System

Mood: **one neon accent in a matte workshop** — a single magenta-plum glow against quiet system materials. The brand lives in the accent and nowhere else; surfaces are always native translucent material, never painted.

## Color

Brand hue 340° (OKLCH), one accent, dynamic per appearance:

| Role | Light | Dark | Usage |
|---|---|---|---|
| `accent` | `#aa2b8a` (oklch 0.52 0.19 340) | `#ec7fca` (oklch 0.74 0.16 340) | Selection tint/edge, mode chip, footer glyph, query caret, settings focus. NOTHING else. |
| `iconBG` | `#6f1859` | same | App icon background only |
| `iconDot` | `#f59cd8` | same | App icon "pop" dot only |

Everything else is a system dynamic color: `labelColor`, `secondaryLabelColor`, `quaternaryLabelColor`, `separatorColor`. Panel/window surfaces: `NSVisualEffectView` `.underWindowBackground`. Never tint a surface with the accent; never use the accent for body text.

Derived accent uses (both appearances must pass):
- Selection capsule: accent at 12% alpha fill (dark) / 9% (light) + 1px inner border accent at 25% alpha. Row text stays `labelColor` on top.
- Mode chip: accent at 14% alpha fill, text in full `accent` (contrast verified ≥ 5.8:1 light, ≥ 6.6:1 dark against material).
- Query caret (`insertionPointColor`) and footer ⌘ glyph: full `accent`.
- Keycaps, badges, separators: stay neutral (informational, not brand).

## Typography

System font only (SF Pro via `.systemFont`). Fixed scale:

| Element | Size / weight | Color |
|---|---|---|
| Query field | 20 regular | labelColor; placeholder secondaryLabelColor |
| Row title | 13 regular | labelColor |
| Row detail (trailing path/kind) | 11 regular | secondaryLabelColor, truncate head |
| Badge / chip / keycap / footer | 11 (badge 10) medium; chip semibold | see color table |

## Spacing & radii

- Panel: width 680, corner 16 continuous, 1px `separatorColor` hairline edge.
- Field area 56 · row 40 · footer 34 · list vertical padding 4 · horizontal inset 16 · selection capsule inset 8, radius 8 · chip radius 6 · keycap radius 4 · icons 22 (rows), 13 (footer).
- Settings window: 380 wide, grouped Form, 20 outer padding.

## Components

- **Palette**: field / hairline / list / footer. Footer always visible: left = mode/status with accent ⌘ glyph, right = verb + `↩` keycap, divider, "Copy" + `⌘C` keycap.
- **Selection**: accent-tinted capsule (above), always emphasized (field keeps first responder).
- **Mode chip**: pill, accent-tinted, text "Files"/"Clipboard".
- **Settings**: SwiftUI grouped Form — Shortcut (recorder w/ accent focus ring), Clipboard (retention stepper), General (launch at login). Same accent, same type scale.
- **App icon**: deep-plum rounded square, white rounded "b" + pale-pink pop dot ("b•").

## Motion

None. A launcher that animates is a launcher that is slow. `animationBehavior = .none` stays.

## Accessibility

Both appearances first-class; every accent use listed above passes ≥ 4.5:1 where it carries text, ≥ 3:1 for large glyphs. VoiceOver labels on rows, field, footer verbs; keycaps hidden from accessibility.
