#!/bin/sh
# Source this at the top of any script to redirect all output to the log file.
# Every command result, echo, and error is captured automatically.
# Rotates at 5MB keeping one backup.

LOG=/jffs/logs/router.log
LOG_MAX=5242880  # 5MB in bytes

mkdir -p /jffs/logs

# Rotate if over limit
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt "$LOG_MAX" ]; then
    mv "$LOG" "${LOG}.old"
fi

# Redirect all stdout and stderr to log file for the rest of the calling script
exec >> "$LOG" 2>&1

# Helper for annotated step messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2"
}
