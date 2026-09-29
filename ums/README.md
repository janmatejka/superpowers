# UMS Memory Bank integration layer

This directory carries the **UMS Memory Bank v2** integration layer for the
UMS monorepo (`d:\_datasys\ums`, Bitbucket `datasyscz/ums`). It lives only on
the `ums-memory-bank` branch of this fork; `main` stays a clean mirror of
upstream `obra/superpowers`.

**Model:** vendored superpowers skills (upstream **v6.4.2**) drive the workflow
(`brainstorming → writing-plans → subagent-driven-development →
finishing-a-development-branch`, with `executing-plans` as the Native executor
of the same plan in place of subagent-driven-development); the Memory Bank is the document/knowledge
layer injected into it. Between brainstorming and writing-plans sits an
optional Architect Review Gate (`mb-architect-review`, request/resume) for
non-trivial designs with a linked Jira ticket — while it is pending,
writing-plans does not start. The normative rules are in
[`.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`](.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md)
(contract 3.2).

## Contract: core, references, evidence — and how the core reaches a session

As of contract **3.0** the rules are no longer one 3 066-line document. They are:

- **The core**, `.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — everything
  every session needs regardless of what it is doing: the directory model, the
  document set, the design+plan pair and its granularity, session eligibility,
  the Publication Contract, the Message Protocol, escalation and fail-closed
  behaviour, plus a `Phase Map` saying which reference owns which operation. Its
  size is budgeted and the budget is enforced by
  `.claude/skills/shared/tests/contract-shape.tests.ps1`.
- **17 references**, `.claude/skills/shared/contract/*.md` — one per topic, read
  on demand by the skill or overlay that owns the operation (the `Phase Map`
  names the owner). Cited as `` (contract/<file>.md, "Section") ``; a rule of
  the core is cited as `` (contract, "Section") ``. Both forms are checked
  mechanically against the heading index, so a citation cannot point at a
  section that does not exist.
- **The evidence tier**, `.claude/skills/shared/contract/doklad/*.md` — the
  measurements, rejected alternatives and reasons behind the rules. Read on
  demand, never cited as normative: it settles no question the contract does not
  settle itself. A `Doklad:` line in the core or a reference points into it.

The version lives in the core's `Contract-Version` line only; the per-version
history is [`shared/CHANGELOG.md`](.claude/skills/shared/CHANGELOG.md).

**The core reaches a session through a hook, not through a reading habit.**
`.claude/hooks/contract-inject.ps1` is registered in `settings.json` and injects
the core as `additionalContext` at session start and again with the first prompt
after a compaction (it tracks that with the marker file
`.superpowers/contract-reload.flag`). A harness with no session-start injection
falls back to the instructions-file rule in `CLAUDE.md.sample` — the layer's
harness compatibility matrix below says which is which.

## Layout

```
ums/
├── README.md                 ← this file
├── CLAUDE.md.sample          ← monorepo root CLAUDE.md (user-preference lever)
├── .gitattributes             ← forces LF on the extensionless pre-push hook (Windows CRLF trap)
├── sync-with-monorepo.ps1    ← deploys this layer (the fork is master) into the monorepo, a user profile or the fork's own root, for 15 harnesses (-Agent)
├── docs/
│   └── pool-rozjeti-tiketu.md  ← Czech operator guide for the pool (mb-epic-run)
└── .claude/
    ├── settings.json         ← Claude Code glue (hooks, permission denies, skillOverrides)
    ├── hooks/
    │   ├── deny-superpowers-docs.mjs  ← PreToolUse write-guard (Claude Code)
    │   ├── guard-git-push.mjs         ← PreToolUse best-effort push warning (Claude Code; NOT the guarantee)
    │   ├── pre-push                   ← git pre-push hook — the actual Publication Contract enforcement
    │   │                                 boundary (plain git, so it runs in every harness; its fail-closed
    │   │                                 stdin-buffer arm always applies, but the rest of its own checks
    │   │                                 only activate once the agent-session marker reaches it)
    │   ├── install-git-hooks.ps1      ← installs pre-push per clone (git hooks are untracked; required — see below)
    │   ├── session-intent.ps1         ← SessionStart hook — delivers the session intent baton
    │   ├── contract-inject.ps1        ← SessionStart/PostCompact hook — injects the contract CORE as context
    │   └── tests/                     ← own Pester-free *.tests.ps1 + _assert.ps1 per this layer's convention
    ├── scripts/revendor-superpowers.ps1  ← vendors skills/ of THIS repo into the monorepo
    └── skills/
        ├── shared/           ← contract 3.2 core + contract/ references + contract/doklad/ evidence,
        │                       CHANGELOG.md, manifest, VENDORED_FROM.md, scripts/, tests/,
        │                       overlays/*.overlay.md
        ├── mb-epic-run/      ← pool status/launch/provision (see its own README.md)
        │   ├── SKILL.md
        │   ├── scripts/      ← pool-status.ps1, pool-launch.ps1, pool-provision.ps1
        │   └── tests/        ← pool-status.tests.ps1, pool-launch.tests.ps1, pool-provision.tests.ps1
        ├── mb-harvest/ …     ← active mb-* utility skills
        └── mb-plan/ …        ← deprecated v1 stubs (transitional)
```

**The push-policy guarantee requires a per-clone install step.** Vendoring
`hooks/pre-push` under `.claude/` is not enough by itself — git only runs
hooks from its own hooks directory (`.git/hooks/`, a linked worktree's common
dir, or a `core.hooksPath` override), which is untracked and never populated
by cloning or by the sync script's normal file deploy. Run
`pwsh ums/.claude/hooks/install-git-hooks.ps1 -RepoRoot <repo>` once per
clone (idempotent; never overwrites a foreign `pre-push`); `sync-with-
monorepo.ps1` already calls it automatically whenever `-Scope Monorepo` or
`-Scope Fork` is used, for any `-Agent`, since a git hook is a property of the
repository, not of the harness (`-Scope UserProfile` has no single repository —
install it per clone). See `UMS_MEMORY_BANK_CONTRACT.md`, "Publication
Contract", for the full enforcement/bypass model.

**One run does not always cover every worktree.** Without `core.hooksPath`,
hooks live in the repository's common dir and one install covers all its
linked worktrees. But a **relative** `core.hooksPath` (e.g. `customhooks`) is
resolved per working tree, so installing against the main clone leaves every
linked worktree inert — run the installer once per worktree in that setup
(it prints a warning naming this case). A `core.hooksPath` coming from
**global** config makes the install per-user rather than per-repository —
also reported in the installer's output. The installer exits non-zero
whenever the guarantee is not CONFIRMED, and the code says which of the two
that is: `1` (proof failed) and `2` (foreign hook left alone) mean the
guarantee is **absent**, while `3` means the hook was installed but is
**unproven** — no shell was available to run the self-check, so its output
prints the two commands to run by hand. A script calling it can therefore
tell "installed and proven" from "absent" and from "unverified";
`sync-with-monorepo.ps1` checks that and warns.

## Vendored skills and overlays

The **14 vendored superpowers skill copies** (upstream v6.4.2, pinned in
[`shared/VENDORED_FROM.md`](.claude/skills/shared/VENDORED_FROM.md)) are **not**
stored here — `sync-with-monorepo.ps1` produces them in every deployment target
by running `revendor-superpowers.ps1` against this repo's `skills/` tree, then
patches them with the `shared/overlays/*.overlay.md` fragments (marked
`<!-- UMS-OVERLAY BEGIN/END -->`). The pin lists the skills and an explicit
`Excluded:` list; the revendor vendors every upstream skill that is in neither,
and STOPS on a new upstream skill it has no decision about.

**Excluded: `diagnosing-superpowers`.** It reads session transcripts and, after
the user approves, files issues or archives on GitHub (`obra/superpowers`) — in
a proprietary monorepo that is a channel for leaking code, and it would report
to upstream behaviour the UMS overlay deliberately shapes.

**Five overlays**, one per skill whose behaviour the document layer changes:
`brainstorming`, `subagent-driven-development`, `finishing-a-development-branch`,
`writing-plans` and `executing-plans`. Every overlaid skill carries a second,
short block — the header pointer (`*.pointer.overlay.md`) — in the first 12 000
characters of the file. The reason: after a compaction Claude Code re-injects an
invoked skill body truncated at 5,000 tokens, and the truncation keeps the START
of the file, so a rule that lives only in the overlay body at the end of a long
skill is lost; the pointer at the top survives and names what to re-read
(measurement: `.claude/skills/shared/contract/doklad/compaction.md`). The other
nine vendored skills are byte-identical to upstream.

**Do not install superpowers as a plugin in a UMS target at the same time.** The
skills would then exist twice — the plugin's copy without the overlay, next to
the layer's copy with it — and the agent may pick the unpatched one. The layer's
vendored copies are the superpowers of a UMS target.

## Upstream merge strategy (the whole point of this branch)

Everything UMS-specific is **additive** under `ums/` — no file outside this
directory is modified on this branch, with the exceptions that add only files
upstream does not have: the fork's own `CLAUDE.md` (upstream deleted its own so
that Claude Code reads `AGENTS.md`; the fork's first line `@AGENTS.md` imports
it) and the fork's `memory-bank/`. Upstream therefore always merges clean:

```bash
git fetch vanila --tags
git merge vanila/main          # never conflicts (upstream has no ums/)
```

After merging a new upstream release, bump the pin in the fork and deploy. The
**fork is the master copy** of the layer; the sync script deploys from it, and
the vendoring is one of its steps:

```powershell
# in this fork: bump the pin (Tag, Commit, Skills, Excluded) and commit it
pwsh ums/.claude/scripts/revendor-superpowers.ps1 -UmsRoot ums -PinOnly -Tag <new-tag>
# deploy; a tag change on a git-tracked target (the monorepo) is TWO runs:
pwsh ums/sync-with-monorepo.ps1     # 1st run: vanilla phase only, exit 4 -> commit "vanilla sync" in the target
pwsh ums/sync-with-monorepo.ps1     # 2nd run: mirrors the layer, applies the overlays -> commit "overlay"
```

An `ANCHOR-BEFORE` miss during overlay application is the upstream-drift
detector — it enumerates exactly the fragments needing attention. Fix the
fragment in `ums/.claude/skills/shared/overlays/` here, run the sync again.

**Rules that keep merges trivial:**

1. Never modify files outside `ums/` on this branch (beyond the two fork-own
   files above). Improvements meant for upstream go to `main`/PRs against
   `obra/superpowers` instead.
2. Never hand-edit vendored files in a target outside `UMS-OVERLAY` blocks;
   change the fragment and re-run the sync. A hand edit is caught as drift.
3. This fork is the master copy of the layer. A change made in the monorepo
   is pulled back deliberately — `pwsh ums/sync-with-monorepo.ps1 -Direction
   FromMonorepo` (only for `-Agent claude -Scope Monorepo`, and it never pulls
   the vendored skills) — reviewed and committed here.

## Harness compatibility

The superpowers architecture keeps skill content identical across harnesses —
only the bootstrap and tool mapping differ (`docs/porting-to-a-new-harness.md`).
The UMS layer follows the same split:

**Portable (any harness that loads skills):** the contract, the mb-* skills,
the overlay fragments, and the work-item (design+plan pair) document
conventions are plain markdown — they work wherever superpowers skills load (Claude Code, Codex
native discovery, Cursor, Copilot CLI, Kimi, OpenCode, pi, Devin CLI, Hermes Agent). The mb-* skills
use only git + filesystem + markdown; `mb-jira-update` needs an Atlassian MCP
connection configured per harness. `mb-epic-run` and the contract text it
follows are plain Markdown plus `pwsh` scripts and carry over the same way —
except its occupancy probe, which is Claude Code-specific (see the table
below).

**Claude Code-specific glue (`.claude/settings.json` + `hooks/`):**

| Mechanism | Claude Code | Other harnesses |
|---|---|---|
| Contract/context injection at session start | SessionStart + PostCompact hooks (`additionalContext`) | Cursor: `hooks-cursor.json` `sessionStart` (schema differs); Codex: no session-start injection — put the "load the contract" rule into the instructions file (`AGENTS.md`); Kimi: manifest `sessionStart`; OpenCode/pi: in-process injection |
| Write-guard for `docs/superpowers/**`, `docs/plans/**` | PreToolUse hook with `permissionDecision: deny` (`deny-superpowers-docs.mjs`) | No shown equivalent — degrade to the contract's Document Placement rule + CLAUDE.md/AGENTS.md preference text (upstream skills honor declared location preferences) |
| Actor rule (the moment of integration belongs to a human) + push-policy early warning — NOT the publication guarantee | PreToolUse hook (`guard-git-push.mjs`) — leans **fail-closed** on what it recognizes as a `git push`: an invocation it cannot read with confidence is denied rather than waved through. It denies an agent's own push to a protected branch **including the integration fast-forward the `pre-push` hook would accept**, the skip-hooks flag, commands carrying the human escape (`MB_HUMAN_PUSH`/`UMS_ALLOW_SHARED_PUSH`, in POSIX-shell or PowerShell spelling — an agent never sets it), wildcard fetches into protected refs, and unreadable invocations. It is no guarantee, because what it does not recognize as a `git push` at all passes through by design (`bash -c '…'`; a git alias standing in for the `push` subcommand) — the `pre-push` hook is the boundary. It has **no epic-line exception**: the epic line `epic/<KEY>` is an unprotected integration base (contract/epic-line.md), so a push to it is judged like a push to any unprotected branch — after the manager's `go` (`mb-epic-run integrate`) the ticket session fast-forwards the line itself, and `pre-push` still bans force-push and branch deletion there | No shown equivalent for the early warning or the actor rule — an agent on any other harness can run the integration fast-forward itself |
| Publication guarantee (`hooks/pre-push`, a plain git hook — see the per-clone install note above) | Marker (`MB_AGENT_SESSION`) reaches it via the `env` block of this layer's own `settings.json`; `sync-with-monorepo.ps1` never calls `Set-AgentMarker` for `-Agent claude` because that file already carries it — except under `-Scope UserProfile`, which deliberately does not deploy `settings.json`, leaving Claude Code on the `CLAUDECODE=1`/non-empty `AI_AGENT` fallback; one arm — the ref-list buffer check — sits above the marker gate and rejects the whole push, tags included, for everyone regardless of the marker | Per harness, see the matrix below: Codex `config.toml [shell_environment_policy].set`; Gemini and Qwen a `.env` file in `.gemini/` / `.qwen/`; OpenCode a plugin with a `shell.env` hook; Hermes `terminal.env_passthrough` (profile only); Pi needs nothing — its CLI sets `AI_AGENT=pi`, which the hook accepts. **Cursor, Copilot CLI, Devin, Droid, Kimi, Muse, Antigravity and Grok have no documented mechanism to set it**, so the marker never arrives, the gate never opens, and the hook enforces NOTHING there — the sync prints the named warning "the pre-push guarantee does not bind '<agent>'" |
| Worktree ban | `permissions.deny: EnterWorktree/ExitWorktree` + `Bash(git worktree:*)` + `PowerShell(git worktree:*)` + `skillOverrides: using-git-worktrees: off` | No shown equivalent — degrade to the ban text in the instructions file; `using-git-worktrees` itself honors a declared preference ("work in place") |
| Model selection for subagents | Owned by superpowers (SDD Model Selection); UMS only adds the cheapest-tier guard for summarization/read-only dispatches (contract, Dispatch Model Policy) | Portable text; the cheapest-tier guard is effective only where the harness exposes a model parameter on subagent dispatch |
| Session intent baton delivery | `SessionStart` hook (`session-intent.ps1`) with a `clear\|startup` matcher; the writer precondition checks for it before writing a baton | No equivalent — the writer's precondition fails, so no baton is written and the operator types the intent, which is the pre-baton behaviour |
| Pool slot occupancy probe (`mb-epic-run`, `pool-status.ps1`) | Native — reads `claude agents --json --cwd <slot>` directly | `claude agents --json` is bound to Claude Code, so on another harness **slot occupancy is not available** and it degrades **fail-closed**: `pool-status.ps1` reports `session.state: unknown` for the slot, `mb-epic-run` treats `unknown` as not free, and a spawn happens only on the operator's explicit instruction, never on the skill's own judgement. The agent-session guard in `pool-provision.ps1` (refuses to run under an agent-session marker without `-Operator`) travels with the script itself and enforces there on any harness; `permissions.deny`'s `EnterWorktree`/`ExitWorktree`/`Bash(git worktree:*)`/`PowerShell(git worktree:*)` denial (the Worktree ban row above) and its `Bash(pool-provision.ps1:*)`/`PowerShell(pool-provision.ps1:*)` denial carry the same "provisioning/entering a worktree is not the agent's call" spirit for Claude Code specifically — provisioning is blocked mechanically there, not just in the script's own prose — but both are Claude Code configuration and do not travel |

## Deploying the layer: `sync-with-monorepo.ps1`

**The fork is the master copy.** The default `-Direction ToMonorepo` deploys
fork → target for every scope; `-Direction FromMonorepo` is the deliberate pull
of monorepo changes back into the fork and exists only for `-Agent claude
-Scope Monorepo` (it never pulls the vendored skills). Run bare in an
interactive console the script asks for agent(s), scope and direction (Enter =
default); in a non-interactive process the defaults apply silently (`claude`,
`Monorepo`, `ToMonorepo`).

```powershell
pwsh ums/sync-with-monorepo.ps1                              # interactive
pwsh ums/sync-with-monorepo.ps1 -Agent claude,codex          # one or more of the 15 harnesses, comma-separated
pwsh ums/sync-with-monorepo.ps1 -Scope UserProfile           # into ~/ instead of the monorepo
pwsh ums/sync-with-monorepo.ps1 -Scope Fork                  # into this fork's own root (see below)
pwsh ums/sync-with-monorepo.ps1 -WhatIf                      # print what would be written and the drift, write nothing
```

| Parameter | Values | Default |
|---|---|---|
| `-Direction` | `ToMonorepo`, `FromMonorepo` | `ToMonorepo` |
| `-Agent` | list of the 15 harnesses in the matrix below | `claude` |
| `-Scope` | `Monorepo`, `UserProfile`, `Fork` | `Monorepo` |
| `-WhatIf` | switch | off |
| `-Force` | switch — deploy over drift | off |
| `-MonorepoRoot` | clone of the monorepo | `$env:UMS_SYNC_MONOREPO_ROOT`, else `D:\_datasys\ums` |
| `-UserProfileRoot` | root for `-Scope UserProfile` | `$HOME` |

**What one run writes, per target.** The UMS items (`skills/shared`, every
`skills/mb-*`); for `claude` in `Monorepo`/`Fork` scope also `settings.json`,
`hooks/*` and `scripts/revendor-superpowers.ps1`, for every other harness the
glue directories (`hooks/`, `scripts/`) merged file by file into its config
directory, never deleting anything there (`settings.json` is deliberately NOT
deployed to a non-Claude harness — it is Claude Code's registration format and
would clobber e.g. `.gemini/settings.json`; hook wiring is manual there); the
vendored superpowers skills (the fork's revendor runs against the target's
skills directory with the fork's pin and the overlay fragments just mirrored
there); the `CLAUDE.md.sample` preference block into the harness's instructions
file between `UMS-MEMORY-BANK BEGIN/END` markers (re-runs replace the block in
place; `UserProfile` prepends a scoping line); the agent-session marker
(`MB_AGENT_SESSION`) through the harness's documented mechanism; the `pre-push`
git hook; and a **drift manifest**. A target shared by several harnesses (a
skills directory, an instructions file) is written once per run.

**Drift protection.** After every successful run the manifest records the
target's post-deploy SHA-256 of what the run owns (per agent and scope; in the
target's git directory, so per worktree — outside git in the target root). Before
writing, target, manifest and fork are compared: a file changed in the target
since the last deployment whose change the fork does not have stops the run
(exit 3) with the file list; resolve it with `-Direction FromMonorepo` (claude +
Monorepo) or overwrite deliberately with `-Force`. A first run without a
manifest stops on every difference. A hand edit of a vendored skill is caught
the same way; an `mb-*` directory present only in the target is a warning.

**A tag change on a git-tracked target is two runs.** The first run does only
the vanilla phase (the new upstream tag without overlays, nothing else) and
exits 4: commit it in the target as "vanilla sync", run again, and the second
run mirrors the layer and applies the overlays: commit "overlay". A target with
the same tag, or one not tracked by git, is deployed in one pass.

**Exit codes:** `0` done; `1` error (read the output — nothing or part was
written); `3` drift STOP (nothing written); `4` vanilla phase done (commit and
run again); `5` deployed, but a per-agent step failed (marker writer error,
`pre-push` not confirmed) — the summary names it.

**`-Scope Fork` deploys the layer into this fork's own root** (the git
toplevel), which replaces refreshing the working copy by hand: `claude` gets
`.claude/` (settings, hooks, scripts, shared, `mb-*`, the vendored skills), the
other harnesses their skills directory only. It writes **no instructions file**
(the fork's `CLAUDE.md` is maintained by hand, `AGENTS.md` is an upstream file)
and no agent-session marker, installs `pre-push`, and adds every deployed
directory that git does not already ignore to `.git/info/exclude` (never to
`.gitignore`), so `git status` stays clean.

### Harness matrix

The single table is `Get-UmsSyncTargets` (paths relative to the project root —
the monorepo or the fork — and, for `-Scope UserProfile`, to `$HOME`); the marker
mechanisms are `Set-AgentMarker`. "Guarantee" says whether the `pre-push` hook
can recognise an agent session there.

| Harness | Skills (project / profile) | Instructions file (project / profile) | Marker `MB_AGENT_SESSION` | Pre-push guarantee binds |
|---|---|---|---|---|
| `claude` | `.claude/skills` / `.claude/skills` | `CLAUDE.md` / `.claude/CLAUDE.md` | `settings.json` `env` block (project); the hook's `CLAUDECODE=1` fallback | yes |
| `codex` | `.agents/skills` / `.agents/skills` | `AGENTS.md` / `.codex/AGENTS.md` | `.codex/config.toml` `[shell_environment_policy]` `set` | yes |
| `gemini` | `.agents/skills` / `.agents/skills` | `GEMINI.md` / `.gemini/GEMINI.md` | `.gemini/.env` | yes |
| `qwen` | `.qwen/skills` / `.qwen/skills` | `QWEN.md` / `.qwen/QWEN.md` | `.qwen/.env` (only the first `.env` Qwen finds is read) | yes |
| `opencode` | `.agents/skills` / `.agents/skills` | `AGENTS.md` / `.config/opencode/AGENTS.md` | plugin `plugins/ums-agent-session.js` with a `shell.env` hook | yes |
| `pi` | `.agents/skills` / `.agents/skills` | `AGENTS.md` / `.pi/agent/AGENTS.md` | none written — Pi's CLI sets `AI_AGENT=pi` (not when Pi is embedded via its SDK) | yes, via the `AI_AGENT` fallback |
| `hermes` | `.agents/skills` / `.hermes/skills` | `.hermes.md` / — | profile only: `terminal.env_passthrough` in `config.yaml` plus `.hermes/.env` | profile: yes; project: **no** (no project-level config) |
| `cursor`, `devin`, `droid`, `kimi`, `muse` | `.agents/skills` / `.agents/skills` | `AGENTS.md` / — | no documented mechanism | **no** — named warning |
| `copilot` | `.agents/skills` / `.agents/skills` | `.github/copilot-instructions.md` / — | no documented mechanism | **no** — named warning |
| `antigravity` | `.agents/skills` / `.gemini/antigravity-cli/skills` | `AGENTS.md` / — | no documented mechanism | **no** — named warning |
| `grok` | `.grok/skills` / `.grok/skills` | `AGENTS.md` / — | no documented mechanism | **no** — named warning |

`kilocode` is no longer a target (upstream superpowers does not support it) and
the sync rejects it by name. Where the guarantee does not bind, the sync prints
"the pre-push guarantee does not bind '<agent>'": the hook recognises an agent
session there only if `MB_AGENT_SESSION` or `AI_AGENT` is set by other means. A
`—` instructions file means the layer writes no preference block there. Most
monorepo-side targets are gitignored, i.e. local per-developer deploys. Every
marker mechanism and path was checked against the harness's own documentation
when it was written; a mechanism that could not be documented is reported, not
guessed. Per-scope target paths live in `Get-UmsSyncTargets` at the top of the
script — adjust there if a harness expects a different layout.

**User-profile install:** `-Scope UserProfile` installs into the current user's
profile (e.g. `~/.claude/skills/`, `~/.codex/AGENTS.md`) — always a one-way
deploy, for `claude` too. The preference block gets a scoping preamble so the
rules apply only when working in the UMS monorepo; the user's own hooks and
instructions files are preserved (merge/append semantics). It installs no git
hook — run `install-git-hooks.ps1 -RepoRoot <repo>` per clone.

## Deployment to the monorepo from scratch

1. Preview: `pwsh ums/sync-with-monorepo.ps1 -WhatIf` lists what would be
   written and any drift; nothing is changed.
2. Deploy: `pwsh ums/sync-with-monorepo.ps1` (`-Direction ToMonorepo` is the
   default). One run copies this layer, vendors the skills of the fork's pin,
   applies the overlays and writes the `CLAUDE.md` block — a target that does
   have a pin yet, or is not tracked by git, gets everything in one pass; a
   git-tracked target that pins another tag needs the two runs described above.
3. Verify: the revendor's verification pass, whose output the sync relays, must
   end with `Verification passed.`; the run's last line names the direction,
   scope, agents and target.
