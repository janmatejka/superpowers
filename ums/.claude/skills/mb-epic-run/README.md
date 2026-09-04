# mb-epic-run scripts

Three PowerShell scripts that back the `mb-epic-run` skill's pool operations
(`status`, `spawn`, `attach`, `ready`): they derive pool-slot state, launch a
Claude Code session into a slot, and provision a new slot. The skill
(`SKILL.md`) owns all decision logic and Czech rendering; these scripts are
English developer tooling (contract, "Language Contract") that the skill
shells out to.

## Scripts

| Script | Parameters | Exit codes |
|---|---|---|
| `scripts/pool-status.ps1` | `-RepoPath` (repo root; defaults to the toplevel of the current directory), `-Epic` (optional epic key; a slot holding a ticket branch of this epic is flagged, compared case-sensitively), `-Json` (optional path to also write the full state as JSON; validated before any work), `-ClaudeCommand` (test seam — harness executable used for the occupancy probe; empty resolves `claude` via `Get-Command`) | `0` OK, `1` input/script failure, `3` the repository has no pool (no linked worktree carries the `.superpowers/pool-slot` marker) |
| `scripts/pool-launch.ps1` | `-SlotPath` (mandatory), `-Prompt` (mandatory), `-Ticket` (mandatory), `-Adapter` (mandatory, `terminal` or `direct`), `-ClaudeCommand` (test seam), `-TerminalCommand` (test seam) | `0` launched, `2` unavailable, `1` failed or input error |
| `scripts/pool-provision.ps1` | `-Path` (mandatory), `-Base` (optional; defaults to the repository's configured base, else `origin/develop`), `-RepoPath` (optional; defaults to the toplevel of the current directory), `-Operator` (switch — required to bypass the agent-session guard), `-NoFetch` (switch) | `0` OK, `1` input/script failure, `4` refused by the agent-session guard, `5` the slot was provisioned but the shared pre-push guard's presence could not be confirmed |

### Test seams

`-ClaudeCommand`, `-TerminalCommand` and `-RepoPath` exist so the test suites
can point these scripts at stubs and fixtures instead of the real `claude`
executable, a real `wt.exe`, or the current working directory's real
repository. Never hardcode a path to `claude` or `wt.exe` in a caller — resolve
through `Get-Command`, or pass a test double through these parameters.

### `pool-launch.ps1` refusals

Before spawning anything, `pool-launch.ps1` refuses five prompt shapes as hard
input errors (exit `1`, nothing started, nothing to clean up):

- a **semicolon** — `wt.exe` reads it as its own command separator;
- a **double quote** — measured to be either silently dropped or to **split**
  the prompt, so the session receives only its first fragment;
- a **trailing backslash** — it escapes the quote that wraps the prompt for
  the `direct` adapter's `Start-Process` call;
- an **empty** prompt;
- a prompt **over 600 characters**.

The quote and backslash refusals were added after measurement, not by
inspection — both looked like successful launches until the session's first
input was checked. Output is always exactly one status word on its own line
(`launched` / `unavailable` / `failed`) followed by one reason line.

### `pool-status.ps1` output shape

`pool-status.ps1` always prints an English summary to stdout, and — when
`-Json` is given — writes the same state as JSON. This JSON is a contract
between the script and the `mb-epic-run` skill; the skill's `status`, `spawn`
and `attach` operations all read it. As emitted by the script today:

```jsonc
{
  "repoRoot": "<absolute path, forward slashes>",
  "generatedAt": "<UTC timestamp, yyyy-MM-ddTHH:mm:ssZ>",
  "occupancySource": "claude" | "unavailable",
  "stashCount": <int>,
  "slots": [
    {
      "name": "<directory leaf name>",
      "path": "<absolute path>",
      "branch": "<branch name>" | null,
      "detached": true | false,
      "head": "<sha>",
      "dirtyCount": <int>,
      "unpushedCount": <int>,
      "unpushedSource": "upstream" | "head-not-remotes",
      "pin": null | { "targetMb": "...", "slug": "...", "jira": "..." },
      "progress": null | { "path": "...", "exists": true|false, "lines": <int>, "lastLine": "..." },
      "session": { "state": "live" | "none" | "unknown", "pids": [<int>, ...] },
      "free": true | false,
      "reasons": ["..."]
    }
  ],
  "excluded": [
    { "path": "<absolute path>", "reason": "<why not a slot>", "branch": "<branch name>" | null }
  ],
  "stash": ["<git stash list entry>", ...]
}
```

Notes on fields that are easy to misread:

- **`dirtyCount` and `unpushedCount` of `-1` is an unreadable sentinel, not a
  count.** It means the underlying `git` call failed, and the matching reason
  string (`status unreadable` / `unpushed count unreadable`) is added to
  `reasons`. Never render `-1` as a literal count.
- **`session.state` is exactly one of `live`, `none` or `unknown`.** `unknown`
  is fail-closed: the occupancy probe (`claude agents --json --cwd <slot>`)
  was unreadable, malformed, or shaped in a way the script does not trust —
  and `unknown` must never be treated as free.
- **`excluded[].branch` was added during implementation.** It reports the
  porcelain branch name for an excluded worktree (or `null` when the worktree
  is detached, bare or prunable), so a consumer can answer "is this ticket's
  branch checked out anywhere" from the union of `slots[].branch` and
  `excluded[].branch` without ever calling `git worktree list` itself — that
  command is separately denied to the Bash tool for this skill.
- **`pin == null` means IDLE, or unreadable** — the two are told apart only by
  the string `pin unreadable (fail-closed)` appearing in that slot's
  `reasons`, because the shape carries no third pin-state field. Decide
  slot readiness from `free`, never from `pin` directly.

## Running the test suites

Each script has its own suite, plain PowerShell with hand-rolled assertions
(no Pester — see `../../../../memory-bank/playbook.md`, "Testy vrstvy"):

```bash
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-status.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-launch.tests.ps1
pwsh -NoProfile -File ums/.claude/skills/mb-epic-run/tests/pool-provision.tests.ps1
```

A green suite ends with `<N> passed` and exit code `0`; a red one prints
`<N>/<M> FAILED` and exits `1`.

## What is deliberately NOT here

No persistent slot-occupancy ledger — occupancy is a live probe, not a stored
fact. No daemon or background watcher over the pool. No new kind of baton or
session-handoff artifact beyond the existing session-intent baton. No writes
of any kind into a slot (a spawned session pulls its own briefing from the
ledger; these scripts never touch slot content beyond the marker file
`pool-provision.ps1` creates). No writes to Jira. No `vscode`, `deeplink` or
`bg` adapter for `pool-launch.ps1` — only `terminal` and `direct` are built.
