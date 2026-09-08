#!/usr/bin/env bash

# PostgreSQL Production DBA Lab
# Streaming Replication Health Monitor

PSQL="/usr/pgsql-18/bin/psql"
DATABASE="postgres"
DB_HOST="127.0.0.1"
DB_USER="monitoring_user"

EXPECTED_STANDBYS=1

# 500 MB replication lag threshold
LAG_THRESHOLD_BYTES=$((500 * 1024 * 1024))

HOSTNAME=$(hostname)
CHECK_TIME=$(date '+%Y-%m-%d %H:%M:%S')

RESULT=$(
    "$PSQL" -h "$DB_HOST" -U "$DB_USER" -d "$DATABASE" -AtF '|' -c "
    SELECT
        COUNT(*) AS total_standbys,
        COUNT(*) FILTER (WHERE state = 'streaming') AS streaming_standbys,
        COALESCE(
            MAX(pg_wal_lsn_diff(sent_lsn, replay_lsn)),
            0
        )::bigint AS max_lag_bytes
    FROM pg_stat_replication;
    "
)

if [ $? -ne 0 ]; then
    echo "CRITICAL: Unable to query PostgreSQL replication status"
    echo "Server: $HOSTNAME"
    echo "Time: $CHECK_TIME"
    exit 2
fi

IFS='|' read -r TOTAL_STANDBYS STREAMING_STANDBYS LAG_BYTES <<< "$RESULT"

echo "PostgreSQL Replication Health Check"
echo "==================================="
echo "Server             : $HOSTNAME"
echo "Time               : $CHECK_TIME"
echo "Total Standbys     : $TOTAL_STANDBYS"
echo "Streaming Standbys : $STREAMING_STANDBYS"
echo "Replication Lag    : $LAG_BYTES bytes"
echo "Lag Threshold      : $LAG_THRESHOLD_BYTES bytes"
echo

if [ "$TOTAL_STANDBYS" -lt "$EXPECTED_STANDBYS" ]; then
    echo "STATUS: CRITICAL"
    echo "Reason: Expected standby is not connected."
    exit 2
fi

if [ "$STREAMING_STANDBYS" -lt "$EXPECTED_STANDBYS" ]; then
    echo "STATUS: CRITICAL"
    echo "Reason: Standby exists but is not streaming."
    exit 2
fi

if [ "$LAG_BYTES" -gt "$LAG_THRESHOLD_BYTES" ]; then
    echo "STATUS: WARNING"
    echo "Reason: Replication lag exceeded configured threshold."
    exit 1
fi

echo "STATUS: HEALTHY"
exit 0
