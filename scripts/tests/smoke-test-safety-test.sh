#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
output=$(SMOKE_DRY_RUN=1 "$repo_root/scripts/smoke-test.sh" --keep --no-launch)
if printf '%s\n' "$output" | grep -Eq 'rm .*snapshots\.db|defaults delete'; then
    printf 'FAIL: --keep attempted destructive cleanup\n' >&2
    exit 1
fi
printf '%s\n' "$output" | grep -F 'state preservation verified'
printf 'PASS: --keep contains no state deletion\n'
