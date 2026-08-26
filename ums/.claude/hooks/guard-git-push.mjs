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
// What this layer DOES carry is the ACTOR rule: the moment of integration
// belongs to a human. Only the agent's own tool calls reach a PreToolUse
// hook — a command the user types with a leading `!` never does — so a `git
// push` arriving here is by definition the agent's, and a protected branch is
// off limits to it even as the fast-forward the pre-push hook would happily
// accept. For the same reason a command carrying the human escape
// (HUMAN_ESCAPE_RE) is denied here: an agent never writes it.
//
// A RECOGNIZED `git push` is therefore FAIL-CLOSED: whatever this file cannot
// read with confidence as harmless (unknown flag, non-plain remote, multiple
// or malformed refspecs) is denied rather than waved through. Everything else
// keeps the old FAIL-OPEN posture on purpose — the context-free `--no-verify`
// check, `git fetch`, every other subcommand, an unresolvable current branch
// (which names no protected target at all), and above all a shape whose `git`
// token is not recognized in the first place (`bash -c 'git push …'`). That
// residual pass-through is named and accepted, not closed: the pre-push hook
// is still the real boundary, and widening the scan here is what produced
// false positives on ordinary document text in earlier rounds.
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

// Hands over the PLAIN command on purpose, with no escape in front of it: an
// integration whose commits are already published on the remote is exactly
// what the pre-push hook's content rule lets through, so prefixing
// MB_HUMAN_PUSH here would teach the user to lift the whole guard for a push
// that needs nothing lifted. When the push is NOT such a fast-forward, the
// hook rejects it and its own message names the escape at that moment.
const sharedBranchMessage = (branch) =>
  `UMS: '${branch}' je sdílená větev — okamžik integrace patří člověku, agent do ní nepushuje ani ` +
  `fast-forwardem. Připrav příkaz a nech ho uživateli: \`! git push origin HEAD:${branch}\` ` +
  '(Publication Contract, vrstva aktéra).';

// The human escape honoured by the pre-push hook (the real boundary), under
// both its current and its transitional old name. A command carrying it is
// DENIED here, and that reversal rests on a measured premise: a command the
// user types with a leading `!` never reaches a PreToolUse hook, so anything
// arriving here is the agent's own tool call — and per the contract an agent
// never sets this variable. Its presence is therefore a violation in itself,
// and this is the only mechanical containment left now that the escape lifts
// the whole guard on the hook side. Checked AFTER the --no-verify rule below,
// which has the more specific reason for the same command.
const HUMAN_ESCAPE_RE = /(^|\s)(MB_HUMAN_PUSH|UMS_ALLOW_SHARED_PUSH)=1(\s|$)/;

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

// FAIL-CLOSED, and only here: this function is reached only once the scan has
// recognized a `push` subcommand, so "I cannot read this" means "I cannot
// rule out a push into a protected branch" — and this layer now carries the
// actor rule, so it must not wave that through.
//
// The ONE deliberate exception is an unresolvable current branch: an
// unguessable branch is not a recognized protected target, and denying there
// would block legitimate work from a detached HEAD. It keeps returning
// { deny: false }, exactly as before.
function evaluatePush(args, cwd, patterns) {
  const flags = args.filter((t) => t.startsWith('-'));
  const positionals = args.filter((t) => !t.startsWith('-'));

  const unparseable = (what) => ({
    deny: true,
    reason:
      `UMS: tenhle push neumím spolehlivě přečíst (${what}), a protože nesu pravidlo o tom, ` +
      'kdo smí pushovat do sdílené větve, radši ho zamítám (Publication Contract). ' +
      'Napiš ho srozumitelně: `git push [-u] <remote> <ref>[:<ref>]`.',
  });

  if (flags.some((f) => !PUSH_ALLOWED_FLAGS.has(f))) return unparseable('neznámý přepínač');

  let target = null;
  if (positionals.length === 0) {
    target = currentBranch(cwd) || null;
  } else {
    const [remote, ...refspecs] = positionals;
    if (!REMOTE_RE.test(remote)) return unparseable('nesrozumitelné jméno remote');
    if (refspecs.length === 0) {
      target = currentBranch(cwd) || null;
    } else if (refspecs.length === 1 && REFSPEC_RE.test(refspecs[0])) {
      target = refspecs[0].includes(':') ? refspecs[0].split(':').pop() : refspecs[0];
    } else {
      return unparseable('víc nebo poškozené refspecy');
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

  // This block used to ALLOW the whole command, because the layer handed the
  // user a command carrying the escape and its own guard would have refused
  // it. That reason is gone: commands the user types with a leading `!` never
  // reach this hook, so anything carrying the escape that DOES reach it is
  // the agent's own tool call — a breach of the contract, not a human
  // publication (see HUMAN_ESCAPE_RE).
  if (HUMAN_ESCAPE_RE.test(command)) {
    deny(
      'UMS: `MB_HUMAN_PUSH` je vědomá výjimka ČLOVĚKA a agent ji nikdy nenastavuje ' +
        '(Publication Contract). Připrav příkaz a nech ho uživateli.',
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
