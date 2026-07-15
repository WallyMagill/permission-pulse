#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
output=$(SMOKE_DRY_RUN=1 "$repo_root/scripts/smoke-test.sh" --keep --no-launch)
if printf '%s\n' "$output" | grep -Eq 'rm .*snapshots\.db|defaults delete'; then
    printf 'FAIL: --keep attempted destructive cleanup\n' >&2
    exit 1
fi
printf '%s\n' "$output" | grep -F 'state preservation verified'

for required_check in \
    'Complete TCC coverage' \
    'Controlled degraded scan' \
    'Bundle-ID stale candidate' \
    'Independent path-only identities' \
    'TCC authorization transition' \
    'degraded data' \
    'last-known data' \
    'no successful history' \
    'Intel execution remains unverified'; do
    if ! grep -Fq "$required_check" "$repo_root/scripts/smoke-test.sh"; then
        printf 'FAIL: human checklist missing: %s\n' "$required_check" >&2
        exit 1
    fi
done

"$repo_root/scripts/tests/snapshot-schema-verifier-test.sh"

printf 'PASS: --keep contains no state deletion\n'
printf 'PASS: Workstream C human checklist is present\n'
