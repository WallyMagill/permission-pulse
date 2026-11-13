#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'usage: %s --database PATH [--allow-pending-migration]\n' "$0" >&2
}

database=''
allow_pending_migration=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --database)
            [[ $# -ge 2 ]] || {
                usage
                exit 2
            }
            database=$2
            shift 2
            ;;
        --allow-pending-migration)
            allow_pending_migration=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

[[ -n "$database" ]] || {
    usage
    exit 2
}
[[ -f "$database" ]] || {
    printf 'snapshot database does not exist: %s\n' "$database" >&2
    exit 1
}
command -v sqlite3 >/dev/null 2>&1 || {
    printf 'sqlite3 is required to verify the snapshot schema\n' >&2
    exit 1
}

readonly_query() {
    sqlite3 -readonly "$database" "PRAGMA query_only = ON; $1"
}

fail_schema() {
    printf 'invalid snapshot database: %s\n' "$1" >&2
    exit 1
}

for table in schema_version snapshots tcc_grants btm_items launch_agents grdb_migrations; do
    table_count=$(readonly_query \
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';") \
        || fail_schema "could not inspect table $table"
    [[ "$table_count" == '1' ]] || fail_schema "missing table $table"
done

for required_column in \
    schema_version:version \
    grdb_migrations:identifier \
    snapshots:id \
    snapshots:created_at \
    launch_agents:id \
    launch_agents:snapshot_id \
    launch_agents:label \
    launch_agents:source_directory \
    launch_agents:program_path \
    launch_agents:program_arguments_json \
    launch_agents:run_at_load \
    launch_agents:keep_alive \
    tcc_grants:id \
    tcc_grants:snapshot_id \
    tcc_grants:service \
    tcc_grants:bundle_id \
    tcc_grants:display_name \
    tcc_grants:bundle_path \
    tcc_grants:last_modified \
    tcc_grants:automation_target \
    tcc_grants:auth_value \
    btm_items:id \
    btm_items:snapshot_id \
    btm_items:identifier \
    btm_items:name \
    btm_items:developer_name \
    btm_items:bundle_identifier \
    btm_items:team_identifier \
    btm_items:type_kind \
    btm_items:type_raw \
    btm_items:disposition_kind \
    btm_items:disposition_raw \
    btm_items:scope_kind \
    btm_items:scope_per_user_uuid \
    btm_items:modification_date \
    btm_items:parent_identifier; do
    table=${required_column%%:*}
    column=${required_column#*:}
    column_count=$(readonly_query \
        "SELECT COUNT(*) FROM pragma_table_info('$table') WHERE name = '$column';") \
        || fail_schema "could not inspect $table.$column"
    [[ "$column_count" == '1' ]] || fail_schema "missing column $table.$column"
done

versions=$(readonly_query \
    "SELECT group_concat(version, ',') FROM schema_version;") \
    || fail_schema 'could not read schema version'
# 6 is the schema this release writes. 4 and 5 are older schemas the app
# migrates on its next launch; they pass only as "pending" and only when the
# caller says the app had no chance to migrate (--allow-pending-migration).
case "$versions" in
    4) expected_migrations='v1,v2,v3,v4' ;;
    5) expected_migrations='v1,v2,v3,v4,v5' ;;
    6) expected_migrations='v1,v2,v3,v4,v5,v6' ;;
    *) fail_schema "unsupported schema version set: ${versions:-empty} (supported: 4, 5, 6)" ;;
esac
expected_migration_count=$versions
migration_count=$(readonly_query 'SELECT COUNT(*) FROM grdb_migrations;') \
    || fail_schema 'could not count GRDB migrations'
migrations=$(readonly_query \
    "SELECT group_concat(identifier, ',') FROM (SELECT identifier FROM grdb_migrations ORDER BY identifier);") \
    || fail_schema 'could not read GRDB migrations'
[[ "$migration_count" == "$expected_migration_count" \
    && "$migrations" == "$expected_migrations" ]] \
    || fail_schema \
        "schema version $versions requires exact GRDB migrations $expected_migrations; found ${migrations:-empty} (count $migration_count)"

column_count() {
    readonly_query \
        "SELECT COUNT(*) FROM pragma_table_info('$1') WHERE name = '$2';" \
        || fail_schema "could not inspect $1.$2"
}

snapshot_marker_columns=$(column_count snapshots launch_agent_disabled_captured)
disabled_columns=$(column_count launch_agents is_disabled)
coverage_columns=0
for coverage_column in tcc_coverage btm_coverage launch_agent_coverage; do
    present=$(column_count snapshots "$coverage_column")
    coverage_columns=$((coverage_columns + present))
done

report_pending() {
    [[ $allow_pending_migration -eq 1 ]] \
        || fail_schema "schema version $versions is pending migration and is not v6-complete"
    snapshot_count=$(readonly_query 'SELECT COUNT(*) FROM snapshots;') \
        || fail_schema 'could not count snapshots'
    printf 'status=pending-v%s\n' "$versions"
    printf 'schema_version=%s\n' "$versions"
    printf 'snapshot_count=%s\n' "$snapshot_count"
    exit 0
}

if [[ "$versions" == '4' ]]; then
    [[ "$snapshot_marker_columns" == '0' && "$disabled_columns" == '0' \
        && "$coverage_columns" == '0' ]] \
        || fail_schema 'schema version 4 has a partial or inconsistent later-schema shape'
    report_pending
fi

[[ "$snapshot_marker_columns" == '1' ]] \
    || fail_schema "schema version $versions requires snapshots.launch_agent_disabled_captured"
[[ "$disabled_columns" == '1' ]] \
    || fail_schema "schema version $versions requires launch_agents.is_disabled"

invalid_capture_markers=$(readonly_query \
    'SELECT COUNT(*) FROM snapshots WHERE launch_agent_disabled_captured IS NULL OR launch_agent_disabled_captured NOT IN (0, 1);') \
    || fail_schema 'could not validate snapshot capture markers'
[[ "$invalid_capture_markers" == '0' ]] \
    || fail_schema "$invalid_capture_markers invalid snapshot capture marker(s)"

invalid_disabled_markers=$(readonly_query \
    'SELECT COUNT(*) FROM launch_agents WHERE is_disabled IS NULL OR is_disabled NOT IN (0, 1);') \
    || fail_schema 'could not validate LaunchAgent disabled markers'
[[ "$invalid_disabled_markers" == '0' ]] \
    || fail_schema "$invalid_disabled_markers invalid LaunchAgent disabled marker(s)"

if [[ "$versions" == '5' ]]; then
    [[ "$coverage_columns" == '0' ]] \
        || fail_schema 'schema version 5 has a partial or inconsistent v6 shape'
    report_pending
fi

[[ "$coverage_columns" == '3' ]] \
    || fail_schema "schema version 6 requires snapshots.tcc_coverage, btm_coverage, and launch_agent_coverage; found $coverage_columns of 3"

invalid_coverage=$(readonly_query \
    "SELECT COUNT(*) FROM snapshots WHERE COALESCE(tcc_coverage, '') NOT IN ('complete', 'reduced', 'degraded', 'failed') OR COALESCE(btm_coverage, '') NOT IN ('complete', 'reduced', 'degraded', 'failed') OR COALESCE(launch_agent_coverage, '') NOT IN ('complete', 'reduced', 'degraded', 'failed');") \
    || fail_schema 'could not validate snapshot coverage values'
[[ "$invalid_coverage" == '0' ]] \
    || fail_schema "$invalid_coverage snapshot(s) with a coverage value outside complete/reduced/degraded/failed"

snapshot_count=$(readonly_query 'SELECT COUNT(*) FROM snapshots;') \
    || fail_schema 'could not count snapshots'
printf 'status=complete-v6\n'
printf 'schema_version=6\n'
printf 'snapshot_count=%s\n' "$snapshot_count"
