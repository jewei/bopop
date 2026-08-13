# Design system

Bopop is instant, native, restrained, and keyboard-first. The palette is a
dark-committed glass surface so it remains legible over unpredictable desktop,
Space, and full-screen content. Settings follows the system appearance and uses
the Bopop accent tint.

This document records intent. Code is authoritative for exact constants:

- `Sources/Bopop/PaletteMetrics.swift` — dimensions and geometry inputs.
- `Sources/Bopop/BrandColor.swift` — brand violet ramp.
- `Sources/Bopop/PaletteLayout.swift` — palette material, typography, and layout.
- `Sources/Bopop/ResultRowView.swift`, `PaletteHeroView.swift`,
  `PaletteTabsView.swift`, and `EmojiGridView.swift` — component rendering.
- `Support/generate-icon.swift` — application icon rendering.

## Stable visual grammar

- Palette: 620 pt wide, 20 pt continuous radius, dark blur plus tint, one-pixel
  border, no decorative motion.
- Brand: accent `#7c5cff`, deep `#5b3ff0`, soft `#a48bff`. The drawn header
  keycap and application icon share this ramp.
- Query: SF Pro Rounded, 22 pt semibold, with the TextKit 1 block cursor described
  in gotcha 11.
- Supporting UI: SF Mono for tabs, keycaps, badges, and footer hints.
- Modes: the always-visible tab row is the sole mode indicator. Its height is
  currently 40 pt (`PaletteMetrics.tabsHeight`). Tab and Shift-Tab cycle modes.
- Results: 52 pt list rows or a 10-column emoji grid. A hero answer suppresses
  its duplicate list row.
- Actions: Command-K opens the actions panel; it is not a reserved future chord.
  The panel remains non-key so the query field retains focus.
- Settings: system appearance, Bopop tint, currently fixed at 380 × 530 pt.

## Accessibility

Every interactive row or repeated button needs a distinguishable VoiceOver
label. Keycaps that merely repeat keyboard hints remain accessibility-hidden.
The palette's literal text colors must retain at least 4.5:1 contrast on its
dark tinted surface. Settings uses semantic system colors.

There is intentionally no palette animation. Pointer behavior supplements the
keyboard path; it does not replace it. Visual changes need a live pass because
the off-screen AppKit test host does not reproduce every delegate and focus
interaction; see `testing.md`.
