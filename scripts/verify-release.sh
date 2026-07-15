#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: %s APP_OR_ZIP EXPECTED_VERSION EXPECTED_BUILD\n' "$0" >&2
    exit 64
fi

input=$1
expected_version=$2
expected_build=$3
temp_root=''
case "$input" in
    /*) ;;
    *) input="$PWD/$input" ;;
esac

cleanup() {
    if [[ -n "$temp_root" && -d "$temp_root" ]]; then
        rm -rf "$temp_root"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

validate_archive_entries() {
    local archive=$1
    local listing=$2
    local archive_app_name=''
    local entry
    local entry_count=0
    local top_level

    if ! /usr/bin/zipinfo -1 "$archive" >"$listing"; then
        fail 'input is not a readable zip archive'
    fi

    while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ -n "$entry" ]] || fail 'archive contains an empty entry name'
        entry_count=$((entry_count + 1))

        case "$entry" in
            /*|*\\*)
                fail 'archive contains an unsafe entry path'
                ;;
        esac
        case "$entry" in
            ..|../*|*/..|*/../*|.|./*|*/.|*/./*|*//*)
                fail 'archive contains an unsafe entry path'
                ;;
        esac

        top_level=${entry%%/*}
        case "$top_level" in
            *.app) ;;
            *) fail 'archive contains an entry outside its single top-level app' ;;
        esac

        if [[ -z "$archive_app_name" ]]; then
            archive_app_name=$top_level
        elif [[ "$top_level" != "$archive_app_name" ]]; then
            fail 'archive contains an entry outside its single top-level app'
        fi
    done <"$listing"

    [[ $entry_count -gt 0 ]] || fail 'archive is empty'
}

validate_symlinks() {
    local app_root=$1
    local component
    local depth
    local link
    local parent
    local relative_link
    local remaining
    local target

    while IFS= read -r -d '' link; do
        relative_link=${link#"$app_root"/}
        target=$(/usr/bin/readlink "$link") \
            || fail 'could not read a symbolic link in the app'

        case "$target" in
            /*) fail 'symbolic link escapes the app root' ;;
        esac

        case "$relative_link" in
            */*) parent=${relative_link%/*} ;;
            *) parent='' ;;
        esac
        if [[ -n "$parent" ]]; then
            remaining="$parent/$target"
        else
            remaining=$target
        fi

        depth=0
        while :; do
            case "$remaining" in
                */*)
                    component=${remaining%%/*}
                    remaining=${remaining#*/}
                    ;;
                *)
                    component=$remaining
                    remaining=''
                    ;;
            esac

            case "$component" in
                ''|.) ;;
                ..)
                    [[ $depth -gt 0 ]] || fail 'symbolic link escapes the app root'
                    depth=$((depth - 1))
                    ;;
                *) depth=$((depth + 1)) ;;
            esac

            [[ -n "$remaining" ]] || break
        done
    done < <(/usr/bin/find "$app_root" -type l -print0)
}

[[ -e "$input" ]] || fail "input does not exist: $input"

if [[ -d "$input" ]]; then
    case "$input" in
        *.app) app=$input ;;
        *) fail 'directory input must be an app bundle' ;;
    esac
else
    temp_root=$(mktemp -d "${TMPDIR:-/tmp}/permission-pulse-release.XXXXXX")
    listing="$temp_root/archive-entries.txt"
    validate_archive_entries "$input" "$listing"
    if ! /usr/bin/unzip -tqq "$input"; then
        fail 'zip archive integrity check failed'
    fi

    extraction_root="$temp_root/extracted"
    /bin/mkdir "$extraction_root"
    if ! /usr/bin/ditto -x -k "$input" "$extraction_root"; then
        fail 'could not extract zip archive'
    fi

    top_level_count=0
    app=''
    while IFS= read -r -d '' top_level_entry; do
        top_level_count=$((top_level_count + 1))
        app=$top_level_entry
    done < <(/usr/bin/find "$extraction_root" -mindepth 1 -maxdepth 1 -print0)

    [[ $top_level_count -eq 1 ]] \
        || fail 'archive must extract to exactly one top-level app'
    [[ -d "$app" && ! -L "$app" ]] \
        || fail 'archive top-level entry must be an app directory'
    case "$app" in
        *.app) ;;
        *) fail 'archive top-level entry must be an app directory' ;;
    esac
fi

validate_symlinks "$app"

plist="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/PermissionPulse"
[[ -f "$plist" ]] || fail 'bundle Info.plist is missing'
[[ -f "$executable" ]] || fail 'PermissionPulse executable is missing'

identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist") \
    || fail 'could not read bundle identifier'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") \
    || fail 'could not read bundle version'
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist") \
    || fail 'could not read bundle build'

[[ "$identifier" == 'com.wallymagill.permissionpulse' ]] \
    || fail "unexpected bundle identifier: $identifier"
[[ "$version" == "$expected_version" ]] \
    || fail "unexpected bundle version: $version"
[[ "$build" == "$expected_build" ]] \
    || fail "unexpected bundle build: $build"

architectures=$(/usr/bin/lipo -archs "$executable") \
    || fail 'could not inspect executable architectures'
printf '%s\n' "$architectures" | /usr/bin/grep -qw arm64 \
    || fail 'missing arm64 architecture'
printf '%s\n' "$architectures" | /usr/bin/grep -qw x86_64 \
    || fail 'missing x86_64 architecture'
architecture_count=$(printf '%s\n' "$architectures" | /usr/bin/awk '{ print NF }')
[[ "$architecture_count" -eq 2 ]] \
    || fail "unexpected executable architectures: $architectures"

if ! signature=$(/usr/bin/codesign -dvvv "$app" 2>&1); then
    fail 'app does not have a readable code signature'
fi
printf '%s\n' "$signature" | /usr/bin/grep -Fq 'Signature=adhoc' \
    || fail 'app signature is not ad hoc'
if printf '%s\n' "$signature" | /usr/bin/grep -Eq '^Authority=|^TeamIdentifier=[A-Z0-9]'; then
    fail 'app signature contains an authority or team identifier'
fi

if [[ "${PERMISSION_PULSE_TEST_FORCE_ENTITLEMENTS_FAILURE:-0}" == '1' ]]; then
    fail 'could not inspect code-signing entitlements'
fi
if ! entitlements=$(/usr/bin/codesign -d --entitlements - "$app" 2>/dev/null); then
    fail 'could not inspect code-signing entitlements'
fi
if printf '%s\n' "$entitlements" \
    | /usr/bin/grep -Fq 'com.apple.security.get-task-allow'; then
    fail 'get-task-allow entitlement is forbidden'
fi
if [[ -n "$entitlements" ]]; then
    fail 'unexpected code-signing entitlement is present'
fi

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"; then
    fail 'strict deep code-signature verification failed'
fi

printf 'PASS: verified PermissionPulse %s (%s)\n' "$version" "$build"
