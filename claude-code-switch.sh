#!/bin/bash

# Claude Code Account Switcher (VS Code / CLI)
#
# Switches between two Anthropic accounts while sharing conversation history,
# settings, MCP config, todos, plans, and file history across both accounts.
#
# Usage:
#   ./claude-code-switch.sh setup                     # First-time setup
#   ./claude-code-switch.sh save-current <name>       # Save current account
#   ./claude-code-switch.sh <name>                    # Switch to account
#   ./claude-code-switch.sh list                      # List saved accounts
#   ./claude-code-switch.sh status                    # Show current account
#   ./claude-code-switch.sh restore-snapshot          # List recovery snapshots

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON="$HOME/.claude.json"
ACCOUNTS_DIR="$HOME/.claude-code-accounts"
SHARED_DIR="$HOME/.claude-shared"
SAFETY_DIR="$ACCOUNTS_DIR/.safety-snapshots"
CURRENT_FILE="$ACCOUNTS_DIR/.current"

# ── Directories/files to symlink to shared location ───────────────────────────
SHARED_ITEMS=(
    "projects"
    "settings.json"
    ".mcp.json"
    "plugins"
    "todos"
    "plans"
    "session-env"
    "file-history"
)

# ── Helpers ───────────────────────────────────────────────────────────────────
die()  { echo "❌ $*" >&2; exit 1; }
info() { echo "   $*"; }

current_account() {
    [ -f "$CURRENT_FILE" ] && cat "$CURRENT_FILE" || echo ""
}

# ── First-time setup ──────────────────────────────────────────────────────────
cmd_setup() {
    echo "🔧 Setting up Claude Code account switcher..."
    echo ""

    mkdir -p "$ACCOUNTS_DIR" "$SAFETY_DIR" "$SHARED_DIR"

    # Move shared items from ~/.claude into ~/.claude-shared (if not already symlinks)
    for item in "${SHARED_ITEMS[@]}"; do
        src="$CLAUDE_DIR/$item"
        dest="$SHARED_DIR/$item"

        if [ -L "$src" ]; then
            info "Already symlinked: $item — skipping"
            continue
        fi

        if [ -e "$src" ]; then
            info "Moving $item → ~/.claude-shared/"
            mv "$src" "$dest"
        else
            info "Creating empty shared $item"
            # Create empty file or directory as appropriate
            if [[ "$item" == *.json ]]; then
                echo '{}' > "$dest"
            else
                mkdir -p "$dest"
            fi
        fi

        # Create symlink
        ln -s "$dest" "$src"
        info "Linked: ~/.claude/$item → ~/.claude-shared/$item"
    done

    echo ""
    echo "✅ Shared items set up in ~/.claude-shared/"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./claude-code-switch.sh save-current <name>"
    echo "     (e.g. 'personal' for your currently logged-in account)"
    echo "  2. Log into your second account with: claude /login"
    echo "  3. Run: ./claude-code-switch.sh save-current <name>"
    echo "     (e.g. 'work')"
    echo "  4. Switch any time with: ./claude-code-switch.sh <name>"
}

# ── Safety snapshot ───────────────────────────────────────────────────────────
safety_snapshot() {
    local label="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local snap="$SAFETY_DIR/${timestamp}_${label}"
    mkdir -p "$snap"

    # Snapshot the swapped items only (not symlinked shared items)
    [ -f "$CLAUDE_JSON" ] && cp "$CLAUDE_JSON" "$snap/claude.json" 2>/dev/null || true
    [ -d "$CLAUDE_DIR/backups" ] && cp -r "$CLAUDE_DIR/backups" "$snap/backups" 2>/dev/null || true

    echo "📸 Safety snapshot: ${timestamp}_${label}"

    # Keep only last 5 snapshots
    ls -dt "$SAFETY_DIR"/*/ 2>/dev/null | tail -n +6 | while read -r old; do
        rm -rf "$old"
    done
}

# ── Save current account ──────────────────────────────────────────────────────
RESERVED_NAMES=("next" "list" "status" "save-current" "restore-snapshot" "setup" "help")

is_reserved() {
    local name="$1"
    for r in "${RESERVED_NAMES[@]}"; do
        [ "$name" = "$r" ] && return 0
    done
    return 1
}

cmd_save_current() {
    local account="${1:-}"
    [ -n "$account" ] || die "Usage: $0 save-current <account_name>"
    is_reserved "$account" && die "'$account' is a reserved command name. Choose a different account name."

    [ -d "$SHARED_DIR" ] || die "Run '$0 setup' first."

    local dest="$ACCOUNTS_DIR/$account"
    mkdir -p "$dest"

    echo "💾 Saving current state as '$account'..."

    [ -f "$CLAUDE_JSON" ] && cp "$CLAUDE_JSON" "$dest/claude.json" || true
    [ -d "$CLAUDE_DIR/backups" ] && cp -r "$CLAUDE_DIR/backups" "$dest/backups" || true

    echo "$account" > "$CURRENT_FILE"
    echo "✅ Saved as '$account'."
}

# ── Switch account ────────────────────────────────────────────────────────────
cmd_switch() {
    local account="$1"
    local current
    current=$(current_account)

    is_reserved "$account" && die "'$account' is a reserved command name, not an account."
    [ -d "$ACCOUNTS_DIR/$account" ] || die "Account '$account' not found. Run: $0 save-current $account"
    [ -d "$SHARED_DIR" ] || die "Run '$0 setup' first."

    if [ "$current" = "$account" ]; then
        echo "✅ Already on '$account'."
        exit 0
    fi

    # Verify symlinks are in place; fix any that are missing
    for item in "${SHARED_ITEMS[@]}"; do
        local link="$CLAUDE_DIR/$item"
        local target="$SHARED_DIR/$item"
        if [ ! -L "$link" ]; then
            echo "⚠️  Symlink missing for $item — re-linking..."
            [ -e "$link" ] && mv "$link" "${link}.bak.$$"
            [ -e "$target" ] || ([ "${item##*.}" = "json" ] && echo '{}' > "$target" || mkdir -p "$target")
            ln -s "$target" "$link"
        fi
    done

    safety_snapshot "before-switch-to-$account"

    # Auto-save current account
    if [ -n "$current" ] && [ -d "$ACCOUNTS_DIR/$current" ]; then
        echo "💾 Auto-saving '$current'..."
        local tmp="$ACCOUNTS_DIR/$current"
        mkdir -p "$tmp"
        [ -f "$CLAUDE_JSON" ] && cp "$CLAUDE_JSON" "$tmp/claude.json" || true
        [ -d "$CLAUDE_DIR/backups" ] && { rm -rf "$tmp/backups"; cp -r "$CLAUDE_DIR/backups" "$tmp/backups"; } || true
    else
        echo "⚠️  Current account unknown — state saved to safety snapshot only."
    fi

    # Restore target account
    echo "🔄 Switching to '$account'..."
    local src="$ACCOUNTS_DIR/$account"

    [ -f "$src/claude.json" ] && cp "$src/claude.json" "$CLAUDE_JSON" || true
    if [ -d "$src/backups" ]; then
        rm -rf "$CLAUDE_DIR/backups"
        cp -r "$src/backups" "$CLAUDE_DIR/backups"
    fi

    echo "$account" > "$CURRENT_FILE"
    echo ""
    echo "✅ Switched to '$account'."
    echo "   Start a new Claude Code session in VS Code or terminal to pick up the new account."
}

# ── Next account ──────────────────────────────────────────────────────────────
cmd_next() {
    local current
    current=$(current_account)

    # Build sorted list of valid accounts (must contain claude.json, not reserved)
    local accounts=()
    for d in "$ACCOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        local name
        name=$(basename "$d")
        [[ "$name" == .* ]] && continue
        is_reserved "$name" && continue
        [ -f "$d/claude.json" ] || continue
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

# ── List accounts ─────────────────────────────────────────────────────────────
cmd_list() {
    local current
    current=$(current_account)
    echo "Saved accounts:"
    local found=0
    for d in "$ACCOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        local name
        name=$(basename "$d")
        [[ "$name" == .* ]] && continue
        is_reserved "$name" && continue
        [ -f "$d/claude.json" ] || continue
        local size
        size=$(du -sh "$d" 2>/dev/null | cut -f1)
        local marker=""
        [ "$name" = "$current" ] && marker=" ◀ current"
        echo "  - $name ($size)$marker"
        found=1
    done
    [ $found -eq 0 ] && echo "  (none — run '$0 save-current <name>' to get started)"
    echo ""
    echo "Shared data: $(du -sh "$SHARED_DIR" 2>/dev/null | cut -f1) in ~/.claude-shared/"
}

# ── Status ────────────────────────────────────────────────────────────────────
cmd_status() {
    local current
    current=$(current_account)
    if [ -n "$current" ]; then
        echo "✅ Current account: $current"
    else
        echo "❓ No account saved yet (run '$0 save-current <name>')"
    fi
    echo ""
    echo "Shared items (~/.claude-shared/):"
    for item in "${SHARED_ITEMS[@]}"; do
        local link="$CLAUDE_DIR/$item"
        if [ -L "$link" ]; then
            echo "  ✓ $item"
        else
            echo "  ✗ $item (not symlinked — run '$0 setup')"
        fi
    done
    echo ""
    echo "Safety snapshots:"
    ls -dt "$SAFETY_DIR"/*/ 2>/dev/null | head -5 | while read -r d; do
        echo "  $(basename "$d") ($(du -sh "$d" | cut -f1))"
    done || echo "  (none)"
}

# ── Restore snapshot ──────────────────────────────────────────────────────────
cmd_restore_snapshot() {
    echo "Available safety snapshots:"
    ls -dt "$SAFETY_DIR"/*/ 2>/dev/null | while read -r d; do
        echo "  $(basename "$d") ($(du -sh "$d" | cut -f1))"
    done || { echo "  (none)"; exit 0; }
    echo ""
    echo "To restore ~/.claude.json from a snapshot:"
    echo "  cp $SAFETY_DIR/<snapshot>/claude.json $CLAUDE_JSON"
    echo ""
    echo "To restore backups from a snapshot:"
    echo "  cp -r $SAFETY_DIR/<snapshot>/backups $CLAUDE_DIR/backups"
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "${1:-}" in
    "setup")
        cmd_setup
        ;;
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
    "restore-snapshot")
        cmd_restore_snapshot
        ;;
    "")
        echo "Claude Code Account Switcher"
        echo ""
        echo "Usage:"
        echo "  $0 setup                   First-time setup (run once)"
        echo "  $0 save-current <name>     Save current account"
        echo "  $0 <name>                  Switch to account"
        echo "  $0 next                    Switch to next account in rotation"
        echo "  $0 list                    List saved accounts"
        echo "  $0 status                  Show current account + symlink health"
        echo "  $0 restore-snapshot        List recovery snapshots"
        echo ""
        echo "Shared across all accounts (~/.claude-shared/):"
        for item in "${SHARED_ITEMS[@]}"; do echo "  - $item"; done
        ;;
    *)
        cmd_switch "$1"
        ;;
esac
