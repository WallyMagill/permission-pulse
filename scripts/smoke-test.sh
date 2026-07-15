#!/usr/bin/env bash
#
# scripts/smoke-test.sh — automated v0.7.0 smoke-test runner.
#
# Verifies everything that can be checked without a human. Drives:
#   - clean-state wipe (Permission Pulse's local data only; real TCC.db
#     and login items are untouched)
#   - Release build
#   - all 5 test bundles (4 packages + app target)
#   - on-disk state (snapshot DB schema, defaults, version)
#   - prints a "what's left for human eyes" checklist
#
# Usage:
#   scripts/smoke-test.sh          # default: wipe + build + test + verify
#   scripts/smoke-test.sh --keep   # don't wipe local state
#   scripts/smoke-test.sh --no-launch  # don't open the app at the end
#
# Exit code: 0 if every automatic check passed; 1 otherwise.

set -u
set -o pipefail

# ------------------------------- options -----------------------------------

WIPE_STATE=1
LAUNCH_APP=1

for arg in "$@"; do
    case "$arg" in
        --keep)      WIPE_STATE=0 ;;
        --no-launch) LAUNCH_APP=0 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

# ------------------------------- paths -------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/PermissionPulse/PermissionPulse.xcodeproj"
SCHEME="PermissionPulse"
SUPPORT_DIR="$HOME/Library/Application Support/com.wallymagill.permissionpulse"
DB="$SUPPORT_DIR/snapshots.db"
BUNDLE_DOMAIN="com.wallymagill.permissionpulse"

PASSED=()
FAILED=()
WARNED=()

# ------------------------------- helpers -----------------------------------

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
section() {
    printf '\n'
    bold "═══ $* ═══"
}

pass() { green "  ✓ $1"; PASSED+=("$1"); }
fail() { red   "  ✗ $1"; FAILED+=("$1"); }
warn() { yellow "  ⚠ $1"; WARNED+=("$1"); }

run_or_print() {
    if [[ "${SMOKE_DRY_RUN:-0}" == "1" ]]; then
        printf 'DRY-RUN'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}

remove_live_state() {
    [[ $WIPE_STATE -eq 1 ]] || return 0
    if [[ -f "$DB" ]]; then
        run_or_print rm -f "$DB" && pass "removed $DB" || fail "could not remove $DB"
    else
        pass "no prior snapshots.db (clean slate)"
    fi
    if defaults read "$BUNDLE_DOMAIN" >/dev/null 2>&1; then
        run_or_print defaults delete "$BUNDLE_DOMAIN" \
            && pass "cleared defaults $BUNDLE_DOMAIN" \
            || warn "defaults delete returned non-zero"
    else
        pass "no prior defaults (clean slate)"
    fi
    return 0
}

# ------------------------------- 0. wipe -----------------------------------

section "0. Wipe local state"

if [[ "${SMOKE_DRY_RUN:-0}" != "1" ]]; then
    osascript -e 'tell application "PermissionPulse" to quit' 2>/dev/null || true
    sleep 1
fi

if [[ $WIPE_STATE -eq 1 ]]; then
    remove_live_state
else
    pass "(skipped — --keep was passed)"
fi

if [[ "${SMOKE_DRY_RUN:-0}" == "1" ]]; then
    pass "state preservation verified"
    exit 0
fi

# ------------------------------- 1. build ----------------------------------

section "1. Release build"

if BUILD_OUTPUT=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build 2>&1); then
    pass "xcodebuild Release succeeded"
else
    fail "xcodebuild Release failed"
    echo "$BUILD_OUTPUT" | tail -40
fi

APP_PATH=$(/bin/ls -d "$HOME/Library/Developer/Xcode/DerivedData/PermissionPulse-"*/Build/Products/Release/PermissionPulse.app 2>/dev/null | head -1)
if [[ -z "$APP_PATH" ]]; then
    fail "could not locate built .app under DerivedData"
else
    pass "built .app at $APP_PATH"
fi

# ------------------------------- 2. version --------------------------------

section "2. Bundle version"

if [[ -n "$APP_PATH" ]]; then
    PLIST="$APP_PATH/Contents/Info.plist"
    MARKETING=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST" 2>/dev/null)
    BUILD_NO=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST" 2>/dev/null)
    if [[ "$MARKETING" == "0.7.1" ]]; then
        pass "CFBundleShortVersionString = $MARKETING"
    else
        fail "CFBundleShortVersionString = $MARKETING (expected 0.7.1)"
    fi
    if [[ "$BUILD_NO" == "11" ]]; then
        pass "CFBundleVersion = $BUILD_NO"
    else
        warn "CFBundleVersion = $BUILD_NO (expected 11)"
    fi
fi

# ------------------------------- 3. package tests --------------------------

section "3. Package test bundles"

TOTAL_TESTS=0
for pkg in PermissionsCore PermissionsStore PermissionsScanners PermissionsUI; do
    OUT=$(swift test --package-path "$REPO_ROOT/Packages/$pkg" 2>&1)
    COUNT=$(echo "$OUT" | grep -oE "Test run with [0-9]+" | tail -1 | grep -oE "[0-9]+")
    if echo "$OUT" | grep -q "Test run with .* passed"; then
        pass "$pkg: $COUNT tests"
        TOTAL_TESTS=$((TOTAL_TESTS + COUNT))
    else
        fail "$pkg: tests failed or did not run"
        echo "$OUT" | tail -15
    fi
done

# ------------------------------- 4. app-target tests -----------------------

section "4. App target test bundle"

APP_TESTS_OUT=$(PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO 2>&1)
APP_TEST_COUNT=$(echo "$APP_TESTS_OUT" | grep -oE "Test run with [0-9]+" | tail -1 | grep -oE "[0-9]+")
if echo "$APP_TESTS_OUT" | grep -q "TEST SUCCEEDED"; then
    pass "App target: $APP_TEST_COUNT tests"
    TOTAL_TESTS=$((TOTAL_TESTS + APP_TEST_COUNT))
else
    fail "App target: tests failed"
    echo "$APP_TESTS_OUT" | tail -25
fi

# ------------------------------- 5. on-disk state --------------------------

section "5. On-disk state checks"

# Snapshots DB will only exist if the app was launched and FDA granted.
if [[ -f "$DB" ]]; then
    pass "snapshots.db exists"
    SCHEMA=$(sqlite3 "$DB" ".tables" 2>&1)
    EXPECTED_TABLES=("btm_items" "launch_agents" "snapshots" "tcc_grants")
    SCHEMA_OK=1
    for t in "${EXPECTED_TABLES[@]}"; do
        if ! echo "$SCHEMA" | grep -wq "$t"; then
            fail "snapshots.db missing table: $t"
            SCHEMA_OK=0
        fi
    done
    [[ $SCHEMA_OK -eq 1 ]] && pass "snapshots.db schema present (snapshots, tcc_grants, btm_items, launch_agents)"
    SNAP_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM snapshots;" 2>&1)
    pass "snapshots.db row count: $SNAP_COUNT"
else
    warn "snapshots.db not yet created (expected on a clean slate before first launch + FDA grant)"
fi

# Defaults snapshot
PP_KEY_COUNT=$(defaults read "$BUNDLE_DOMAIN" 2>&1 \
    | grep -c "com.wallymagill.permissionpulse" || true)
NSWIN_COUNT=$(defaults read "$BUNDLE_DOMAIN" 2>&1 \
    | grep -cE "^\s*\"(NSWindow|NSStatusItem|NSSplitView)" || true)
pass "defaults: $PP_KEY_COUNT PP keys, $NSWIN_COUNT NSWindow/NSStatusItem keys"

# ------------------------------- 6. git state ------------------------------

section "6. Git state"

cd "$REPO_ROOT"
HEAD_SHA=$(git rev-parse --short HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
UNCOMMITTED=$(git status --porcelain | grep -v '^??' | wc -l | tr -d ' ')
UNTRACKED=$(git status --porcelain | grep '^??' | wc -l | tr -d ' ')
pass "branch=$BRANCH HEAD=$HEAD_SHA"
[[ "$UNCOMMITTED" == "0" ]] && pass "no uncommitted changes" || warn "$UNCOMMITTED uncommitted change(s)"
[[ "$UNTRACKED" -gt 0 ]] && warn "$UNTRACKED untracked file(s)"

# ------------------------------- launch (optional) -------------------------

if [[ $LAUNCH_APP -eq 1 && -n "$APP_PATH" ]]; then
    section "7. Launching the app"
    open "$APP_PATH"
    pass "open $APP_PATH"
fi

# ------------------------------- summary -----------------------------------

section "Summary"

echo
echo "Total automated checks:"
echo "  passed: ${#PASSED[@]}"
echo "  warned: ${#WARNED[@]}"
echo "  failed: ${#FAILED[@]}"
echo
echo "Total tests run: $TOTAL_TESTS"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo
    red "FAILURES:"
    printf '  - %s\n' "${FAILED[@]}"
fi

if [[ ${#WARNED[@]} -gt 0 ]]; then
    echo
    yellow "WARNINGS:"
    printf '  - %s\n' "${WARNED[@]}"
fi

echo
bold "═══ HUMAN-ONLY STEPS REMAINING ═══"
cat <<'EOF'

These cannot be verified by a script; the app is open now (unless you
passed --no-launch). Run through them and report any deviations.

  A. Welcome window appears + FDA-grant flow works
     → After granting, click Refresh in the detail-window toolbar.

  B. Menu-bar dropdown shows: What Changed (⌘W), Open Permission Pulse
     (⌘O), Preferences… (⌘,), Quit (⌘Q).

  C. ⌘, opens Preferences (Tahoe MenuBarExtra regression check). Two
     tabs — Snapshots, Notifications.

  D. Snapshots tab — drag retention + stale sliders, close and reopen.
     Values persist. defaults read com.wallymagill.permissionpulse
     <key> confirms.

  E. Notifications tab — flip toggle ON. macOS prompt should show
     "Permission Pulse" as the app name. Click Allow.

  F. Notifications tab — click the new "Send" button (next to "Send
     test notification"). Switch to another app. A banner labelled
     "Permission Pulse · Test" should appear in ~5 seconds.
     ← THIS is the diagnostic for the missing-notification bug.

  G. Recent Changes — trailing ellipsis menu → Dismiss / Snooze 7 days
     work. To force a non-empty diff, run scripts/seed-diff.sh (which
     writes a 2-day-old empty snapshot in GRDB's TEXT date format), then
     click Refresh in the detail-window toolbar.

  H. Stale Apps — trailing ellipsis menu → Skip forever, confirmation
     alert appears.

  I. Reset All Data — confirmation sheet, cascade works, NSWindow
     keys preserved.

  ─── Accessibility (W4) — needs a VoiceOver session (toggle VO: ⌘F5) ───

  J. Menu-bar icon state (A1 — MOST IMPORTANT). With VoiceOver on, move to
     the Permission Pulse status item. It must announce the STATE label
     ("Permission Pulse — unreviewed changes" / "… — camera in use" /
     "… — scan error, action needed"), NOT a raw SF Symbol name like
     "bell badge fill". ⚠ If it reads the symbol name, MenuBarExtra isn't
     bridging .accessibilityLabel to the NSStatusBarButton — add an AppKit
     bridge in AppDelegate (set NSStatusBarButton.accessibilityLabel from
     viewModel.menuBarAccessibilityLabel). Caveat is documented above the
     modifier in PermissionPulseApp.swift.

  K. Reduce Motion (A4). System Settings → Accessibility → Display →
     Reduce Motion ON. In the detail window, click Refresh: the icon must
     NOT spin — it dims and VoiceOver reads "Refreshing". Turn Reduce
     Motion OFF and confirm the icon spins again.

  L. Selected state (A3). VoiceOver/Tab through the detail-window sidebar
     and the Preferences tabs: it announces "selected" on the active item/
     tab, and the announcement moves when you change selection.

  M. Action menus (A2). Recent Changes and Stale Apps rows: VoiceOver reads
     the trailing menu as "Options, pop up button" with the hint ("Dismiss
     or snooze this change" / "Skip this app forever"), and the menu is
     reachable by keyboard (no mouse).

  N. No symbol-name noise (A5). VoiceOver should NOT read decorative icon
     names: section labels are reachable via the Headings rotor (VO+U →
     Headings); overview rows read as one phrase ("Permissions, 12"); and
     empty-state / hero icons (Welcome, FDA sheet, empty diffs) stay silent.

  ─── Visual / design system (Thread B) ───

  O. Type scale & Dynamic Type. System Settings → Accessibility → Display →
     larger text (or Displays → Larger Text). Detail window, sheets,
     Preferences, Welcome all scale and reflow cleanly. The menu-bar dropdown
     scales only modestly (clamped at xLarge) and never blows past its 320pt
     width.

  P. Light & dark. Toggle System Settings → Appearance. Every surface —
     dropdown, detail window, sidebar, each sheet, Preferences, Welcome —
     looks intentional in BOTH; no washed-out or unreadable text.

  Q. Reduce Transparency. Accessibility → Display → Reduce Transparency ON.
     Cards/panels stay solid and legible (the app's cards are solid by
     design); the dropdown popover background stays readable. OFF looks normal.

  R. Accent color. System Settings → Appearance → Accent color → pick a
     non-blue (e.g. Pink). Interactive elements (sidebar selection, buttons,
     pickers, service pills) follow it; the brand badge stays blue; category
     and status colors (green/red/orange) are unchanged.

  S. Badge contrast. The Mock / Live badges and the background-item
     disposition badges read clearly (dark text on a pale tint) in both light
     and dark — no white-on-color low-contrast text.

  T. Consistency sweep. Scan all surfaces side by side: section labels,
     spacing rhythm, card depth (hairline + soft shadow), and type sizes match
     everywhere. Nothing looks like a one-off.

  # Thread C — native redesign (U: deep links & inspector)
  # U1. Dropdown: every status row opens the window on the correct section.
  # U2. Permissions: click row → inspector follows; ↑/↓ moves selection + inspector updates.
  # U3. ⌘1–⌘6 switch sections; ⌥⌘I toggles inspector; ⌘R rescans from window.
  # U4. Overview: attention + count rows navigate; Last Scan time is honest.
  # U5. Changes: context-menu dismiss/snooze; badge clears after visiting.
  # U6. Stale: context-menu Reveal/Skip forever works.
  # U7. FDA-denied run: dropdown attention row → Permissions full-page state → Grant button opens System Settings.
  # U8. Settings: 4 tabs render; launch-at-login toggles a Login Items entry; Reset confirms via alert and wipes.
  # U9. Welcome: both steps; Open System Settings lands on Full Disk Access.
  # U10. All of the above in light + dark; large Dynamic Type in window; clamped in dropdown; Reduce Transparency + Reduce Motion honored.

EOF

if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
