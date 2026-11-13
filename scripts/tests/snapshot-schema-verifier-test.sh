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

migrate_to_v6() {
    local database=$1
    sqlite3 "$database" <<'SQL'
ALTER TABLE snapshots ADD COLUMN tcc_coverage TEXT NOT NULL DEFAULT 'complete';
ALTER TABLE snapshots ADD COLUMN btm_coverage TEXT NOT NULL DEFAULT 'complete';
ALTER TABLE snapshots
    ADD COLUMN launch_agent_coverage TEXT NOT NULL DEFAULT 'complete';
UPDATE schema_version SET version = 6;
INSERT INTO grdb_migrations (identifier) VALUES ('v6');
UPDATE snapshots SET launch_agent_coverage = 'degraded', tcc_coverage = 'reduced';
SQL
}

migrate_to_v7() {
    local database=$1
    sqlite3 "$database" <<'SQL'
ALTER TABLE launch_agents
    ADD COLUMN details_readable INTEGER NOT NULL DEFAULT 1;
ALTER TABLE launch_agents ADD COLUMN file_name TEXT;
UPDATE schema_version SET version = 7;
INSERT INTO grdb_migrations (identifier) VALUES ('v7');
UPDATE launch_agents SET details_readable = 0, file_name = 'fixture.plist';
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
v6_db="$tmp_dir/snapshots v6.db"
v7_db="$tmp_dir/snapshots v7.db"
invalid_readable_db="$tmp_dir/invalid readable.db"
missing_v7_column_db="$tmp_dir/missing v7 column.db"
partial_v6_shape_db="$tmp_dir/partial v6 shape.db"
missing_v7_ledger_db="$tmp_dir/missing v7 ledger.db"
invalid_coverage_db="$tmp_dir/invalid coverage.db"
missing_coverage_column_db="$tmp_dir/missing coverage column.db"
missing_v6_ledger_db="$tmp_dir/missing v6 ledger.db"
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
cp "$v5_db" "$v6_db"
migrate_to_v6 "$v6_db"
cp "$v6_db" "$v7_db"
migrate_to_v7 "$v7_db"
cp "$v7_db" "$invalid_readable_db"
cp "$v7_db" "$missing_v7_column_db"
cp "$v7_db" "$missing_v7_ledger_db"
cp "$v6_db" "$partial_v6_shape_db"
cp "$v7_db" "$invalid_coverage_db"
cp "$v7_db" "$missing_coverage_column_db"
cp "$v6_db" "$missing_v6_ledger_db"
cp "$v7_db" "$invalid_capture_db"
cp "$v7_db" "$invalid_disabled_db"
cp "$v4_db" "$invalid_shape_db"
cp "$v4_db" "$missing_capture_column_db"
cp "$v4_db" "$missing_disabled_column_db"
cp "$v7_db" "$future_db"
cp "$v7_db" "$missing_ledger_db"
cp "$v4_db" "$missing_v4_ledger_db"
cp "$v5_db" "$missing_v5_ledger_db"
cp "$v7_db" "$unexpected_ledger_db"
cp "$v7_db" "$duplicate_ledger_db"
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
sqlite3 "$future_db" 'UPDATE schema_version SET version = 8;'
sqlite3 "$invalid_readable_db" \
    'UPDATE launch_agents SET details_readable = 2;'
sqlite3 "$missing_v7_column_db" \
    'ALTER TABLE launch_agents DROP COLUMN file_name;'
sqlite3 "$partial_v6_shape_db" \
    'ALTER TABLE launch_agents ADD COLUMN file_name TEXT;'
sqlite3 "$missing_v7_ledger_db" \
    "DELETE FROM grdb_migrations WHERE identifier = 'v7';"
sqlite3 "$invalid_coverage_db" \
    "UPDATE snapshots SET tcc_coverage = 'partial';"
sqlite3 "$missing_coverage_column_db" \
    'ALTER TABLE snapshots DROP COLUMN btm_coverage;'
sqlite3 "$missing_v6_ledger_db" \
    "DELETE FROM grdb_migrations WHERE identifier = 'v6';"
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
INSERT INTO grdb_migrations (identifier) VALUES ('v7');
DROP TABLE grdb_migrations_original;
SQL

v4_before=$(shasum -a 256 "$v4_db")
v5_before=$(shasum -a 256 "$v5_db")
v6_before=$(shasum -a 256 "$v6_db")
v7_before=$(shasum -a 256 "$v7_db")

expect_success 'preserved v4 is pending when no launch can migrate it' \
    "$verifier" --database "$v4_db" --allow-pending-migration
expect_failure 'v4 is not v7-complete on a schema-expected path' \
    "$verifier" --database "$v4_db"
expect_success 'preserved v5 is pending when no launch can migrate it' \
    "$verifier" --database "$v5_db" --allow-pending-migration
expect_failure 'v5 is not v7-complete on a schema-expected path' \
    "$verifier" --database "$v5_db"
expect_success 'preserved v6 is pending when no launch can migrate it' \
    "$verifier" --database "$v6_db" --allow-pending-migration
expect_failure 'v6 is not v7-complete on a schema-expected path' \
    "$verifier" --database "$v6_db"
expect_failure 'v6 rejects a partial v7 shape' \
    "$verifier" --database "$partial_v6_shape_db" --allow-pending-migration
expect_success 'valid v7 is complete, including degraded and reduced coverage values' \
    "$verifier" --database "$v7_db"
expect_failure 'v7 rejects a details_readable value outside 0/1' \
    "$verifier" --database "$invalid_readable_db"
expect_failure 'v7 requires both launch_agents.details_readable and file_name' \
    "$verifier" --database "$missing_v7_column_db"
expect_failure 'v7 rejects a coverage value outside complete/reduced/degraded/failed' \
    "$verifier" --database "$invalid_coverage_db"
expect_failure 'v7 requires all three coverage columns' \
    "$verifier" --database "$missing_coverage_column_db"
expect_failure 'v7 rejects an invalid snapshot capture marker' \
    "$verifier" --database "$invalid_capture_db"
expect_failure 'v7 rejects an invalid LaunchAgent disabled marker' \
    "$verifier" --database "$invalid_disabled_db"
expect_failure 'v4 rejects a missing required pre-v5 column' \
    "$verifier" --database "$invalid_shape_db" --allow-pending-migration
expect_failure 'v5 requires the snapshot capture column' \
    "$verifier" --database "$missing_capture_column_db" --allow-pending-migration
expect_failure 'v5 requires the LaunchAgent disabled column' \
    "$verifier" --database "$missing_disabled_column_db" --allow-pending-migration
expect_failure 'future schema versions fail closed' \
    "$verifier" --database "$future_db"
expect_failure 'v7 requires the GRDB migration ledger table' \
    "$verifier" --database "$missing_ledger_db"
expect_failure 'schema v4 requires the exact v1-v4 migration ledger' \
    "$verifier" --database "$missing_v4_ledger_db" --allow-pending-migration
expect_failure 'schema v5 rejects a ledger missing v5' \
    "$verifier" --database "$missing_v5_ledger_db" --allow-pending-migration
expect_failure 'schema v6 rejects a ledger missing v6' \
    "$verifier" --database "$missing_v6_ledger_db" --allow-pending-migration
expect_failure 'schema v7 rejects a ledger missing v7' \
    "$verifier" --database "$missing_v7_ledger_db"
expect_failure 'schema v7 rejects an unexpected migration identifier' \
    "$verifier" --database "$unexpected_ledger_db"
expect_failure 'schema v7 rejects duplicate migration identifiers in a malformed ledger' \
    "$verifier" --database "$duplicate_ledger_db"
expect_failure 'a missing database is reported without creating it' \
    "$verifier" --database "$missing_db"

expect_output_success \
    'smoke accepts preserved v4 as pending under --keep --no-launch' \
    'schema version = 4 (pending app migration; not yet verified as schema v7)' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v4_db" \
    "$smoke_test" --keep --no-launch
expect_output_success \
    'smoke accepts preserved v5 as pending under --keep --no-launch' \
    'schema version = 5 (pending app migration; not yet verified as schema v7)' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v5_db" \
    "$smoke_test" --keep --no-launch
expect_output_success \
    'smoke accepts preserved v6 as pending under --keep --no-launch' \
    'schema version = 6 (pending app migration; not yet verified as schema v7)' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v6_db" \
    "$smoke_test" --keep --no-launch
expect_failure \
    'smoke rejects v6 when launch makes schema v7 expected' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v6_db" \
    "$smoke_test" --keep
expect_output_success \
    'smoke accepts valid v7 as complete' \
    'snapshots.db schema version = 7 (complete)' \
    env SMOKE_DRY_RUN=1 SMOKE_SCHEMA_CHECK_ONLY=1 SMOKE_DB_PATH="$v7_db" \
    "$smoke_test" --keep
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
[[ "$v6_before" == "$(shasum -a 256 "$v6_db")" ]] || {
    printf 'FAIL: v6 database changed during verification\n' >&2
    exit 1
}
[[ "$v7_before" == "$(shasum -a 256 "$v7_db")" ]] || {
    printf 'FAIL: v7 database changed during verification\n' >&2
    exit 1
}

printf 'PASS: snapshot schema verifier accepts pending v4/v5/v6 only without migration opportunity\n'
printf 'PASS: snapshot schema verifier validates v7 read-only and fails closed\n'
