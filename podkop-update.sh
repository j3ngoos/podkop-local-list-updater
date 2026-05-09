#!/bin/sh
# Sync podkop lists from itdoginfo/allow-domains.
# Reloads podkop only if at least one file changed.
# Requires wget with SSL (wget-ssl on OpenWrt) — BusyBox stock wget lacks HTTPS.

LISTS="/etc/podkop/lists"
TMP="/tmp/podkop_update.$$"
LOCK="/tmp/podkop-updater.lock"
BASE="https://raw.githubusercontent.com/itdoginfo/allow-domains/main"
TAG="podkop-updater"

log() { logger -t "$TAG" "$1"; echo "[$(date '+%H:%M:%S')] $1"; }

is_valid_lst() {
    ! grep -qiE '<(html|head|body|!doctype|title)' "$1" && \
        grep -qE '^[a-zA-Z0-9.*]' "$1"
}

exec 9>"$LOCK"
if ! flock -n 9; then
    log "already running, exiting"
    exit 0
fi

trap 'rm -rf "$TMP"' EXIT INT TERM HUP
mkdir -p "$TMP" || { log "cannot create $TMP"; exit 1; }
mkdir -p "$LISTS/domains" "$LISTS/subnets"

CHANGED=0
FAILED=0

# $1=repo_path  $2=domains|subnets  $3=filename
sync_one() {
    local url="$BASE/$1"
    local dst="$LISTS/$2/$3"
    local new="$TMP/$2-$3"
    local stage="$dst.new"

    if ! wget -q -T 30 -O "$new" "$url" || [ ! -s "$new" ]; then
        log "FAIL    $1"
        FAILED=$((FAILED+1))
        return
    fi

    if ! is_valid_lst "$new"; then
        log "INVALID $1 (failed sanity check)"
        FAILED=$((FAILED+1))
        return
    fi

    if [ -f "$dst" ] && cmp -s "$new" "$dst"; then
        return
    fi

    # Stage on the same FS as $dst so the final rename is atomic.
    if ! cp "$new" "$stage"; then
        rm -f "$stage"
        log "FAIL    $1 (cp to $stage failed)"
        FAILED=$((FAILED+1))
        return
    fi
    if ! mv "$stage" "$dst"; then
        rm -f "$stage"
        log "FAIL    $1 (mv to $dst failed)"
        FAILED=$((FAILED+1))
        return
    fi
    log "UPDATED $2/$3"
    CHANGED=$((CHANGED+1))
}

log "Checking for list updates..."

sync_one "Russia/inside-raw.lst"      domains  russia_inside.lst
sync_one "Services/discord.lst"       domains  discord.lst
sync_one "Services/twitter.lst"       domains  twitter.lst
sync_one "Services/meta.lst"          domains  meta.lst
sync_one "Services/google_ai.lst"     domains  google_ai.lst
sync_one "Services/roblox.lst"        domains  roblox.lst
sync_one "Services/telegram.lst"      domains  telegram.lst

sync_one "Subnets/IPv4/discord.lst"   subnets  discord.lst
sync_one "Subnets/IPv4/twitter.lst"   subnets  twitter.lst
sync_one "Subnets/IPv4/meta.lst"      subnets  meta.lst
sync_one "Subnets/IPv4/roblox.lst"    subnets  roblox.lst
sync_one "Subnets/IPv4/telegram.lst"  subnets  telegram.lst

if [ "$CHANGED" -gt 0 ]; then
    log "$CHANGED file(s) updated, $FAILED failed — reloading podkop"
    if /etc/init.d/podkop reload; then
        log "podkop reloaded"
    else
        rc=$?
        log "ERROR: podkop reload failed (exit $rc)"
        exit 1
    fi
elif [ "$FAILED" -gt 0 ]; then
    log "no changes, $FAILED download(s) failed"
else
    log "all lists up to date"
fi
