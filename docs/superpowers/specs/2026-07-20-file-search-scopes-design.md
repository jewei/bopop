# File Search Folder Scopes — Design

Date: 2026-07-20. Approved by Jewei. Baseline: main after click-focus fix, 162 tests.

## Goal

User-selected folder scopes for file search — the inverse of Spotlight's Privacy
exclusion list. Narrower scope = faster gathers and less backup/cache noise.

## Decisions

- SCOPING, not indexing. Bopop still never builds an index, watches folders, or
  scans in the background — `NSMetadataQuery.searchScopes` simply receives the
  chosen folder URLs instead of `NSMetadataQueryUserHomeScope`.
- Empty list (default) = current behavior: whole home folder. The list narrows;
  it is never required.
- Settings → new "File Search" section: folder list with +/− buttons. `+` opens
  an NSOpenPanel (canChooseDirectories, multi-select, no files). Rows show
  tilde-abbreviated paths. Duplicates ignored; subfolder-of-existing allowed
  (harmless overlap).
- Persistence: `fileSearchFolders` UserDefaults key, `[String]` of absolute paths.
  Static reader `storedFileSearchFolders(in:)` following the existing pattern.
  A stored path that no longer exists is skipped at query time (not auto-pruned;
  the drive may be temporarily unmounted).
- `FileSearcher` gains `scopeProvider: @Sendable () -> [String]` (paths; empty →
  home scope). Read per search, so Settings changes apply to the next query with
  no restart.
- Footer no-matches hint gains "…or adjust File Search folders in Settings".
- Deferred: early-stop gather (measure after scoping), per-scope toggles, bookmarks.

## Testing

Kit: searcher passes chosen paths as scopes / falls back to home scope when the
list is empty or all paths are missing (assert on the built NSMetadataQuery's
searchScopes via the existing internal seam); missing-path skipping. App: settings
reader default/round-trip. Live behavior: existing opt-in live tests + manual QA.
