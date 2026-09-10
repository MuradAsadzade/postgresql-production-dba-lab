#!/usr/bin/env bash

# PostgreSQL Production DBA Lab
# Replication alert wrapper
# Sends email only when replication health state changes.

MONITOR_SCRIPT="/opt/pgmonitor/replication_monitor.sh"
CONFIG_FILE="/etc/pgmonitor/pgmonitor.conf"
STATE_FILE="/var/lib/pgmonitor/replication_monitor.state"
MAIL_BIN="/bin/mail"

HOSTNAME=$(hostname)
CHECK_TIME=$(date '+%Y-%m-%d %H:%M:%S')

if [ ! -r "$CONFIG_FILE" ]; then
    echo "ERROR: Cannot read configuration file: $CONFIG_FILE"
    exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [ -z "${ALERT_EMAIL:-}" ]; then
    echo "ERROR: ALERT_EMAIL is not configured."
    exit 2
fi

MONITOR_OUTPUT=$("$MONITOR_SCRIPT" 2>&1)
MONITOR_EXIT_CODE=$?

case "$MONITOR_EXIT_CODE" in
    0)
        CURRENT_STATE="HEALTHY"
        ;;
    1)
        CURRENT_STATE="WARNING"
        ;;
    *)
        CURRENT_STATE="CRITICAL"
        ;;
esac

if [ -r "$STATE_FILE" ]; then
    PREVIOUS_STATE=$(cat "$STATE_FILE")
else
    PREVIOUS_STATE="UNKNOWN"
fi

printf '%s\n' "$CURRENT_STATE" > "$STATE_FILE"

echo "$MONITOR_OUTPUT"

# First execution while healthy: initialize state without sending email.
if [ "$PREVIOUS_STATE" = "UNKNOWN" ] && [ "$CURRENT_STATE" = "HEALTHY" ]; then
    exit "$MONITOR_EXIT_CODE"
fi

# No state change: do not send duplicate alerts.
if [ "$CURRENT_STATE" = "$PREVIOUS_STATE" ]; then
    exit "$MONITOR_EXIT_CODE"
fi

if [ "$CURRENT_STATE" = "HEALTHY" ]; then
    SUBJECT="[RECOVERY] PostgreSQL Replication Healthy - $HOSTNAME"
else
    SUBJECT="[$CURRENT_STATE] PostgreSQL Replication Alert - $HOSTNAME"
fi

{
    echo "PostgreSQL Replication Monitoring Alert"
    echo "======================================="
    echo
    echo "Server         : $HOSTNAME"
    echo "Time           : $CHECK_TIME"
    echo "Previous State : $PREVIOUS_STATE"
    echo "Current State  : $CURRENT_STATE"
    echo
    echo "$MONITOR_OUTPUT"
} | "$MAIL_BIN" -s "$SUBJECT" "$ALERT_EMAIL"

exit "$MONITOR_EXIT_CODE"
