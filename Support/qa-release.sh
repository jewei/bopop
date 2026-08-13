#!/usr/bin/env bash
# Manual release QA for behavior that the automated suite cannot exercise.
#
# Usage:
#   Support/qa-release.sh [--version X.Y.Z]
#   Support/qa-release.sh --version X.Y.Z --check
#
# Results default to <repo>/.qa-results. A sheet is valid only for the exact
# commit and version it names. Pass QA_RESULTS_FILE to keep parallel sheets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_FILE="${QA_RESULTS_FILE:-$PROJECT_DIR/.qa-results}"
CURRENT_COMMIT="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_DIR/Support/Info.plist")"
CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --version)
      [[ $# -ge 2 ]] || { printf 'error: --version needs X.Y.Z\n' >&2; exit 2; }
      CURRENT_VERSION="$2"
      shift 2
      ;;
    *)
      printf 'usage: %s [--version X.Y.Z] [--check]\n' "$0" >&2
      exit 2
      ;;
  esac
done
if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'error: version %s is not MAJOR.MINOR.PATCH\n' "$CURRENT_VERSION" >&2
  exit 2
fi
QA_DISK_IMAGE="$PROJECT_DIR/dist/Bopop-QA-$CURRENT_VERSION.dmg"

EXPECTED_CHECKS=(
  QA_LAUNCH QA_EMOJI_TRANSIENT
  QA_TRASH_CONFIRM QA_FINDER_CONSENT QA_EJECT
  QA_LOGOUT QA_RESTART QA_SHUTDOWN
  QA_PW_CAPTURED QA_PW_SCRUBBED
  QA_QL_OPEN QA_QL_ESC QA_QL_TOGGLE QA_REVEAL
  QA_LT_OPEN QA_LT_TOGGLE QA_LT_AUTODISMISS
  QA_SNIPPETS_CRUD QA_SNIPPETS_PERSIST
  QA_SEARCH_VALIDATION QA_SEARCH_USE QA_SEARCH_PICKERS
  QA_FILES_ADD QA_FILES_FIND QA_FILES_REMOVE
  QA_ICON_CHOOSE QA_ICON_RESET QA_ICON_FALLBACK
  QA_CLAMP_MAIN QA_CLAMP_SECONDARY
  QA_SPOTLIGHT_WARNING QA_SPOTLIGHT_RECOVER QA_HOTKEY_DUPLICATE_HONESTY
  QA_SCRIPT_TIMEOUT
)

existing_value() {
  [[ -f "$RESULTS_FILE" ]] || return 1
  local line
  line="$(grep -E "^${1}=" "$RESULTS_FILE" | tail -n 1)" || return 1
  printf '%s' "${line#*=}"
}

write_value() {
  local key="$1" value="$2" temporary
  mkdir -p "$(dirname "$RESULTS_FILE")"
  touch "$RESULTS_FILE"
  temporary="$(mktemp "${TMPDIR:-/tmp}/bopop-qa.XXXXXX")"
  grep -vE "^${key}=" "$RESULTS_FILE" >"$temporary" || true
  printf '%s=%s\n' "$key" "$value" >>"$temporary"
  mv "$temporary" "$RESULTS_FILE"
}

print_release_status() {
  local blocked=0 key value sheet_commit sheet_version
  sheet_commit="$(existing_value QA_COMMIT || true)"
  sheet_version="$(existing_value QA_VERSION || true)"

  if [[ "$sheet_commit" != "$CURRENT_COMMIT" ]]; then
    printf 'blocked: QA sheet commit is %s; current commit is %s\n' \
      "${sheet_commit:-missing}" "$CURRENT_COMMIT" >&2
    blocked=1
  fi
  if [[ "$sheet_version" != "$CURRENT_VERSION" ]]; then
    printf 'blocked: QA sheet version is %s; current version is %s\n' \
      "${sheet_version:-missing}" "$CURRENT_VERSION" >&2
    blocked=1
  fi

  for key in "${EXPECTED_CHECKS[@]}"; do
    value="$(existing_value "$key" || true)"
    case "$value" in
      pass|skip-reviewed:*) ;;
      "") printf 'blocked: %s has no verdict\n' "$key" >&2; blocked=1 ;;
      FAIL:*) printf 'blocked: %s=%s\n' "$key" "$value" >&2; blocked=1 ;;
      skip-unreviewed:*) printf 'blocked: %s=%s\n' "$key" "$value" >&2; blocked=1 ;;
      *) printf 'blocked: %s has invalid verdict %s\n' "$key" "$value" >&2; blocked=1 ;;
    esac
  done

  if [[ "$blocked" == "0" ]]; then
    write_value QA_RELEASE_STATUS ready
    printf 'ready: manual QA passed for Bopop %s at %s\n' \
      "$CURRENT_VERSION" "$CURRENT_COMMIT"
    return 0
  fi
  write_value QA_RELEASE_STATUS blocked
  return 1
}

if [[ "$CHECK_ONLY" == "1" ]]; then
  print_release_status
  exit
fi

if [[ ! -t 0 ]]; then
  printf 'qa-release.sh needs an interactive terminal. Run it directly.\n' >&2
  exit 2
fi

if [[ -f "$RESULTS_FILE" ]] && grep -q '^QA_' "$RESULTS_FILE"; then
  sheet_commit="$(existing_value QA_COMMIT || true)"
  if [[ -z "$sheet_commit" ]]; then
    printf 'error: %s is a legacy sheet with no commit identity.\n' "$RESULTS_FILE" >&2
    printf 'Move it aside, then run this checklist again; old verdicts are not release evidence.\n' >&2
    exit 2
  elif [[ "$sheet_commit" != "$CURRENT_COMMIT" ]]; then
    printf 'error: %s belongs to commit %s, not %s.\n' \
      "$RESULTS_FILE" "$sheet_commit" "$CURRENT_COMMIT" >&2
    printf 'Use a different QA_RESULTS_FILE or archive the old sheet first.\n' >&2
    exit 2
  fi
fi

write_value QA_COMMIT "$CURRENT_COMMIT"
write_value QA_VERSION "$CURRENT_VERSION"
write_value QA_RELEASE_STATUS incomplete

stage_number=0
stage() {
  stage_number=$((stage_number + 1))
  printf '\n== Stage %s/13: %s ==\n' "$stage_number" "$1"
}
step() { printf '  - %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
pause() { printf '  %s ' "${1:-Press Enter to continue.}"; read -r _; }

verdict() {
  local key="$1" prompt="$2" current answer detail reviewed
  current="$(existing_value "$key" || true)"
  while true; do
    if [[ -n "$current" ]]; then
      printf '  %s [p/f/s; recorded: %s; Enter keeps] ' "$prompt" "$current"
    else
      printf '  %s [p/f/s] ' "$prompt"
    fi
    read -r answer
    if [[ -z "$answer" && -n "$current" ]]; then return; fi
    case "$answer" in
      p|P) write_value "$key" pass; return ;;
      f|F)
        printf '  What failed? '; read -r detail
        write_value "$key" "FAIL: ${detail:-no detail}"
        return
        ;;
      s|S)
        printf '  Why is this skipped? '; read -r detail
        printf '  Has the release owner reviewed and accepted this skip? [y/N] '; read -r reviewed
        if [[ "$reviewed" =~ ^[Yy]$ ]]; then
          write_value "$key" "skip-reviewed: ${detail:-no detail}"
        else
          write_value "$key" "skip-unreviewed: ${detail:-no detail}"
        fi
        return
        ;;
      *) printf '  Answer p, f, or s.\n' ;;
    esac
  done
}

printf '\nBopop %s manual release QA\nCommit: %s\nResults: %s\n' \
  "$CURRENT_VERSION" "$CURRENT_COMMIT" "$RESULTS_FILE"
note 'A ready verdict requires every check: pass or an explicitly reviewed skip.'
pause 'Press Enter to start or resume.'

stage 'Build and launch the isolated dev app'
step 'The build uses the .dev identity, but this quits every running process named Bopop to avoid hotkey contention.'
pause 'Press Enter to quit Bopop and build.'
killall Bopop >/dev/null 2>&1 || true
build_log="$(mktemp "${TMPDIR:-/tmp}/bopop-qa-build.XXXXXX")"
if make -C "$PROJECT_DIR" open >"$build_log" 2>&1; then
  printf '  Build launched.\n'
else
  tail -n 20 "$build_log" >&2
  printf 'error: build failed; full log: %s\n' "$build_log" >&2
  exit 1
fi
rm -f "$build_log"
step 'Summon the palette and type a few letters.'
verdict QA_LAUNCH 'Palette appears and filters?'
step "Type ':fire' and watch the switch to the emoji grid."
verdict QA_EMOJI_TRANSIENT 'Grid switch has no wrong-height frame or flicker?'

stage 'Finder Automation consent and disk ejection'
step 'Put a disposable file in Trash. Empty Trash really deletes it.'
step "Run 'Empty Trash…', verify Bopop confirms, then allow the Finder Automation sheet."
verdict QA_TRASH_CONFIRM 'Bopop confirmation appeared?'
verdict QA_FINDER_CONSENT 'Finder consent appeared when applicable, and Trash emptied?'
rm -f "$QA_DISK_IMAGE"
hdiutil create -quiet -volname "Bopop QA $CURRENT_VERSION" \
  -srcfolder "$PROJECT_DIR/dist/Bopop.app" -ov -format UDZO "$QA_DISK_IMAGE"
step "Open $QA_DISK_IMAGE, then run 'Eject All Disks'."
verdict QA_EJECT 'The QA volume unmounted without a Bopop confirmation?'

stage 'loginwindow confirmations — cancel every dialog'
step "Run 'Log Out…', then cancel the macOS dialog."
verdict QA_LOGOUT 'Log Out dialog appeared and cancel was safe?'
step "Repeat for 'Restart…' and cancel."
verdict QA_RESTART 'Restart dialog appeared and cancel was safe?'
step "Repeat for 'Shut Down…' and cancel."
verdict QA_SHUTDOWN 'Shut Down dialog appeared and cancel was safe?'

stage 'Apple Passwords clipboard scrub'
note 'Apple Passwords does not mark copied text secret. This checks the upstream-clear heuristic.'
step 'Copy two passwords, then open Clipboard mode.'
verdict QA_PW_CAPTURED 'Both are temporarily visible (the observed platform behavior)?'
step 'Wait a full two minutes without copying anything else, then check again.'
pause 'Press Enter after two minutes.'
verdict QA_PW_SCRUBBED 'Both passwords are gone, not just the newest?'

stage 'Quick Look key handoff and toggle'
step "Select a file result, open actions with Command-K, then press Command-Y."
verdict QA_QL_OPEN 'Quick Look opened and stayed open?'
step "Close Quick Look with its own Escape."
verdict QA_QL_ESC 'Palette remained open after Escape?'
step "Open it again through actions, then press Command-Y while Quick Look has focus."
verdict QA_QL_TOGGLE 'Command-Y closed Quick Look?'
step "With actions open on the file, press Command-Return."
verdict QA_REVEAL 'Finder revealed the file?'

stage 'Large Type end to end'
step "Select text, open actions with Command-K, then press Command-L."
verdict QA_LT_OPEN 'Large Type opened, legible and sensibly sized?'
step 'Press Command-L again while Large Type has focus.'
verdict QA_LT_TOGGLE 'Large Type closed?'
step 'Open it again, then switch to another app.'
verdict QA_LT_AUTODISMISS 'Large Type dismissed on genuine focus loss?'

stage 'Settings: snippets persistence'
step 'Add and edit a snippet; add a second and delete it.'
verdict QA_SNIPPETS_CRUD 'Snippet add/edit/delete worked?'
step "Quit and relaunch with 'make -C $PROJECT_DIR open', then reopen Settings."
verdict QA_SNIPPETS_PERSIST 'The surviving snippet persisted?'
step 'Delete the QA snippet before leaving Settings.'

stage 'Settings: custom search and pickers'
step "Add a search, then verify reserved keyword 'f' shows a reason."
verdict QA_SEARCH_VALIDATION 'Reserved keyword was visibly rejected?'
step 'Run the valid search from the palette.'
verdict QA_SEARCH_USE 'It opened the expected browser URL?'
step 'Change the search engine and Chinese translation variant.'
verdict QA_SEARCH_PICKERS 'Both settings changed and persisted?'
step 'Remove the QA custom search and restore your preferred pickers.'

stage 'Settings: file-search scopes'
step 'Add a folder using the picker.'
verdict QA_FILES_ADD 'Folder was added?'
step 'Find a known file in it with the file-search prefix.'
verdict QA_FILES_FIND 'File was found?'
step 'Remove the folder and repeat the search.'
verdict QA_FILES_REMOVE 'Removed scope no longer contributes results?'

stage 'Settings: custom palette image'
step 'Choose a real image for the palette icon.'
verdict QA_ICON_CHOOSE 'Image appeared with a square crop?'
step 'Reset to default.'
verdict QA_ICON_RESET 'Violet keycap returned?'
step 'Choose a text file renamed with a .png suffix.'
verdict QA_ICON_FALLBACK 'Invalid image kept the default instead of a blank icon?'

stage 'Real screen geometry'
step 'Move the palette near the bottom and grow the results.'
verdict QA_CLAMP_MAIN 'Palette stayed fully on the main screen?'
step 'Repeat on a secondary display or with Stage Manager, if available.'
verdict QA_CLAMP_SECONDARY 'Secondary/Stage Manager geometry worked?'

stage 'Global-hotkey honesty and Spotlight recovery'
note 'Carbon does not establish cross-process shortcut exclusivity. Bopop must not claim that it does.'
step 'Assign Command-Space to both Spotlight and Bopop, then open Settings > Shortcut.'
verdict QA_SPOTLIGHT_WARNING 'The specific Spotlight warning appeared?'
step 'Disable Spotlight’s shortcut and press Re-check.'
verdict QA_SPOTLIGHT_RECOVER 'Warning cleared and Command-Space opened Bopop?'
step 'Give another launcher a non-default shortcut that Bopop also uses, then relaunch Bopop.'
verdict QA_HOTKEY_DUPLICATE_HONESTY 'Bopop avoided the unsupported “another app owns this shortcut” claim?'
step 'Observe which app receives the duplicate chord and record surprises as a failure; restore both apps afterward.'

stage 'Script output-drain timeout'
step 'Create executable holds-pipe.sh in the Scripts folder:'
note '#!/bin/bash'
note 'echo hello'
note 'sleep 30 &'
step 'Run it and wait about two seconds.'
verdict QA_SCRIPT_TIMEOUT "Output kept 'hello' and added '(output truncated: descendant still holds the pipe)'?"
step 'Delete holds-pipe.sh from the Scripts folder.'

rm -f "$QA_DISK_IMAGE"
printf '\nRelease verdict:\n'
if print_release_status; then
  exit 0
fi
printf '\nManual QA is blocked. Fix failures and review every skip, then resume this sheet.\n' >&2
exit 1
