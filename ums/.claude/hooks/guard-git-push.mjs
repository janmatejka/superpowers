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
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const BUILTIN_PROTECTED = ['develop', 'main', 'master', 'release/*'];

// Glob -> anchored, case-insensitive regex. Only `*` is a wildcard here; every
// other regex metacharacter is escaped, so a pattern like `release/*` cannot
// accidentally mean something else.
const globToRe = (glob) =>
  new RegExp('^' + String(glob).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\\\*/g, '.*') + '$', 'i');

// Same source of truth as the pre-push hook, read directly (this is Node, a
// JSON parser is available). A missing, malformed, or non-object-shaped file
// falls back to the built-in list: degradation must lead to MORE protection,
// never less.
//
// The array is filtered to USABLE entries (non-empty-after-trim strings)
// BEFORE the length test, not after. An array can be non-empty while
// containing nothing usable — [1, null, ["x"], {}] passes `Array.isArray &&
// length > 0` but every element stringifies into a useless pattern (`1`,
// `null`, `x`, `[object Object]`), so a config that names no real branch
// silently replaces the built-in list instead of falling back to it: a
// fork-round finding, same trap as task 3's PowerShell loader in a different
// shape. Filtering first means "nothing usable remains" degrades exactly
// like "the key is absent".
//
// A BARE STRING is normalized to a single-element list, exactly as the
// PowerShell loader's @() wrapping does. Without this, `"protectedBranches":
// "Branches/*"` made the two enforcement layers disagree: the loader accepted
// it and the installer baked it into the generated list, so `pre-push`
// REJECTED a push to `Branches/5.37`, while this file required Array.isArray,
// fell back to the built-in four and ALLOWED the very same push. Reproduced
// empirically. No protection was lost — the stricter layer is the real
// boundary — but the layers must give the same answer for the same config
// (see the pre-push hook's own comment on that invariant), so the shape is
// normalized here rather than rejected.
const loadProtected = (cwd) => {
  try {
    const raw = readFileSync(join(cwd || process.cwd(), 'memory-bank', 'ums-repo.json'), 'utf8');
    const parsed = JSON.parse(raw);
    const value = parsed && typeof parsed === 'object' ? parsed.protectedBranches : undefined;
    const list = typeof value === 'string' ? [value] : value;
    if (Array.isArray(list)) {
      const usable = list.filter((v) => typeof v === 'string' && v.trim() !== '');
      if (usable.length > 0) return usable.map(globToRe);
    }
  } catch { /* missing or malformed -> built-in list below */ }
  return BUILTIN_PROTECTED.map(globToRe);
};

const stripRef = (ref) => String(ref).replace(/^refs\/heads\//, '');
const isProtected = (ref, patterns) => patterns.some((re) => re.test(stripRef(ref)));

const sharedBranchMessage = (branch) =>
  `UMS: '${branch}' je sdílená větev — agent do ní nepushuje. Připrav příkaz a nech ho uživateli: ` +
  `\`! UMS_ALLOW_SHARED_PUSH=1 git push origin HEAD:${branch}\` — UMS_ALLOW_SHARED_PUSH=1 je vědomá výjimka ` +
  'pro člověka, agent ji nikdy nenastavuje (Publication Contract, dvouúrovňová push policy).';

// The human escape honoured by the pre-push hook (the real boundary). A
// command carrying it is a deliberate human publication, so this early
// warning must not stand in front of it — otherwise the layer would hand the
// user a command its own guard then refuses, which is the deadlock this
// escape exists to break. Checked AFTER the --no-verify rule below: the
// escape lifts one rule, it is not a licence to disable every hook.
const HUMAN_ESCAPE_RE = /(^|\s)UMS_ALLOW_SHARED_PUSH=1(\s|$)/;

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
function evaluatePush(args, cwd, patterns) {
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

  if (target && isProtected(target, patterns)) {
    return { deny: true, reason: sharedBranchMessage(stripRef(target)) };
  }
  return { deny: false };
}

// A WILDCARD destination names no single branch, so isProtected() never
// matches it — yet `+refs/heads/*:refs/heads/*` overwrites every local
// branch, protected ones included. Only LOCAL-BRANCH destinations count
// here: the everyday `+refs/heads/*:refs/remotes/origin/*` refspec writes
// remote-tracking refs and must keep passing.
const isWildcardLocalBranch = (ref) => {
  const s = String(ref);
  if (!s.includes('*')) return false;
  return s.startsWith('refs/heads/') || !s.startsWith('refs/');
};

// Fetch stays best-effort on the same footing as before: only denies an
// explicit refspec whose destination is a protected local ref; everything
// else passes (fetch is frequent and normally harmless).
function evaluateFetch(args, patterns) {
  for (const t of args) {
    if (t.startsWith('-') || !t.includes(':')) continue;
    const dst = t.split(':').pop();
    if (!dst) continue;
    if (isWildcardLocalBranch(dst)) {
      return {
        deny: true,
        // Deliberately does not say WHERE the protected list came from
        // (config file vs. built-in fallback) — the wording must stay true
        // in both states, not just the common one.
        reason: `UMS: refspec '${t}' míří žolíkem na lokální větve — přepsal by i chráněné větve tohoto ` +
          'repozitáře, agent to nesmí udělat (Publication Contract, dvouúrovňová push policy).',
      };
    }
    if (isProtected(dst, patterns)) {
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
  // Loaded ONCE for this invocation, before any scanning below — not per
  // call. A stale call site passing the old (patterns-less) signature would
  // silently receive `undefined` and match nothing, i.e. a guard that never
  // guards.
  const patterns = loadProtected(cwd);

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

  // Deliberate human publication of a shared branch (see HUMAN_ESCAPE_RE):
  // allow the whole command. The pre-push hook — the actual boundary —
  // honours the same variable and still enforces everything the escape does
  // not lift (deletion, force push).
  if (HUMAN_ESCAPE_RE.test(command)) process.exit(0);

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
      const r = evaluatePush(args, cwd, patterns);
      if (r.deny) deny(r.reason);
    } else if (subcommand === 'fetch') {
      const r = evaluateFetch(args, patterns);
      if (r.deny) deny(r.reason);
    }
    // any other subcommand: not this hook's concern, keep scanning
  }
  process.exit(0);
});
