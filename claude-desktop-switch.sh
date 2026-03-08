#!/bin/bash

# Claude Desktop Account Switcher
# Switches between two Anthropic accounts while sharing MCP config.
# Usage:
#   ./claude-desktop-switch.sh save-current <account_name>   # First-time save
#   ./claude-desktop-switch.sh <account_name>                # Switch to account
#   ./claude-desktop-switch.sh next                          # Switch to next account
#   ./claude-desktop-switch.sh list                          # List saved accounts
#   ./claude-desktop-switch.sh status                        # Show current account

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
CLAUDE_APP_SUPPORT="$HOME/Library/Application Support/Claude"
ACCOUNTS_DIR="$HOME/.claude-desktop-accounts"
SAFETY_DIR="$ACCOUNTS_DIR/.safety-snapshots"
CURRENT_ACCOUNT_FILE="$ACCOUNTS_DIR/.current"

mkdir -p "$ACCOUNTS_DIR" "$SAFETY_DIR"

# ── Files to swap per account (auth + history) ───────────────────────────────
# claude_desktop_config.json is intentionally excluded — shared across accounts
SWAP_FILES=(
    "ant-did"
    "config.json"
    "Cookies"
    "Cookies-journal"
)
SWAP_DIRS=(
    "IndexedDB"
    "Local Storage"
    "Session Storage"
)

# ── Helpers ──────────────────────────────────────────────────────────────────
die() { echo "❌ $*" >&2; exit 1; }

is_running() {
    pgrep -x "Claude" > /dev/null 2>&1
}

quit_claude() {
    if is_running; then
        echo "⏳ Quitting Claude Desktop..."
        osascript -e 'quit app "Claude"' 2>/dev/null || pkill -x "Claude" 2>/dev/null || true
        # Wait up to 10s for it to quit
        for i in $(seq 1 10); do
            sleep 1
            is_running || break
        done
        is_running && die "Claude Desktop didn't quit in time. Close it manually and retry."
        echo "✅ Claude Desktop quit."
    fi
}

launch_claude() {
    echo "🚀 Launching Claude Desktop..."
    open -a "Claude"
}

# ── Safety snapshot ──────────────────────────────────────────────────────────
safety_snapshot() {
    local label="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local snap="$SAFETY_DIR/${timestamp}_${label}"
    mkdir -p "$snap"

    for f in "${SWAP_FILES[@]}"; do
        [ -f "$CLAUDE_APP_SUPPORT/$f" ] && cp "$CLAUDE_APP_SUPPORT/$f" "$snap/" 2>/dev/null || true
    done
    for d in "${SWAP_DIRS[@]}"; do
        [ -d "$CLAUDE_APP_SUPPORT/$d" ] && cp -r "$CLAUDE_APP_SUPPORT/$d" "$snap/" 2>/dev/null || true
    done

    echo "📸 Safety snapshot: ${timestamp}_${label}"

    # Keep only last 5 snapshots
    ls -dt "$SAFETY_DIR"/*/ 2>/dev/null | tail -n +6 | while read -r old; do
        rm -rf "$old"
    done
}

# ── Save current account state ───────────────────────────────────────────────
save_account() {
    local account="$1"
    local dest="$ACCOUNTS_DIR/$account"
    mkdir -p "$dest"

    echo "💾 Saving current state as '$account'..."
    for f in "${SWAP_FILES[@]}"; do
        [ -f "$CLAUDE_APP_SUPPORT/$f" ] && cp "$CLAUDE_APP_SUPPORT/$f" "$dest/" 2>/dev/null || true
    done
    for d in "${SWAP_DIRS[@]}"; do
        [ -d "$CLAUDE_APP_SUPPORT/$d" ] && cp -r "$CLAUDE_APP_SUPPORT/$d" "$dest/" 2>/dev/null || true
    done

    echo "$account" > "$CURRENT_ACCOUNT_FILE"
    echo "✅ Saved as '$account'."
}

# ── Restore an account's state ───────────────────────────────────────────────
restore_account() {
    local account="$1"
    local src="$ACCOUNTS_DIR/$account"
    [ -d "$src" ] || die "Account '$account' not found. Run: $0 save-current $account"

    echo "🔄 Restoring '$account'..."
    for f in "${SWAP_FILES[@]}"; do
        [ -f "$src/$f" ] && cp "$src/$f" "$CLAUDE_APP_SUPPORT/" 2>/dev/null || true
    done
    for d in "${SWAP_DIRS[@]}"; do
        if [ -d "$src/$d" ]; then
            rm -rf "$CLAUDE_APP_SUPPORT/$d"
            cp -r "$src/$d" "$CLAUDE_APP_SUPPORT/" 2>/dev/null || true
        fi
    done

    echo "$account" > "$CURRENT_ACCOUNT_FILE"
    echo "✅ Restored '$account'."
}

# ── Commands ─────────────────────────────────────────────────────────────────
cmd_save_current() {
    local account="${1:-}"
    [ -n "$account" ] || die "Usage: $0 save-current <account_name>"
    is_running && die "Claude Desktop is running. Quit it before saving."
    save_account "$account"
}

cmd_switch() {
    local account="$1"
    local current=""
    [ -f "$CURRENT_ACCOUNT_FILE" ] && current=$(cat "$CURRENT_ACCOUNT_FILE")

    [ -d "$ACCOUNTS_DIR/$account" ] || die "Account '$account' not found. Run: $0 save-current $account"

    if [ "$current" = "$account" ]; then
        echo "✅ Already on '$account'."
        is_running || launch_claude
        exit 0
    fi

    quit_claude
    safety_snapshot "before-switch-to-$account"

    # Auto-save current account if known
    if [ -n "$current" ] && [ -d "$ACCOUNTS_DIR/$current" ]; then
        echo "💾 Auto-saving '$current'..."
        save_account "$current"
    else
        echo "⚠️  Current account unknown — state saved to safety snapshot only."
    fi

    restore_account "$account"
    launch_claude
    echo ""
    echo "✅ Switched to '$account' and relaunched Claude Desktop."
}

cmd_next() {
    local current=""
    [ -f "$CURRENT_ACCOUNT_FILE" ] && current=$(cat "$CURRENT_ACCOUNT_FILE")

    # Build sorted list of accounts
    local accounts=()
    for d in "$ACCOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        local name
        name=$(basename "$d")
        [[ "$name" == .* ]] && continue
        accounts+=("$name")
    done

    [ ${#accounts[@]} -eq 0 ] && die "No accounts saved. Run: $0 save-current <account_name>"
    [ ${#accounts[@]} -eq 1 ] && die "Only one account saved ('${accounts[0]}'). Save a second with: $0 save-current <account_name>"

    # Find index of current account, pick the next one (wrapping around)
    local next=""
    local found=0
    for i in "${!accounts[@]}"; do
        if [ "${accounts[$i]}" = "$current" ]; then
            local next_index=$(( (i + 1) % ${#accounts[@]} ))
            next="${accounts[$next_index]}"
            found=1
            break
        fi
    done

    # If current account not found in list, just pick the first
    [ $found -eq 0 ] && next="${accounts[0]}"

    echo "➡️  Next account: '$next'"
    cmd_switch "$next"
}

cmd_list() {
    echo "Saved accounts:"
    local current=""
    [ -f "$CURRENT_ACCOUNT_FILE" ] && current=$(cat "$CURRENT_ACCOUNT_FILE")
    found=0
    for d in "$ACCOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        [[ "$name" == .* ]] && continue
        size=$(du -sh "$d" 2>/dev/null | cut -f1)
        marker=""
        [ "$name" = "$current" ] && marker=" ◀ current"
        echo "  - $name ($size)$marker"
        found=1
    done
    [ $found -eq 0 ] && echo "  (none — run '$0 save-current <name>' to get started)"
}

cmd_status() {
    if [ -f "$CURRENT_ACCOUNT_FILE" ]; then
        echo "✅ Current account: $(cat "$CURRENT_ACCOUNT_FILE")"
    else
        echo "❓ No account saved yet."
    fi
    echo ""
    echo "Claude Desktop: $(is_running && echo 'running' || echo 'not running')"
    echo ""
    echo "Safety snapshots:"
    ls -dt "$SAFETY_DIR"/*/ 2>/dev/null | head -5 | while read -r d; do
        echo "  $(basename "$d") ($(du -sh "$d" | cut -f1))"
    done || echo "  (none)"
}

# ── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
    "next")
        cmd_next
        ;;
    "save-current")
        cmd_save_current "${2:-}"
        ;;
    "list")
        cmd_list
        ;;
    "status")
        cmd_status
        ;;
    "")
        echo "Claude Desktop Account Switcher"
        echo ""
        echo "Usage:"
        echo "  $0 save-current <name>   Save current account (Claude must be quit first)"
        echo "  $0 <name>                Switch to account (auto-quits and relaunches)"
        echo "  $0 next                  Switch to next account in rotation"
        echo "  $0 list                  List saved accounts"
        echo "  $0 status                Show current account and snapshots"
        echo ""
        echo "MCP config (claude_desktop_config.json) is shared across all accounts."
        ;;
    *)
        cmd_switch "$1"
        ;;
esac
