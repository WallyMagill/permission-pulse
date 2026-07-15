#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: %s RELEASE_APP EXPECTED_VERSION EXPECTED_BUILD\n' "$0" >&2
    exit 64
fi

release_app=$1
expected_version=$2
expected_build=$3
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
verifier="$repo_root/scripts/verify-release.sh"
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/permission-pulse-verifier-test.XXXXXX")
case "$release_app" in
    /*) ;;
    *) release_app="$PWD/$release_app" ;;
esac

cleanup() {
    rm -rf "$temp_root"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

copy_app() {
    local destination=$1
    /usr/bin/ditto "$release_app" "$destination"
}

sign_app() {
    local app=$1
    /usr/bin/codesign --force --deep --sign - --options runtime --timestamp=none "$app"
}

expect_success() {
    local name=$1
    local input=$2
    if ! "$verifier" "$input" "$expected_version" "$expected_build" \
        >"$temp_root/result.log" 2>&1; then
        /bin/cat "$temp_root/result.log" >&2
        fail "$name was rejected"
    fi
    printf 'PASS: %s accepted\n' "$name"
}

expect_rejection() {
    local name=$1
    local input=$2
    local expected_message=$3
    if "$verifier" "$input" "$expected_version" "$expected_build" \
        >"$temp_root/result.log" 2>&1; then
        fail "$name was accepted"
    fi
    if ! /usr/bin/grep -Fq "$expected_message" "$temp_root/result.log"; then
        /bin/cat "$temp_root/result.log" >&2
        fail "$name did not report: $expected_message"
    fi
    printf 'PASS: %s rejected\n' "$name"
}

[[ -d "$release_app" ]] || fail "release app not found: $release_app"

valid_app="$temp_root/valid app/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$valid_app")"
copy_app "$valid_app"
sign_app "$valid_app"
expect_success 'valid raw app' "$valid_app"

valid_zip="$temp_root/valid release.zip"
(
    cd "$(dirname "$valid_app")"
    /usr/bin/ditto -c -k --keepParent "$(basename "$valid_app")" "$valid_zip"
)
expect_success 'valid zip' "$valid_zip"

debug_app="$temp_root/debug-entitled/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$debug_app")"
copy_app "$debug_app"
debug_entitlements="$temp_root/debug-entitlements.plist"
/bin/cat >"$debug_entitlements" <<'PLIST'
<?xml version="1.0"?>
<plist version="1.0"><dict>
  <key>com.apple.security.get-task-allow</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --deep --sign - --options runtime --timestamp=none \
    --entitlements "$debug_entitlements" "$debug_app"
expect_rejection 'debug entitlement' "$debug_app" 'get-task-allow entitlement is forbidden'

unexpected_entitlement_app="$temp_root/unexpected-entitlement/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$unexpected_entitlement_app")"
copy_app "$unexpected_entitlement_app"
unexpected_entitlements="$temp_root/unexpected-entitlements.plist"
/bin/cat >"$unexpected_entitlements" <<'PLIST'
<?xml version="1.0"?>
<plist version="1.0"><dict>
  <key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --deep --sign - --options runtime --timestamp=none \
    --entitlements "$unexpected_entitlements" "$unexpected_entitlement_app"
expect_rejection 'unexpected entitlement' "$unexpected_entitlement_app" \
    'unexpected code-signing entitlement is present'

wrong_version_app="$temp_root/wrong-version/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$wrong_version_app")"
copy_app "$wrong_version_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 9.9.9' \
    "$wrong_version_app/Contents/Info.plist"
sign_app "$wrong_version_app"
expect_rejection 'wrong version' "$wrong_version_app" 'unexpected bundle version'

wrong_build_app="$temp_root/wrong-build/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$wrong_build_app")"
copy_app "$wrong_build_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999' \
    "$wrong_build_app/Contents/Info.plist"
sign_app "$wrong_build_app"
expect_rejection 'wrong build' "$wrong_build_app" 'unexpected bundle build'

wrong_identifier_app="$temp_root/wrong-identifier/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$wrong_identifier_app")"
copy_app "$wrong_identifier_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.permissionpulse' \
    "$wrong_identifier_app/Contents/Info.plist"
sign_app "$wrong_identifier_app"
expect_rejection 'wrong identifier' "$wrong_identifier_app" 'unexpected bundle identifier'

thin_app="$temp_root/thin-architecture/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$thin_app")"
copy_app "$thin_app"
thin_executable="$thin_app/Contents/MacOS/PermissionPulse"
/usr/bin/lipo "$thin_executable" -thin arm64 -output "$temp_root/thin-executable"
/bin/mv "$temp_root/thin-executable" "$thin_executable"
sign_app "$thin_app"
expect_rejection 'single architecture' "$thin_app" 'missing x86_64 architecture'

invalid_signature_app="$temp_root/invalid-signature/PermissionPulse.app"
/bin/mkdir -p "$(dirname "$invalid_signature_app")"
copy_app "$invalid_signature_app"
sign_app "$invalid_signature_app"
printf '\0' >>"$invalid_signature_app/Contents/MacOS/PermissionPulse"
expect_rejection 'invalid strict signature' "$invalid_signature_app" \
    'strict deep code-signature verification failed'

unrelated_root="$temp_root/unrelated-root"
/bin/mkdir -p "$unrelated_root"
copy_app "$unrelated_root/PermissionPulse.app"
sign_app "$unrelated_root/PermissionPulse.app"
printf 'unrelated\n' >"$unrelated_root/README.txt"
unrelated_zip="$temp_root/unrelated-entry.zip"
(
    cd "$unrelated_root"
    /usr/bin/zip -qry "$unrelated_zip" PermissionPulse.app README.txt
)
expect_rejection 'unrelated archive entry' "$unrelated_zip" \
    'archive contains an entry outside its single top-level app'

symlink_root="$temp_root/escaping-symlink"
/bin/mkdir -p "$symlink_root"
copy_app "$symlink_root/PermissionPulse.app"
sign_app "$symlink_root/PermissionPulse.app"
/bin/ln -s '../../../../outside-release-root' \
    "$symlink_root/PermissionPulse.app/Contents/Resources/escaping-link"
symlink_zip="$temp_root/escaping-symlink.zip"
(
    cd "$symlink_root"
    /usr/bin/zip -qry -y "$symlink_zip" PermissionPulse.app
)
expect_rejection 'escaping symlink' "$symlink_zip" 'symbolic link escapes the app root'

printf 'PASS: all release verifier fixtures passed\n'
