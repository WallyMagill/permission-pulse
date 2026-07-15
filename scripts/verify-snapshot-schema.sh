#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'usage: %s --database PATH [--allow-pending-v4]\n' "$0" >&2
}

database=''
allow_pending_v4=0
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
        --allow-pending-v4)
            allow_pending_v4=1
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

for table in schema_version snapshots tcc_grants btm_items launch_agents; do
    table_count=$(readonly_query \
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';") \
        || fail_schema "could not inspect table $table"
    [[ "$table_count" == '1' ]] || fail_schema "missing table $table"
done

for required_column in \
    schema_version:version \
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
[[ "$versions" == '4' || "$versions" == '5' ]] \
    || fail_schema "unsupported schema version set: ${versions:-empty}"

snapshot_marker_columns=$(readonly_query \
    "SELECT COUNT(*) FROM pragma_table_info('snapshots') WHERE name = 'launch_agent_disabled_captured';") \
    || fail_schema 'could not inspect snapshots columns'
disabled_columns=$(readonly_query \
    "SELECT COUNT(*) FROM pragma_table_info('launch_agents') WHERE name = 'is_disabled';") \
    || fail_schema 'could not inspect launch_agents columns'

if [[ "$versions" == '4' ]]; then
    [[ $allow_pending_v4 -eq 1 ]] \
        || fail_schema 'schema version 4 is pending migration and is not v5-complete'
    [[ "$snapshot_marker_columns" == '0' && "$disabled_columns" == '0' ]] \
        || fail_schema 'schema version 4 has a partial or inconsistent v5 shape'
    snapshot_count=$(readonly_query 'SELECT COUNT(*) FROM snapshots;') \
        || fail_schema 'could not count snapshots'
    printf 'status=pending-v4\n'
    printf 'schema_version=4\n'
    printf 'snapshot_count=%s\n' "$snapshot_count"
    exit 0
fi

[[ "$snapshot_marker_columns" == '1' ]] \
    || fail_schema 'schema version 5 requires snapshots.launch_agent_disabled_captured'
[[ "$disabled_columns" == '1' ]] \
    || fail_schema 'schema version 5 requires launch_agents.is_disabled'

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

snapshot_count=$(readonly_query 'SELECT COUNT(*) FROM snapshots;') \
    || fail_schema 'could not count snapshots'
printf 'status=complete-v5\n'
printf 'schema_version=5\n'
printf 'snapshot_count=%s\n' "$snapshot_count"
