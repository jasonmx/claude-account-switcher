# Claude Account Switcher

Two shell scripts for macOS that let you switch between multiple Anthropic accounts — useful when one account hits its 5-hour usage limit and you want to keep working.

- **`claude-desktop-switch.sh`** — switches accounts in Claude Desktop (the chat app)
- **`claude-code-switch.sh`** — switches accounts in Claude Code (VS Code extension and CLI)

Both scripts save a safety snapshot before every switch, auto-save the current account state, and support cycling through accounts with a single `next` command.

---

## claude-desktop-switch.sh

Switches the active account in Claude Desktop by swapping auth tokens, session cookies, and conversation history. Each account gets its own isolated history. **MCP server configuration (`claude_desktop_config.json`) is shared across all accounts.**

Claude Desktop is automatically quit before switching and relaunched after.

### First-time setup

```bash
chmod +x claude-desktop-switch.sh

# Quit Claude Desktop, then save your currently logged-in account
./claude-desktop-switch.sh save-current personal

# Log into your second account in Claude Desktop, quit it, then save
./claude-desktop-switch.sh save-current work
```

### Usage

```
./claude-desktop-switch.sh save-current <name>   Save current account (Claude must be quit first)
./claude-desktop-switch.sh <name>                Switch to a named account (auto-quits and relaunches)
./claude-desktop-switch.sh next                  Switch to the next account in rotation
./claude-desktop-switch.sh list                  List saved accounts
./claude-desktop-switch.sh status                Show current account and recent snapshots
```

### What gets swapped per account

- `ant-did` — account identity token
- `config.json` — OAuth token and allowlist cache
- `Cookies` / `Cookies-journal` — session cookies
- `IndexedDB/` — conversation history
- `Local Storage/` — app state
- `Session Storage/` — session data

### What is shared across all accounts

- `claude_desktop_config.json` — MCP server connections and settings

---

## claude-code-switch.sh

Switches the active account for Claude Code (used by the VS Code extensions and CLI). Auth credentials are swapped per account. Conversation history, settings, MCP config, todos, plans, and file history are **shared across all accounts** via symlinks to a `~/.claude-shared/` directory.

No restart required — just start a new Claude Code session after switching.

### First-time setup

Run `setup` once to move shared items into `~/.claude-shared/` and replace them with symlinks:

```bash
chmod +x claude-code-switch.sh

# Step 1: restructure ~/.claude to use shared directory
./claude-code-switch.sh setup

# Step 2: save your currently logged-in account
./claude-code-switch.sh save-current personal

# Step 3: log into your second account
claude /login

# Step 4: save that account
./claude-code-switch.sh save-current work
```

### Usage

```
./claude-code-switch.sh setup                    First-time setup (run once)
./claude-code-switch.sh save-current <name>      Save current account
./claude-code-switch.sh <name>                   Switch to a named account
./claude-code-switch.sh next                     Switch to the next account in rotation
./claude-code-switch.sh list                     List saved accounts
./claude-code-switch.sh status                   Show current account and symlink health
./claude-code-switch.sh restore-snapshot         List safety snapshots for manual recovery
```

### What gets swapped per account

- `~/.claude.json` — root auth file
- `~/.claude/backups/` — account-specific config backups

### What is shared across all accounts (`~/.claude-shared/`)

- `projects/` — conversation history
- `settings.json` — Claude Code settings
- `.mcp.json` — MCP server configuration
- `plugins/` — installed plugins
- `todos/` — session todos
- `plans/` — agent plans
- `session-env/` — session environment data
- `file-history/` — file edit history

---

## Safety snapshots

Both scripts take a timestamped snapshot of the current account state before every switch, keeping the last 5. If something goes wrong, use `status` or `restore-snapshot` to find and manually restore from a snapshot.

Snapshots are stored in:
- `~/.claude-desktop-accounts/.safety-snapshots/`
- `~/.claude-code-accounts/.safety-snapshots/`

---

## Adding more accounts

Both scripts support more than two accounts. The `next` command cycles through all saved accounts in alphabetical order, wrapping around at the end.

```bash
./claude-code-switch.sh save-current personal
./claude-code-switch.sh save-current work
./claude-code-switch.sh save-current client-x

./claude-code-switch.sh next   # cycles: personal → work → client-x → personal → ...
```

---

## Suggested aliases

Add to your `~/.zshrc` for convenience:

```bash
alias cds="~/path/to/claude-desktop-switch.sh"
alias ccs="~/path/to/claude-code-switch.sh"
```

Then just run `cds next` or `ccs next` to rotate accounts.

---

## Requirements

- macOS (Claude Desktop switching uses `osascript` to quit/relaunch the app)
- Claude Desktop installed at `/Applications/Claude.app`
- Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
- bash 3.2+ (ships with all macOS versions)

---

## License

MIT — see [LICENSE](LICENSE).
