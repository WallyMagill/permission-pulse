#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
verifier="$repo_root/scripts/verify-snapshot-schema.sh"
smoke_test="$repo_root/scripts/smoke-test.sh"
tmp_dir=$(mktemp -d "/tmp/permission pulse schema.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

create_v4_database() {
    local database=$1
    sqlite3 "$database" <<'SQL'
CREATE TABLE schema_version (version INTEGER NOT NULL);
INSERT INTO schema_version (version) VALUES (4);
CREATE TABLE snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at DOUBLE NOT NULL
);
CREATE TABLE launch_agents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshot_id INTEGER NOT NULL,
    label TEXT NOT NULL,
    source_directory TEXT NOT NULL,
    program_path TEXT,
    program_arguments_json TEXT NOT NULL DEFAULT '[]',
    run_at_load INTEGER NOT NULL,
    keep_alive INTEGER NOT NULL
);
CREATE TABLE tcc_grants (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshot_id INTEGER NOT NULL,
    service TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    bundle_path TEXT,
    last_modified DOUBLE NOT NULL,
    automation_target TEXT,
    auth_value INTEGER NOT NULL DEFAULT 2
);
CREATE TABLE btm_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshot_id INTEGER NOT NULL,
    identifier TEXT NOT NULL,
    name TEXT NOT NULL,
    developer_name TEXT,
    bundle_identifier TEXT,
    team_identifier TEXT,
    type_kind TEXT NOT NULL,
    type_raw INTEGER,
    disposition_kind TEXT NOT NULL,
    disposition_raw INTEGER,
    scope_kind TEXT NOT NULL,
    scope_per_user_uuid TEXT,
    modification_date DOUBLE NOT NULL,
    parent_identifier TEXT
);
CREATE TABLE grdb_migrations (
    identifier TEXT PRIMARY KEY NOT NULL
);
INSERT INTO grdb_migrations (identifier) VALUES
    ('v1'),
    ('v2'),
    ('v3'),
    ('v4');
INSERT INTO snapshots (created_at) VALUES (0);
INSERT INTO launch_agents (
    snapshot_id, label, source_directory, program_arguments_json,
    run_at_load, keep_alive
) VALUES (1, 'com.example.fixture', 'user', '[]', 1, 0);
SQL
}

migrate_to_v5() {
    local database=$1
    sqlite3 "$database" <<'SQL'
ALTER TABLE launch_agents
    ADD COLUMN is_disabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE snapshots
    ADD COLUMN launch_agent_disabled_captured INTEGER NOT NULL DEFAULT 0;
UPDATE schema_version SET version = 5;
INSERT INTO grdb_migrations (identifier) VALUES ('v5');
UPDATE snapshots SET launch_agent_disabled_captured = 1;
UPDATE launch_agents SET is_disabled = 1;
SQL
}

expect_success() {
    local description=$1
    shift
    if ! "$@" >"$tmp_dir/output" 2>&1; then
        printf 'FAIL: expected success: %s\n' "$description" >&2
        sed -n '1,120p' "$tmp_dir/output" >&2
        exit 1
    fi
}

expect_failure() {
    local description=$1
    shift
    if "$@" >"$tmp_dir/output" 2>&1; then
        printf 'FAIL: expected failure: %s\n' "$description" >&2
        sed -n '1,120p' "$tmp_dir/output" >&2
        exit 1
    fi
}

expect_output_success() {
    local description=$1
    local expected=$2
    shift 2
    if ! "$@" >"$tmp_dir/output" 2>&1; then
        printf 'FAIL: expected success: %s\n' "$description" >&2
        sed -n '1,120p' "$tmp_dir/output" >&2
        exit 1
    fi
    grep -Fq "$expected" "$tmp_dir/output" || {
        printf 'FAIL: missing expected output for %s: %s\n' \
            "$description" "$expected" >&2
        sed -n '1,120p' "$tmp_dir/output" >&2
        exit 1
    }
}

v4_db="$tmp_dir/snapshots 'preserved v4'.db"
v5_db="$tmp_dir/snapshots v5.db"
invalid_capture_db="$tmp_dir/invalid capture.db"
invalid_disabled_db="$tmp_dir/invalid disabled.db"
invalid_shape_db="$tmp_dir/invalid v4 shape.db"
missing_capture_column_db="$tmp_dir/missing capture column.db"
missing_disabled_column_db="$tmp_dir/missing disabled column.db"
future_db="$tmp_dir/future.db"
missing_ledger_db="$tmp_dir/missing migration ledger.db"
missing_v4_ledger_db="$tmp_dir/missing v4 ledger.db"
missing_v5_ledger_db="$tmp_dir/missing v5 ledger.db"
unexpected_ledger_db="$tmp_dir/unexpected ledger identifier.db"
duplicate_ledger_db="$tmp_dir/duplicate ledger identifier.db"
missing_db="$tmp_dir/missing snapshots.db"

create_v4_database "$v4_db"
cp "$v4_db" "$v5_db"
migrate_to_v5 "$v5_db"
cp "$v5_db" "$invalid_capture_db"
cp "$v5_db" "$invalid_disabled_db"
cp "$v4_db" "$invalid_shape_db"
cp "$v4_db" "$missing_capture_column_db"
cp "$v4_db" "$missing_disabled_column_db"
cp "$v5_db" "$future_db"
cp "$v5_db" "$missing_ledger_db"
cp "$v4_db" "$missing_v4_ledger_db"
cp "$v5_db" "$missing_v5_ledger_db"
cp "$v5_db" "$unexpected_ledger_db"
cp "$v5_db" "$duplicate_ledger_db"
sqlite3 "$invalid_capture_db" \
    'UPDATE snapshots SET launch_agent_disabled_captured = 2;'
sqlite3 "$invalid_disabled_db" \
    'UPDATE launch_agents SET is_disabled = -1;'
sqlite3 "$invalid_shape_db" 'ALTER TABLE tcc_grants DROP COLUMN auth_value;'
sqlite3 "$missing_capture_column_db" <<'SQL'
ALTER TABLE launch_agents
    ADD COLUMN is_disabled INTEGER NOT NULL DEFAULT 0;
UPDATE schema_version SET version = 5;
SQL
sqlite3 "$missing_disabled_column_db" <<'SQL'
ALTER TABLE snapshots
    ADD COLUMN launch_agent_disabled_captured INTEGER NOT NULL DEFAULT 0;
UPDATE schema_version SET version = 5;
SQL
sqlite3 "$future_db" 'UPDATE schema_version SET version = 6;'
sqlite3 "$missing_ledger_db" 'DROP TABLE grdb_migrations;'
sqlite3 "$missing_v4_ledger_db" \
    "DELETE FROM grdb_migrations WHERE identifier = 'v4';"
sqlite3 "$missing_v5_ledger_db" \
    "DELETE FROM grdb_migrations WHERE identifier = 'v5';"
sqlite3 "$unexpected_ledger_db" \
    "INSERT INTO grdb_migrations (identifier) VALUES ('v99');"
sqlite3 "$duplicate_ledger_db" <<'SQL'
ALTER TABLE grdb_migrations RENAME TO grdb_migrations_original;
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL);
INSERT INTO grdb_migrations (identifier)
    SELECT identifier FROM grdb_migrations_original;
INSERT INTO grdb_migrations (identifier) VALUES ('v5');
DROP TABLE grdb_migrations_original;
SQL

v4_before=$(shasum -a 256 "$v4_db")
v5_before=$(shasum -a 256 "$v5_db")

expect_success 'preserved v4 is pending when no launch can migrate it' \
    "$verifier" --database "$v4_db" --allow-pending-v4
expect_failure 'v4 is not v5-complete on a schema-expected path' \
    "$verifier" --database "$v4_db"
expect_success 'valid v5 is complete' \
    "$verifier" --database "$v5_db"
expect_failure 'v5 rejects an invalid snapshot capture marker' \
    "$verifier" --database "$invalid_capture_db"
expect_failure 'v5 rejects an invalid LaunchAgent disabled marker' \
    "$verifier" --database "$invalid_disabled_db"
expect_failure 'v4 rejects a missing required pre-v5 column' \
    "$verifier" --database "$invalid_shape_db" --allow-pending-v4
expect_failure 'v5 requires the snapshot capture column' \
    "$verifier" --database "$missing_capture_column_db"
expect_failure 'v5 requires the LaunchAgent disabled column' \
    "$verifier" --database "$missing_disabled_column_db"
expect_failure 'future schema versions fail closed' \
    "$verifier" --database "$future_db"
expect_failure 'v5 requires the GRDB migration ledger table' \
    "$verifier" --database "$missing_ledger_db"
expect_failure 'schema v4 requires the exact v1-v4 migration ledger' \
    "$verifier" --database "$missing_v4_ledger_db" --allow-pending-v4
expect_failure 'schema v5 rejects the reviewer partial-ledger case missing v5' \
    "$verifier" --database "$missing_v5_ledger_db"
expect_failure 'schema v5 rejects an unexpected migration identifier' \
    "$verifier" --database "$unexpected_ledger_db"
expect_failure 'schema v5 rejects duplicate migration identifiers in a malformed ledger' \
    "$verifier" --database "$duplicate_ledger_db"
expect_failure 'a missing database is reported without creating it' \
    "$verifier" --database "$missing_db"

expect_output_success \
    'smoke accepts preserved v4 as pending under --keep --no-launch' \
    'pending app migration; not yet verified as schema v5' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v4_db" \
    "$smoke_test" --keep --no-launch
expect_failure \
    'smoke rejects v4 when launch makes schema v5 expected' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v4_db" \
    "$smoke_test" --keep
expect_output_success \
    'smoke accepts valid v5 as complete' \
    'snapshots.db schema version = 5 (complete)' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v5_db" \
    "$smoke_test" --keep --no-launch
expect_output_success \
    'smoke preserves the documented missing-database warning' \
    'snapshots.db not yet created' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$missing_db" \
    "$smoke_test" --keep --no-launch

[[ ! -e "$missing_db" ]] || {
    printf 'FAIL: read-only verification created the missing database\n' >&2
    exit 1
}
[[ "$v4_before" == "$(shasum -a 256 "$v4_db")" ]] || {
    printf 'FAIL: v4 database changed during verification\n' >&2
    exit 1
}
[[ "$v5_before" == "$(shasum -a 256 "$v5_db")" ]] || {
    printf 'FAIL: v5 database changed during verification\n' >&2
    exit 1
}

printf 'PASS: snapshot schema verifier accepts pending v4 only without migration opportunity\n'
printf 'PASS: snapshot schema verifier validates v5 read-only and fails closed\n'
