#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: %s VERSION OUTPUT_DIR\n' "$0" >&2
    exit 64
fi

expected_version=$1
output_argument=$2
script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
testing_dirty_tree=${PERMISSION_PULSE_PACKAGE_TESTING:-0}
test_late_collision=${PERMISSION_PULSE_PACKAGE_TEST_LATE_COLLISION:-0}
staging=''
lock_dir=''
lock_owned=0
final_zip=''
final_checksum=''
final_manifest=''
complete=0

cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM

    if [[ $complete -ne 1 && $status -eq 0 ]]; then
        status=1
    fi

    if [[ $lock_owned -eq 1 && -d "$lock_dir" ]]; then
        if [[ -f "$lock_dir/owner" ]] \
            && /usr/bin/grep -Fxq "$staging" "$lock_dir/owner"; then
            /bin/rm -f "$lock_dir/owner"
        fi
        /bin/rmdir "$lock_dir" 2>/dev/null || true
    fi

    if [[ -n "$staging" && -d "$staging" ]]; then
        /bin/rm -rf "$staging"
    fi

    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

config_value() {
    local key=$1
    /usr/bin/awk -F= -v key="$key" '
        $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            value = $2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
        }
    ' "$version_config"
}

path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

sign_nested_bundles() {
    local app=$1
    local bundle

    while IFS= read -r -d '' bundle; do
        printf 'Signing nested bundle: %s\n' "${bundle#"$app"/}"
        /usr/bin/codesign --force --sign - --options runtime --timestamp=none \
            "$bundle"
    done < <(
        /usr/bin/find "$app" -depth -type d \
            \( -name '*.app' -o -name '*.appex' -o -name '*.xpc' \
                -o -name '*.framework' -o -name '*.bundle' \
                -o -name '*.plugin' -o -name '*.qlgenerator' \
                -o -name '*.mdimporter' \) \
            ! -path "$app" -print0
    )
}

printf '%s\n' "$expected_version" \
    | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail 'VERSION must be a semantic version such as 0.7.2'
[[ -n "$output_argument" ]] || fail 'OUTPUT_DIR must not be empty'
case "$testing_dirty_tree" in
    0|1) ;;
    *) fail 'PERMISSION_PULSE_PACKAGE_TESTING must be 0 or 1' ;;
esac
case "$test_late_collision" in
    0|1) ;;
    *) fail 'PERMISSION_PULSE_PACKAGE_TEST_LATE_COLLISION must be 0 or 1' ;;
esac
if [[ $test_late_collision -eq 1 && $testing_dirty_tree -ne 1 ]]; then
    fail 'late-collision testing requires PERMISSION_PULSE_PACKAGE_TESTING=1'
fi

cd "$repo_root"
if [[ $testing_dirty_tree -ne 1 ]] \
    && [[ -n "$(/usr/bin/git status --porcelain --untracked-files=no)" ]]; then
    fail 'tracked worktree must be clean before packaging'
fi
git_sha=$(/usr/bin/git rev-parse --verify 'HEAD^{commit}')
printf '%s\n' "$git_sha" | /usr/bin/grep -Eq '^[0-9a-f]{40}$' \
    || fail 'could not record a full Git commit SHA'

case "$output_argument" in
    /*) ;;
    *) output_argument="$PWD/$output_argument" ;;
esac
/bin/mkdir -p "$output_argument"
output_dir=$(cd "$output_argument" && pwd -P)

if [[ $testing_dirty_tree -eq 1 ]]; then
    artifact_stem="PermissionPulse-v${expected_version}-TESTING-DIRTY"
else
    artifact_stem="PermissionPulse-v${expected_version}"
fi
archive_basename="${artifact_stem}.app.zip"
checksum_basename="${archive_basename}.sha256"
manifest_basename="${artifact_stem}.manifest.txt"
final_zip="$output_dir/$archive_basename"
final_checksum="$output_dir/$checksum_basename"
final_manifest="$output_dir/$manifest_basename"

path_exists "$final_zip" && fail "output already exists: $final_zip"
path_exists "$final_checksum" && fail "output already exists: $final_checksum"
path_exists "$final_manifest" && fail "output already exists: $final_manifest"

staging=$(/usr/bin/mktemp -d "$output_dir/.permission-pulse-package.XXXXXX")
lock_dir="$output_dir/.${artifact_stem}.package.lock"
if ! /bin/mkdir "$lock_dir"; then
    fail "another package installation holds the output lock: $lock_dir"
fi
lock_owned=1
printf '%s\n' "$staging" >"$lock_dir/owner"

path_exists "$final_zip" && fail "output appeared during package setup: $final_zip"
path_exists "$final_checksum" && fail "output appeared during package setup: $final_checksum"
path_exists "$final_manifest" && fail "output appeared during package setup: $final_manifest"

if [[ $testing_dirty_tree -eq 1 ]]; then
    build_root=$repo_root
else
    build_root="$staging/source"
    source_archive="$staging/source.tar"
    /bin/mkdir "$build_root"
    /usr/bin/git archive --format=tar --output="$source_archive" "$git_sha"
    /usr/bin/tar -xf "$source_archive" -C "$build_root"
    /bin/rm -f "$source_archive"
fi

project="$build_root/PermissionPulse/PermissionPulse.xcodeproj"
version_config="$build_root/Config/Version.xcconfig"
verifier="$build_root/scripts/verify-release.sh"
[[ -f "$version_config" ]] || fail 'Config/Version.xcconfig is missing'
[[ -x "$verifier" ]] || fail 'scripts/verify-release.sh is missing or not executable'

configured_version=$(config_value MARKETING_VERSION)
expected_build=$(config_value CURRENT_PROJECT_VERSION)
[[ -n "$configured_version" ]] \
    || fail 'MARKETING_VERSION is missing from Config/Version.xcconfig'
[[ -n "$expected_build" ]] \
    || fail 'CURRENT_PROJECT_VERSION is missing from Config/Version.xcconfig'
[[ "$configured_version" == "$expected_version" ]] \
    || fail "requested version $expected_version does not match configured version $configured_version"
printf '%s\n' "$expected_build" | /usr/bin/grep -Eq '^[0-9]+$' \
    || fail 'CURRENT_PROJECT_VERSION must be numeric'

derived="$staging/DerivedData"
cloned_source_packages="$staging/SourcePackages"
package_cache="$staging/PackageCache"
temporary_zip="$staging/payload.zip"
temporary_checksum="$staging/checksum.txt"
temporary_manifest="$staging/manifest.txt"
/bin/mkdir "$cloned_source_packages" "$package_cache"

/usr/bin/xcodebuild -project "$project" -scheme PermissionPulse \
    -configuration Release -derivedDataPath "$derived" \
    -disableAutomaticPackageResolution \
    -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    -disablePackageRepositoryCache \
    -clonedSourcePackagesDirPath "$cloned_source_packages" \
    -packageCachePath "$package_cache" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO 'DEVELOPMENT_TEAM=' build

app="$derived/Build/Products/Release/PermissionPulse.app"
[[ -d "$app" ]] || fail "built app not found: $app"

sign_nested_bundles "$app"
printf 'Signing root app\n'
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$app"

"$verifier" "$app" "$expected_version" "$expected_build"
/usr/bin/ditto -c -k --keepParent "$app" "$temporary_zip"
"$verifier" "$temporary_zip" "$expected_version" "$expected_build"

checksum=$(/usr/bin/shasum -a 256 "$temporary_zip" | /usr/bin/awk '{ print $1 }')
[[ ${#checksum} -eq 64 ]] || fail 'could not calculate a SHA-256 checksum'
case "$checksum" in
    *[!0-9a-f]*) fail 'SHA-256 checksum was not lowercase hexadecimal' ;;
esac
printf '%s  %s\n' "$checksum" "$(basename "$temporary_zip")" \
    >"$temporary_checksum"
(
    cd "$staging"
    /usr/bin/shasum -a 256 -c "$(basename "$temporary_checksum")"
)

{
    printf 'version=%s\n' "$expected_version"
    printf 'build=%s\n' "$expected_build"
    printf 'gitSHA=%s\n' "$git_sha"
    printf 'archive=%s\n' "$archive_basename"
    printf 'sha256=%s\n' "$checksum"
    if [[ $testing_dirty_tree -eq 1 ]]; then
        printf 'testingDirtyTree=true\n'
    fi
} >"$temporary_manifest"

printf '%s  %s\n' "$checksum" "$archive_basename" \
    >"$staging/final-checksum.txt"

if [[ $test_late_collision -eq 1 ]]; then
    printf 'late-collision-sentinel\n' >"$final_zip"
fi

if ! /bin/ln "$staging/final-checksum.txt" "$final_checksum"; then
    fail "output appeared before final installation: $final_checksum"
fi

if ! /bin/ln "$temporary_manifest" "$final_manifest"; then
    fail "output appeared before final installation: $final_manifest"
fi

if ! /bin/ln "$temporary_zip" "$final_zip"; then
    fail "output appeared before final installation: $final_zip"
fi
complete=1

printf 'Release archive: %s\n' "$final_zip"
printf 'Checksum: %s\n' "$final_checksum"
printf 'Manifest: %s\n' "$final_manifest"
