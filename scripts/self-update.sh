#!/bin/sh
. /jffs/scripts/log.sh

REPO="https://github.com/ivan-strogan/asus-rt-ac56u-hotspot-router.git"
TMP_DIR="/tmp/router-update"
SCRIPTS_DIR="/jffs/scripts"
BACKUP_DIR="/jffs/previous"

# Add Entware bin to PATH but do NOT export LD_LIBRARY_PATH globally —
# it causes Entware's glibc to corrupt the busybox environment.
# LD_LIBRARY_PATH is passed only to git via env wrapper below.
export PATH="/opt/bin:/opt/libexec/git-core:/opt/sbin:$PATH"
GIT="env LD_LIBRARY_PATH=/opt/lib /opt/bin/git"

log "self-update" "--- starting update check ---"

if [ ! -x "/opt/bin/git" ]; then
    log "self-update" "ERROR: git not found at /opt/bin/git"
    exit 0
fi

CURRENT_COMMIT=$(cat /jffs/current-commit 2>/dev/null || echo "none")
log "self-update" "current commit: $CURRENT_COMMIT"

rm -rf "$TMP_DIR"

log "self-update" "cloning $REPO"
$GIT clone --depth 1 --quiet "$REPO" "$TMP_DIR"
if [ $? -ne 0 ]; then
    log "self-update" "ERROR: git clone failed"
    rm -rf "$TMP_DIR"
    exit 0
fi

NEW_COMMIT=$($GIT -C "$TMP_DIR" rev-parse --short HEAD 2>/dev/null)
log "self-update" "remote commit: $NEW_COMMIT"

if [ "$CURRENT_COMMIT" = "$NEW_COMMIT" ]; then
    log "self-update" "already up to date"
    rm -rf "$TMP_DIR"
    exit 0
fi

log "self-update" "new commit detected - deploying $CURRENT_COMMIT -> $NEW_COMMIT"

log "self-update" "backing up current scripts to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -v "$SCRIPTS_DIR"/* "$BACKUP_DIR/"

log "self-update" "deploying scripts"
for f in "$TMP_DIR/scripts/"*; do
    name=$(basename "$f")
    cp -v "$f" "$SCRIPTS_DIR/$name"
    case "$name" in
        *.sh|services-start|firewall-start|init-start|wan-watchdog.sh|self-update.sh)
            chmod +x "$SCRIPTS_DIR/$name" ;;
    esac
done

echo "$NEW_COMMIT" > /jffs/current-commit

log "self-update" "reloading watchdog cron"
cru d wan-watchdog 2>/dev/null
cru a wan-watchdog "* * * * * $SCRIPTS_DIR/wan-watchdog.sh"
cru l

log "self-update" "update complete: $CURRENT_COMMIT -> $NEW_COMMIT"

rm -rf "$TMP_DIR"
