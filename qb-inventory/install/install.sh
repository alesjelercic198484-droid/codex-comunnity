#!/usr/bin/env bash
# =============================================================================
#  CodeX Roleplay Inventory - installer for qb-core
#
#  Usage (on your server, via SSH):
#
#     bash install.sh /path/to/resources
#
#  If you leave the path out, the script looks for your resources folder in the
#  usual places.
#
#  What it does:
#    1. backs up your current qb-inventory (if there is one)
#    2. downloads this branch
#    3. puts the folder down as `qb-inventory`   <- the name is REQUIRED
#    4. prints what you still have to add to server.cfg
#
#  It never touches server.cfg, your database or any other resource.
# =============================================================================
set -euo pipefail

BRANCH="arena/783f2a94-codex-comunnity"
REPO="https://github.com/alesjelercic198484-droid/codex-comunnity.git"
RESOURCE="qb-inventory"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mfail\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. find the resources folder
# ---------------------------------------------------------------------------
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
    for guess in \
        "$HOME/server-data/resources" \
        "$HOME/server/resources" \
        "$HOME/resources" \
        "/home/container/resources" \
        "/home/fivem/server-data/resources" \
        "/root/server-data/resources" \
        "$(pwd)/resources" \
        "$(pwd)"; do
        if [ -d "$guess" ]; then TARGET="$guess"; break; fi
    done
fi

[ -n "$TARGET" ] || die "No resources folder found. Run: bash install.sh /path/to/resources"
[ -d "$TARGET" ] || die "Folder does not exist: $TARGET"

# most qb-core servers keep framework resources in [qb]
if [ -d "$TARGET/[qb]" ]; then
    TARGET="$TARGET/[qb]"
fi

say "Installing into: $TARGET"

command -v git >/dev/null 2>&1 || die "git is not installed on this server."

# ---------------------------------------------------------------------------
# 2. back up the current inventory
# ---------------------------------------------------------------------------
if [ -d "$TARGET/$RESOURCE" ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP="$TARGET/${RESOURCE}.backup-$STAMP"
    say "Backing up your current $RESOURCE -> $(basename "$BACKUP")"
    mv "$TARGET/$RESOURCE" "$BACKUP"
    ok "backup created"
else
    say "No existing $RESOURCE found - fresh install."
fi

# ---------------------------------------------------------------------------
# 3. download
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading $RESOURCE (branch $BRANCH)..."
git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMP/codex" >/dev/null 2>&1 \
    || die "git clone failed. Check your internet connection on the server."

[ -d "$TMP/codex/$RESOURCE" ] || die "Downloaded repo does not contain $RESOURCE."

mv "$TMP/codex/$RESOURCE" "$TARGET/$RESOURCE"
ok "$RESOURCE installed"

# make sure the file list is complete
MISSING=0
for f in fxmanifest.lua config.lua client/main.lua client/pedpreview.lua \
         server/core.lua server/main.lua html/index.html html/style.css \
         html/app.js html/locales.js; do
    if [ ! -f "$TARGET/$RESOURCE/$f" ]; then
        warn "missing file: $f"
        MISSING=1
    fi
done
[ "$MISSING" -eq 0 ] && ok "all 10 required files are present"

# ---------------------------------------------------------------------------
# 4. optional: SQL for persistent stashes
# ---------------------------------------------------------------------------
if [ -f "$TARGET/$RESOURCE/install/qb_inventory_codex.sql" ]; then
    say "Optional: for stashes that survive a restart, import"
    echo "     $TARGET/$RESOURCE/install/qb_inventory_codex.sql"
    echo "  (without it everything still works, stashes just reset on restart)"
fi

# ---------------------------------------------------------------------------
# 5. what to do next
# ---------------------------------------------------------------------------
printf '%b\n' \
    "" \
    "\033[1;32mDone.\033[0m" \
    "" \
    "Now add the resource to server.cfg, AFTER qb-core:" \
    "" \
    "    ensure qb-core" \
    "    ensure qb-weapons" \
    "    ensure $RESOURCE" \
    "" \
    "Then restart the server and press \033[1mTAB\033[0m in game." \
    "" \
    "If something is wrong, your old inventory is in:" \
    "    $( [ -n "${BACKUP:-}" ] && echo "$BACKUP" || echo "(no backup was needed)" )" \
    ""
