// PreToolUse guard for `git push` / `git fetch` (contract v2.2, "Publication
// Contract"). NOT the enforcement boundary — fix round 2 demoted this hook
// after two rounds of adversarial review defeated increasingly hardened
// detection: a whitespace tokenizer cannot reason about shell syntax it does
// not parse (bash -c, --git-dir, HEAD, operator adjacency, config overrides
// all resolve to the same thing only once git itself has parsed them). The
// actual guarantee is the git `pre-push` hook (ums/.claude/hooks/pre-push,
// installed per clone by install-git-hooks.ps1), which git feeds
// fully-resolved refs — no shell spelling left to bypass.
//
// This layer's only remaining job: a cheap, best-effort, FAIL-OPEN early
// warning for the common accident — a plainly-typed `git push` whose target
// is confidently recognized as a protected branch — plus one context-free
// substring check for `--no-verify` (which would skip the real guarantee).
// Everything this layer cannot parse with confidence now ALLOWS (quoted
// branch names, redirections, trailing comments, a commit message that
// happens to mention "push" must all pass); the pre-push hook remains the
// backstop for anything this early check misses or gets wrong.
import { execFileSync } from 'node:child_process';

const PROTECTED = [/^develop$/i, /^main$/i, /^master$/i, /^release\//i];

const stripRef = (ref) => String(ref).replace(/^refs\/heads\//, '');
const isProtected = (ref) => PROTECTED.some((re) => re.test(stripRef(ref)));

const sharedBranchMessage = (branch) =>
  `UMS: '${branch}' je sdílená větev — agent do ní nepushuje. Připrav příkaz a nech ho uživateli: ` +
  `\`! git push origin ${branch}\` (Publication Contract, dvouúrovňová push policy).`;

const currentBranch = (cwd) => {
  try {
    return execFileSync('git', ['branch', '--show-current'],
      { cwd: cwd || process.cwd(), encoding: 'utf8' }).trim();
  } catch { return ''; }
};

const deny = (reason) => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
};

// Shell control-flow tokens that end the current invocation's argument list.
const CONTROL = new Set(['&&', '||', ';', '|', '&']);

// Flags considered "boring" enough that we still trust our own read of the
// remote/refspec around them. Any other flag means "not simple" -> allow.
const PUSH_ALLOWED_FLAGS = new Set([
  '-u', '--set-upstream', '-q', '--quiet', '-v', '--verbose',
  '--progress', '--no-progress',
]);
const REMOTE_RE = /^[A-Za-z0-9._-]+$/;
const REFSPEC_RE = /^[A-Za-z0-9._/-]+(:[A-Za-z0-9._/-]+)?$/;

// A token is a git invocation start if, after stripping a leading subshell
// or backtick marker, it is exactly `git`/`git.exe` or ends in `/git`.
const isGitToken = (tok) => {
  const t = tok.replace(/^(\$\(|\(|`)/, '');
  return t === 'git' || t === 'git.exe' || /\/git$/.test(t);
};

// Best-effort, FAIL-OPEN: only denies when the target is confidently
// resolved to a protected branch. Anything not cleanly parseable (unknown
// flag, non-plain remote, multiple/malformed refspecs, unresolvable current
// branch) now ALLOWS — the pre-push hook is the real check, and it resolves
// the current branch itself from the actual push, not from a guessed cwd.
function evaluatePush(args, cwd) {
  const flags = args.filter((t) => t.startsWith('-'));
  const positionals = args.filter((t) => !t.startsWith('-'));

  if (flags.some((f) => !PUSH_ALLOWED_FLAGS.has(f))) return { deny: false };

  let target = null;
  if (positionals.length === 0) {
    target = currentBranch(cwd) || null;
  } else {
    const [remote, ...refspecs] = positionals;
    if (!REMOTE_RE.test(remote)) return { deny: false };
    if (refspecs.length === 0) {
      target = currentBranch(cwd) || null;
    } else if (refspecs.length === 1 && REFSPEC_RE.test(refspecs[0])) {
      target = refspecs[0].includes(':') ? refspecs[0].split(':').pop() : refspecs[0];
    } else {
      return { deny: false }; // multiple / malformed refspecs -> not simple
    }
  }

  if (target && isProtected(target)) {
    return { deny: true, reason: sharedBranchMessage(stripRef(target)) };
  }
  return { deny: false };
}

// Fetch stays best-effort on the same footing as before: only denies an
// explicit refspec whose destination is a protected local ref; everything
// else passes (fetch is frequent and normally harmless).
function evaluateFetch(args) {
  for (const t of args) {
    if (t.startsWith('-') || !t.includes(':')) continue;
    const dst = t.split(':').pop();
    if (dst && isProtected(dst)) {
      return {
        deny: true,
        reason: `UMS: '${stripRef(dst)}' je sdílená větev — tenhle fetch by přepsal její lokální ref, agent to ` +
          'nesmí udělat (Publication Contract, dvouúrovňová push policy).',
      };
    }
  }
  return { deny: false };
}

let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch { process.exit(0); }
  const command = String(input?.tool_input?.command ?? '');
  const cwd = input?.cwd;

  // Context-free substring check: `--no-verify` next to `push` (in a command
  // that also mentions `git`, so e.g. `npm run push -- --no-verify` does not
  // trigger this) would skip the real guarantee (the pre-push hook). A false
  // positive here costs nothing, so it deliberately is not tied to a
  // specific parsed invocation. The remaining edge — a commit message that
  // happens to contain both words — is accepted as out of scope.
  if (/\bgit\b/.test(command) && /\bpush\b/.test(command) && /--no-verify\b/.test(command)) {
    deny(
      'UMS: `--no-verify` by u pushe přeskočil pre-push hook (skutečnou pojistku Publication Contract, ' +
        'ne jen tuhle předběžnou kontrolu) — nepoužívej ho bez výslovného souhlasu uživatele.',
    );
  }

  const tokens = command.split(/\s+/).filter(Boolean);
  let i = 0;
  while (i < tokens.length) {
    if (!isGitToken(tokens[i])) { i++; continue; }
    i++; // past the `git` token itself

    // Consume pre-subcommand options: `-C <path>` / `-c <k=v>` (two-token
    // form) skip both tokens; any attached form or other global flag skips
    // just the one token it occupies.
    while (i < tokens.length && tokens[i].startsWith('-')) {
      i += (tokens[i] === '-C' || tokens[i] === '-c') ? 2 : 1;
    }
    if (i >= tokens.length) break; // no subcommand found
    const subcommand = tokens[i];
    i++;

    // Collect this invocation's own argument tokens: stop at a shell
    // control operator, or at the start of another git invocation.
    const args = [];
    while (i < tokens.length && !CONTROL.has(tokens[i]) && !isGitToken(tokens[i])) {
      args.push(tokens[i]);
      i++;
    }

    if (subcommand === 'push') {
      const r = evaluatePush(args, cwd);
      if (r.deny) deny(r.reason);
    } else if (subcommand === 'fetch') {
      const r = evaluateFetch(args);
      if (r.deny) deny(r.reason);
    }
    // any other subcommand: not this hook's concern, keep scanning
  }
  process.exit(0);
});
