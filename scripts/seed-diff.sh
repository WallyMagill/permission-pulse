#!/usr/bin/env bash
#
# scripts/seed-diff.sh — inject an empty snapshot dated 2 days ago.
#
# Forces the next scan's diff to be non-empty (every current TCC grant
# shows as "Granted X to Y" since the seeded prior snapshot has nothing).
# Used by the v0.7.0 smoke test §G to exercise the Recent Changes
# dismiss/snooze flow without waiting a day for a real diff.
#
# Run AFTER the app has launched at least once (snapshots.db must exist
# with the schema in place). Then click Refresh in the detail window's
# toolbar to compute the diff against the seeded snapshot.

set -u

DB="$HOME/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db"

if [[ ! -f "$DB" ]]; then
    echo "error: $DB not found." >&2
    echo "Launch Permission Pulse, grant FDA, and click Refresh once before running this." >&2
    exit 1
fi

# A snapshot exactly 2 days old. Yesterday-window cutoff is 24h, so this
# row will be the "before" reference for the next scan's diff.
#
# Write the date in GRDB's default Date encoding: TEXT 'yyyy-MM-dd
# HH:mm:ss.SSS'. The diff query parameterizes the cutoff as a Swift Date
# which GRDB also encodes as TEXT — same format on both sides is the only
# reliable comparison. Don't use strftime('%s', ...) which produces a
# REAL UNIX epoch and won't compare correctly to GRDB's TEXT dates.
sqlite3 "$DB" \
    "INSERT INTO snapshots (created_at) VALUES (strftime('%Y-%m-%d %H:%M:%f','now','-2 days'));"

echo "✓ Seeded a 2-day-old empty snapshot."
echo "  Now click Refresh in the detail window's toolbar."
echo "  Recent Changes should show your current TCC grants as 'Granted X to Y' rows."
