# Privacy and security

Bopop is local-first, not offline-only.

## Network activity

- Currency conversion is the only query/provider feature that contacts a
  server. It is off by default, requires explicit consent, downloads the daily
  rate table from `frankfurter.dev`, sends no query text, and removes cached
  rates when disabled.
- Released builds use Sparkle for automatic update checks. Sparkle reads the
  appcast hosted on GitHub and may download a GitHub release asset after the
  user accepts an update. Source-built `.dev` bundles do not start the updater.
- Regenerating the committed emoji catalog is a developer action and can fetch
  Unicode and CLDR source data; it is not runtime application traffic.

Translation and dictionary lookup use on-device Apple frameworks. File search
uses Spotlight only after a file query.

## Clipboard history

Settings > Clipboard > Record clipboard history controls new captures. It
defaults on and persists across restarts. Turning it off preserves saved
history and its Clear action. Enabling it skips text copied while it was off.
The watcher continues to check for upstream clears while recording is off,
so the privacy cleanup below remains active. Inactive login sessions still
suspend all polling.

Bopop ignores pasteboard entries marked concealed, transient, or otherwise
sensitive by their source or macOS. That protection depends on the source
setting a marker.

Apple Passwords on the verified macOS 15.7 path exposes copied passwords as
ordinary plain text with no secrecy marker. Such a password can therefore
appear temporarily in Bopop history. Apple Passwords later clears the upstream
pasteboard (observed after roughly 60–90 seconds); Bopop treats that clear as a
signal to delete every recent unpinned capture within a 120-second window.

The heuristic deliberately prefers deleting too much history over retaining a
password. An unrelated recent unpinned copy may be removed too. Pinned entries
are exempt because the clear cannot identify its source and a pin is an explicit
keep decision. Do not pin secrets. This behavior and its platform evidence are
also recorded in gotcha 3 and are mandatory manual release QA.

Clipboard history is stored locally. “Clear Clipboard History” removes
unpinned entries; unpin an item before clearing if it must be removed.

## Generated passwords

The password generator runs entirely locally and draws from
`SecRandomCopyBytes`. Nothing it produces is written to disk: the result row's
identifier names the recipe (`password:strong`), never the password, so the
frecency file records only which recipe was chosen.

The passphrase recipe draws words from a committed local file
(`Resources/wordlist.txt`, BIP-39 English). It contacts no network and consults
no system dictionary or personal word list. Words are drawn with replacement, so
a phrase may repeat a word; rejecting repeats would reduce the entropy that the
row reports on screen.

Copying a generated password uses `ResultAction.copySecret` rather than the
ordinary copy path. That write declares `org.nspasteboard.ConcealedType`
alongside the plain text, which is the marker Bopop's own watcher — and any
clipboard manager following the convention — treats as "never record this".
The password therefore reaches the pasteboard and not the history.

The automated test writes to a scratch pasteboard. The real pasteboard, the
0.5-second poll, and the paste itself are covered by the "Generated passwords
stay out of history" stage in `Support/qa-release.sh`, which is mandatory
release QA.

## Local execution and permissions

- Scripts execute only after Return, via `Process`, using absolute paths and no
  shell interpolation. Script arguments are intentionally unsupported.
- Script capture retains the final 64 KiB of each output stream, including a
  size-omission marker when needed. Captured output goes to the local script
  log. Completion feedback uses the last non-empty output line.
- Bopop does not require Accessibility permission and does not synthesize paste
  or keyboard events into other applications.
- Destructive commands confirm either in Bopop or in the responsible macOS
  service. Finder Automation permission is required for Finder-backed commands
  such as Empty Trash and Eject All Disks.
- JSON stores are written atomically with mode `0600`; corrupt data is
  quarantined rather than silently overwritten.

Privacy-sensitive changes need both automated policy tests and the relevant
manual stage in `Support/qa-release.sh`.
