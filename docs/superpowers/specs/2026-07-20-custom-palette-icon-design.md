# Custom Palette Icon — Design

Date: 2026-07-20. Approved by Jewei. Baseline: main after brand-keycap fix, 167 tests.

## Goal

Let the user replace the palette header's brand keycap with their own image
(e.g. an avatar). Palette mark only — the Dock/Finder icns stays the Bopop keycap.

## Decisions

- Settings → new "Appearance" section: "Palette icon" row with
  "Choose Image…" and, when a custom image is active, "Reset to Default".
  NSOpenPanel: png/jpeg/heic/tiff, single file.
- Import = copy, not reference: decode, aspect-fill square-crop, downscale to
  128×128 px, write PNG to `Storage.baseDirectory/brand.png` (0600 — reuse the
  Storage permission conventions; add `brandImageURL` to Storage). Original file
  is never referenced again.
- State: the presence of `brand.png` IS the flag (no separate defaults key —
  one source of truth). Reset deletes the file.
- Rendering: `PaletteBrandView` gains an image mode — the custom image masked to
  the SAME continuous-corner rounded square (radius = height × 0.24) the keycap
  uses. Missing/undecodable file → keycap, silently.
- Refresh: the palette controller re-checks the file on every `show()` (cheap
  stat + cached NSImage invalidated by modification date), so a Settings change
  applies to the next summon without restart.
- Import failures (undecodable file) → no write, settings row shows a one-line
  error text (same style as launchAtLoginError).

## Testing

Kit has no part in this (pure app-target) except `Storage.brandImageURL`.
Testable pieces live in an `ImageImporter` helper if put in the app target —
BUT the crop/downscale math is pure: put `BrandImageImporter` in BopopKit
(Foundation + CoreGraphics? NO — Kit is Foundation+os only; CGImage needs
CoreGraphics which Foundation re-exports on Apple platforms, but ImageIO is off
limits). Resolution: importer lives in the APP target (AppKit NSImage);
Kit gets only `Storage.brandImageURL` + a test that the URL is under
baseDirectory. App-target import pipeline is verified by manual QA plus a
small in-app debug assertion path; keep the importer function pure-ish
(NSImage in → PNG data out) so a future app-target test bundle could cover it.

## Out of scope

Runtime Dock icon replacement, multiple icons, sync.
