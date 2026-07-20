# Emoji Grid — Design

Date: 2026-07-20. Approved direction from Jewei (Raycast-style grid reference).
Baseline: main at the SF-Pro-Rounded/ellipsis commits, 168 tests.

## Goal

Emoji mode renders a grid of emoji tiles (10 columns) instead of list rows —
like Raycast's emoji picker. Every other mode keeps the table.

## Decisions

- NSCollectionView (flow layout) lives alongside the table in the palette;
  visible only in emoji mode (hero rule untouched — emoji mode has no hero).
- 10 columns. Tile 52×52, radius 10 continuous, emoji glyph 28pt centered.
  Hover: white 6% fill. Selected: accent 14% fill + 1px accent 30% border
  (same tokens as row selection). Insets match listSideInset.
- Data: the SAME ranked [SearchResult] pipeline — grid is a view swap, not a
  new data path. EmojiProvider's empty-term result changes from top-24 to the
  FULL catalog ordered frecency-first (ties in catalog order) so the grid
  scrolls through everything; with a term, Ranker output order fills the grid
  left-to-right, top-to-bottom.
- Keyboard: ←/→ move ±1, ↑/↓ move ±10 (clamped, no wrap), grid scrolls to keep
  selection visible. Return copies selected emoji (existing action). Click on
  a tile copies (same as rowClicked). Esc chain unchanged. ⇥ still cycles tabs.
- Footer in emoji mode: "↵ copy", status shows result count ("1,914 emoji" /
  "12 matches").
- Panel height in emoji mode: 5 tile-rows visible (~300pt content) then
  scrolls; sizing follows the same panelHeight pattern.
- Selection state: selectedIndex continues to index into `results` — the grid
  and table never show simultaneously, so the controller's single index works
  for both; only the ±offset arithmetic differs per mode.
- VoiceOver: each tile is accessibility element with the emoji name.

## Deferred (follow-up, needs emoji.json regeneration with a group field)

Category section headers with counts ("Smileys & People 559"), category
jump dropdown.

## Testing

Kit: EmojiProvider empty-term = full catalog frecency-first (update existing
test), non-empty unchanged. Grid math (index↔row/col clamping) extracted into
a pure Kit helper `GridNavigation.move(index:by:columns:count:)` with tests
(edges: first row up, last partial row down, rightmost →). UI: manual QA
screenshots (grid renders, selection border, arrows, click copies).
