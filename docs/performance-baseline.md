# Performance baseline

Bopop uses permanent coarse `OSSignposter` intervals so Instruments can measure real
startup, summon, catalog, query, provider, ranking, and result-application work.
Signposts contain no query text, clipboard content, result titles, paths, or URLs.

## Intervals

| Category | Interval | Meaning |
|---|---|---|
| Lifecycle | `App Construction` | Swift dependency-graph construction after AppKit process startup begins |
| Lifecycle | `Application Did Finish Launching` | Synchronous launch callback work; background warmups are only scheduled |
| Palette | `Palette Show` | Accepted synchronous show call through initial query dispatch |
| Palette | `Results Apply` | Main-actor result splitting, selection, view reload, footer, and resize |
| Catalog | `App Catalog Refresh` | One app scanner pass, including injected test scanners |
| Query | `Query Providers` | Provider fan-out through final completion, after mode debounce |
| Query | `Rank Results` | One incremental ranking pass |
| Provider | `Provider Results` | One provider invocation; concurrent intervals may overlap |
| Provider | `Clipboard Results Build` | Building clipboard rows from a history snapshot |
| Catalog | `Script Catalog Scan` | One scripts-directory scan; runs per keystroke in General mode |

`Palette Show` is CPU/control-flow duration, not literal hotkey-to-first-photon latency.
`Query Providers` excludes debounce sleep because it begins inside `runProviders`.

## Build a release-optimized dev identity

Never profile a source build with release identity; that could read installed Bopop data.

```sh
make BUNDLE_ID=com.oneone.bopop.dev BUNDLE_NAME='Bopop Dev' app
```

## Record signposts

Two things that will otherwise waste an evening:

- **`log stream` cannot see these.** Signposts are no-ops unless a tracing tool
  enables them, which is what makes them free in shipping builds. Only a
  recording session materialises them.
- **`xctrace --launch` matches by bundle name.** With an installed `Bopop.app`
  present it refuses with `Provided process ... is ambiguous`, or silently
  profiles the installed copy. Stage the dev build under a unique name first.
  Xcode 26 also has no `Points of Interest` template; `Logging` records the
  `os-signpost` tables.

```sh
make BUNDLE_ID=com.oneone.bopop.dev BUNDLE_NAME='Bopop Dev' app

stage="/tmp/bopop-profile-$(uuidgen)"
mkdir -p "$stage"
cp -R dist/Bopop.app "$stage/BopopProfile.app"
mv "$stage/BopopProfile.app/Contents/MacOS/Bopop" \
   "$stage/BopopProfile.app/Contents/MacOS/BopopProfile"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable BopopProfile" \
  "$stage/BopopProfile.app/Contents/Info.plist"
codesign --force --deep --sign - "$stage/BopopProfile.app"

trace="/tmp/bopop-performance-$(uuidgen).trace"
xcrun xctrace record \
  --template 'Logging' \
  --time-limit 20s \
  --output "$trace" \
  --env BOPOP_DEBUG_AUTOSHOW=1 \
  --launch -- "$stage/BopopProfile.app/Contents/MacOS/BopopProfile"
```

Renaming the executable leaves `CFBundleIdentifier` at `com.oneone.bopop.dev`, so
the profiled run still uses dev preferences and dev Application Support.

Read the intervals back out:

```sh
xcrun xctrace export --input "$trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost-interval"]'
```

Filter exported rows to subsystem `com.oneone.bopop.performance`; the same table
also carries WindowServer and CoreAnimation signposts.

During a longer interactive run, exercise these scenarios separately:

1. Cold launch with automatic first palette show.
2. Warm palette show with empty General query.
3. App-name query.
4. Calculator query.
5. Warm emoji query.
6. File query; report debounce separately from provider interval.
7. Idle for 60 seconds, then record CPU and RSS from Activity Monitor or Instruments.

## First recorded observation

One cold run only — enough to prove the instrumentation works and to give later
changes something to move against. Not a budget, and not a p95.

| Field | Value |
|---|---|
| Commit | `824ead9` plus the phase-1 foundation branch |
| Hardware | MacBook Air (Apple silicon, `t8112`) |
| macOS | 15.7.9 (24G830) |
| Instruments | 26.0 (17C529), `Logging` template |
| Build identity | `com.oneone.bopop.dev` |
| Build configuration | Release |
| State | Cold launch, `BOPOP_DEBUG_AUTOSHOW=1`, 12 s recording |
| Runs | 1 |

| Interval | n | Median | Max |
|---|---:|---:|---:|
| `App Construction` | 1 | 58.0 ms | 58.0 ms |
| `Application Did Finish Launching` | 1 | 4.0 ms | 4.0 ms |
| `Palette Show` | 1 | 53.1 ms | 53.1 ms |
| `Results Apply` | 12 | 0.08 ms | 0.50 ms |
| `App Catalog Refresh` | 2 | 49.5 ms | 80.5 ms |
| `Query Providers` | 1 | 2.7 ms | 2.7 ms |
| `Rank Results` | 12 | 0.001 ms | 0.02 ms |
| `Provider Results` | 12 | 0.009 ms | 2.3 ms |

Reading it: ranking and result application are already far below anything worth
optimising, which retires several speculative ideas. The interesting numbers are
`App Construction`, the first `Palette Show` (one-time panel construction), and
`App Catalog Refresh`. Confirm each against several warm runs before acting —
one cold run cannot separate one-time setup from per-summon cost.

## Microbenchmarks, and two rejected optimisations

Debug build, same machine. Recorded with throwaway harnesses that were deleted
afterwards; re-create them if you want to re-measure. Debug overstates absolute
values, but the comparisons below are like for like.

### Script catalog scan

`ScriptsProvider` runs on every keystroke in General mode, and `ScriptCatalog`
scans the directory on every call.

| Scripts on disk | Per scan |
|---:|---:|
| 1 | 55 µs |
| 10 | 316 µs |
| 100 | 3223 µs |

**Decision: no snapshot for now.** A real installation has one or two scripts,
where the scan is 2% of a 2.7 ms query. The cost is linear in file count and
each file costs a `stat` plus an executable check, so revisit this if anyone
keeps tens of scripts. `Script Catalog Scan` is instrumented, so the next
person can check rather than guess.

### Clipboard search

Whole keystroke path, provider plus ranker, for a narrow term:

| Entries | Provider + Ranker |
|---:|---:|
| 50 | 4.8 ms |
| 500 | 47.5 ms |

**Decision: no provider-side pre-filter.** Filtering before building rows —
the shape `AppsProvider` uses — was implemented and measured at 4.5 ms and
45.5 ms, a 4-5% gain. It only moves the folding work out of `Ranker` and into
the provider, while adding a semantic coupling that needs its own test to stop
the two drifting apart. Not worth it.

**The real cost is folding.** Each entry contributes up to 1000 characters of
searchable text, and every keystroke folds all of it for case and diacritics.
That dominates both paths and scales with history size. The default limit is
100 entries; the maximum is 500.

Fixing it properly means one of:

- cache the folded searchable text per entry, since entry text never changes
  after capture — this needs `Ranker` to accept pre-folded candidates;
- shorten the 1000-character searchable prefix, which is a product decision:
  it would stop matching text deep inside a long clip.

Neither is a small change, and neither should start without a release-build
measurement.

## Known gap: release-configuration tests

`swift test -c release` does not build:

```
error: deinit is marked isolated, but containing class 'HotkeyManager' is not
isolated to an actor
```

`swift build -c release` and `make app` are unaffected, so shipping works. It
does mean the numbers above are debug-build numbers.

## Recording template

For real comparisons record at least five runs per scenario and report median and
p95, not the best run.

| Field | Value |
|---|---|
| Commit | |
| Hardware | |
| macOS | |
| Xcode / Swift | |
| Build identity | `com.oneone.bopop.dev` |
| Build configuration | Release |
| Warm/cold state | |
| Run count | |
| Median | |
| p95 | |
| Idle CPU after 60s | |
| RSS after 60s | |
| Release executable size | |

Measurements are observations, not CI gates. Establish warning and failure budgets
only after several accepted releases provide stable data.
