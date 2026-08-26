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
// A RECOGNIZED `git push` therefore leans FAIL-CLOSED: this file's default
// answer to an invocation it cannot read with confidence is deny, not
// wave-through. Where it holds that answer back, and why, is evaluatePush's
// business — next paragraph. "Recognized" is deliberately narrow: the `git`
// token has to sit at a COMMAND POSITION. Without that requirement the
// tightening would fire on any string that happens to contain the words `git
// push` — a heredoc, a commit message, an `echo` — which is document text,
// not a push.
//
// WHAT THE VERDICT ACTUALLY IS, read it from evaluatePush and from nowhere
// else. This header deliberately does not restate its branches: every earlier
// attempt to summarise them up here was falsified by the next change to the
// function, and a summary that has gone quietly stale is worse than no summary.
//
// A shape this file does not recognize as a command at all (`bash -c 'git push
// …'`) keeps the old FAIL-OPEN answer, as does `git fetch` outside its own
// refspec rule, as does every other subcommand. That residual pass-through is
// named and accepted, not closed: the pre-push hook is still the real
// boundary, and widening the scan here is what produced false positives on
// ordinary document text in earlier rounds.
//
// COMMAND POSITION IS READ FROM WHITESPACE-SPLIT TOKENS, so any separator the
// split does not leave standing alone hides it, and the fail-closed arm then
// does not fire for that invocation at all. Known carriers, same root cause
// and same accepted class: a NEWLINE (`git status` newline `git push --mirror
// origin`), and a separator GLUED to the previous token (`cd /repo; git push
// --mirror origin`, where `/repo;` is neither a CONTROL token nor a NAME=value
// assignment).
// Promoting either to a separator would immediately re-open the heredoc case,
// which is precisely what this rule exists to protect — so the gap is
// accepted. Note what it does NOT cost: a target the guard can read is still
// judged on those shapes, because the protected-target deny does not need
// command position for a cleanly-written invocation (see evaluatePush).
//
// CONTEXT-FREE CHECKS knowingly pay a price for reading the raw command TEXT
// without asking whether it is an invocation at all, because what they guard
// is invisible to a parsed-invocation check: `--no-verify` near `push` would
// skip the real guarantee, and the whole value of HUMAN_ESCAPE_RE is that the
// variable never appears in an agent's command in the first place. The
// accepted cost is the same for each of them: an agent WRITING ABOUT one from
// Bash (a heredoc, an echo, a commit message quoting it) is denied. Closing
// that would mean parsing shell quoting, which is exactly what this layer was
// demoted for failing to do — and for the escape it would also cost the
// containment itself.
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
// never sets this variable. Its presence is therefore a violation in itself.
// On the hook side the escape lifts the whole guard and nothing downstream
// re-examines the push, so this deny is where that examination happens
// instead. Checked AFTER the --no-verify rule below, which has the more
// specific reason for the same command.
//
// The accepted VALUE spellings are the shell's, not a tidier subset of them.
// The hook tests `[ "$MB_HUMAN_PUSH" = "1" ]`, which the shell satisfies for
// `=1`, `="1"` and `='1'` alike, and a trailing `;` or `&` separates the
// assignment just as whitespace does. While this regex ALLOWED the command it
// could afford to be narrow (a missed spelling only meant one more deny);
// now that it DENIES, every spelling it misses is a push waved through — for
// example a non-fast-forward rewrite of the agent's own published ticket
// branch, which the hook would then let past on the escape.
const HUMAN_ESCAPE_RE = /(^|\s)(MB_HUMAN_PUSH|UMS_ALLOW_SHARED_PUSH)=("1"|'1'|1)([\s;&]|$)/;

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
// remote/refspec around them. Any other flag is recorded as a problem for
// evaluatePush to weigh; this line used to end "-> allow", which task 6
// falsified and nothing here noticed for three rounds.
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

// `NAME=value` env assignment, the third shape that can precede a command.
const ENV_ASSIGN_RE = /^[A-Za-z_][A-Za-z0-9_]*=/;

// Shell EXPANSION this tokenizer cannot resolve. A token carrying it names a
// remote or a ref that is simply not in the string, which is the same state
// as `bash -c 'git push …'` — not "a literal I refuse to read". Denying
// `git push "$remote" "$branch"` would make the layer unusable for ordinary
// scripted work while catching nobody: an agent that wanted the bypass has
// the far easier `bash -c` one, named and accepted in the design.
//
// Tested against the tokens that caused ONE problem, never against the whole
// invocation and never against one problem on another's behalf. Round 1 tested
// `args.some(...)` and that was a real weakening: one `$` anywhere bought
// silence about a destination spelled out in plain text, so `git push $r
// develop` and `git push --mirror $r` both went from deny to allow. Round 2
// narrowed it to the causing tokens but still kept only the FIRST problem, so
// an excused one hid an expansion-free one behind it — a wildcard refspec
// after an expanded remote walked straight through. Expansion excuses the
// problem IT caused, and nothing else.
//
// QUOTING alone is deliberately NOT expansion. `git push origin "develop"`
// still names a literal branch, so it stays judged and the obvious evasion
// ("just put quotes round it") stays closed.
const EXPANSION_RE = /[$`]/;

// Surrounding quotes come off before a token is read AS A REF, for the same
// reason: `"develop"` still names develop. The RAW token is what decides
// whether the invocation is cleanly WRITTEN, so a quoted branch is still
// reported as unreadable when nothing protected turned up — two different
// questions about the same token, deliberately answered differently.
const unquote = (tok) => tok.replace(/^(['"])([\s\S]*)\1$/, '$2');

// Reads an invocation TWICE over, because the two answers are independent:
//
//   targets  — every destination this push can be read to name. An unreadable
//              token blinds the guard to THAT destination, not to the others.
//   problems — a LIST of what could not be read, each with the tokens that
//              made it unreadable. A list, because one problem being excused
//              says nothing about the next one.
//
// A readable protected target is judged FIRST, before any problem is weighed:
// an unreadable token elsewhere on the line must not buy silence about a
// destination the command spells out (round 2: the old code returned out of
// the unreadable path before ever looking, so `git push $r develop` was
// allowed; today it denies on `develop`). For a MESSY invocation that is itself
// gated on command position — in `cat <<EOF … git push --force origin develop
// … EOF` the word `develop` is document text, and only the command position
// tells the two apart. A CLEAN invocation needs no such permission: `git
// status` newline `git push origin develop` names develop with no guessing.
//
// What each of the remaining checks asks, and why, is written beside the check
// itself below rather than summarised here.
//
// `atCommandPosition` DEFAULTS TO TRUE so a stale call site omitting it
// degrades toward more protection, the same rule loadProtected follows.
function evaluatePush(args, cwd, patterns, atCommandPosition = true) {
  const flags = args.filter((t) => t.startsWith('-'));
  const positionals = args.filter((t) => !t.startsWith('-'));

  // A LIST, not a first-one-wins slot: each problem is judged against the
  // tokens that caused IT, so an excused problem cannot shadow an unexcused
  // one. `git push $r a:b c:d` has an expansion-caused bad remote AND an
  // entirely expansion-free refspec defect; recording only the first let the
  // second walk through.
  const problems = [];
  const note = (what, tokens) => problems.push({ what, tokens });

  const targets = [];
  // A current branch that cannot be resolved contributes NO target rather than
  // a guessed one: an unguessable branch is not a recognized protected target,
  // and denying there would block legitimate work from a detached HEAD.
  const addCurrent = () => { const c = currentBranch(cwd); if (c) targets.push(c); };

  const badFlags = flags.filter((f) => !PUSH_ALLOWED_FLAGS.has(f));
  if (badFlags.length > 0) note('neznámý přepínač', badFlags);

  if (positionals.length === 0) {
    addCurrent();
  } else {
    const [remote, ...refspecs] = positionals;
    if (!REMOTE_RE.test(remote)) note('nesrozumitelné jméno remote', [remote]);
    if (refspecs.length === 0) {
      addCurrent();
    } else {
      for (const r of refspecs) {
        const bare = unquote(r);
        if (REFSPEC_RE.test(bare)) targets.push(bare.includes(':') ? bare.split(':').pop() : bare);
      }
      // The RAW token decides "cleanly written", the unquoted one decided
      // "names a destination" above - so `git push origin "develop"` yields a
      // readable target AND stays reported as not plainly written.
      const notPlain = refspecs.filter((r) => !REFSPEC_RE.test(r));
      if (notPlain.length > 0) note('víc nebo poškozené refspecy', notPlain);
      else if (refspecs.length > 1) note('víc nebo poškozené refspecy', refspecs);
    }
  }

  // A target read out of an invocation with nothing wrong with it needs no
  // permission — it was spelled out. Read out of one this file could not fully
  // parse, it only counts as a destination if the `git` was a command in the
  // first place; otherwise `develop` in a heredoc body would be a push target.
  if (problems.length === 0 || atCommandPosition) {
    const hit = targets.find((t) => isProtected(t, patterns));
    if (hit) return { deny: true, reason: sharedBranchMessage(stripRef(hit)) };
  }

  // A problem blocks where the invocation is one this file may judge at all,
  // and where what made it unreadable is actually in the string.
  //
  // Command position — the `git` token starts an invocation (index 0, after a
  // shell control operator, or after a NAME=value assignment). Without it,
  // fail-closed would fire on any string CONTAINING the words `git push`: a
  // heredoc being written to a file, a commit message quoting a command, an
  // `echo`. That is document text, and denying it is the exact failure mode
  // this layer was demoted for.
  //
  // And no shell expansion in the tokens that CAUSED that problem (see
  // EXPANSION_RE) — per problem and per token, never on another problem's
  // behalf, which is why this is a `find` over the list and not a test of the
  // whole invocation.
  const blocking = atCommandPosition
    ? problems.find((p) => !p.tokens.some((t) => EXPANSION_RE.test(t)))
    : undefined;
  if (blocking) {
    return {
      deny: true,
      reason:
        `UMS: tenhle push neumím spolehlivě přečíst (${blocking.what}), a protože nesu pravidlo o tom, ` +
        'kdo smí pushovat do sdílené větve, radši ho zamítám (Publication Contract). ' +
        'Napiš ho srozumitelně: `git push [-u] <remote> <ref>[:<ref>]`.',
    };
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

// Fetch stays best-effort on the same footing as before. It reads an explicit
// refspec's destination and denies where that destination would overwrite a
// protected local ref — by name, or through a wildcard that covers local
// branches (see isWildcardLocalBranch above). A destination it cannot read
// that way passes; fetch is frequent and normally harmless, and task 6's
// fail-closed turn was deliberately confined to `push`.
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
  // positive here is cheap — the agent rewords — so the check deliberately is
  // not tied to a specific parsed invocation. An accepted edge of that: a
  // commit message that happens to contain both words is denied too.
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
  const escape = command.match(HUMAN_ESCAPE_RE);
  if (escape) {
    // Names the variable that ACTUALLY matched, not whichever one this file
    // mentions first — the message is read by someone who wrote one of the
    // spellings HUMAN_ESCAPE_RE knows and needs to know which one is the
    // problem. And it hands over the command with the assignment stripped, the
    // way sharedBranchMessage does: a deny that only scolds leaves the agent to
    // improvise the way out.
    //
    // Stripping the assignment is textual surgery, so the remainder is handed
    // over only if `runnable` below accepts it: it must begin `git push `, run
    // to the end of the string, and contain none of `\n ; & |` or a second
    // escape. Two rounds of narrowing got here. `\bgit\b` was not enough:
    // `export MB_HUMAN_PUSH=1 && git push …` leaves the fragment `export &&
    // git push …`, a line continuation leaves a stray backslash, and a command
    // carrying BOTH names keeps the deprecated one — all three still contain
    // the word `git` and none of them runs. A PREFIX test was not enough
    // either: everything APPENDED after the push rode along into the handed
    // command, chained second commands and whole second lines included, and
    // that is the part a human would paste without noticing.
    //
    // Read `runnable` as exactly the test on the next line, not as "a clean
    // `git push`", which is how earlier wording here glossed it and got it
    // wrong. Measured, both still handed over verbatim: `git push origin
    // develop > /tmp/x` (a redirection) and `git push origin $(whoami)` (a
    // command substitution, which runs when the human pastes it). Left that
    // way on purpose: the agent composed the text of this command in the first
    // place and can put any text in its own message to the user, so this
    // hand-over is not a channel that tightening would take away from it. If
    // it is ever tightened anyway, delete this paragraph with the same commit.
    const plain = command.replace(HUMAN_ESCAPE_RE, '$1').replace(/^[\s;&]+/, '').trim();
    const runnable = /^git\s+push\s+[^\n;&|]*$/.test(plain) && !HUMAN_ESCAPE_RE.test(plain);
    const advice = runnable
      ? `Připrav příkaz a nech ho uživateli: \`! ${plain}\``
      : 'Připrav příkaz a nech ho uživateli.';
    deny(
      `UMS: \`${escape[2]}\` je vědomá výjimka ČLOVĚKA a agent ji nikdy nenastavuje ` +
        `(Publication Contract). ${advice}`,
    );
  }

  const tokens = command.split(/\s+/).filter(Boolean);
  let i = 0;
  while (i < tokens.length) {
    if (!isGitToken(tokens[i])) { i++; continue; }
    // Captured BEFORE the index moves: whether this `git` starts a command is
    // a fact about the token to its LEFT, and everything below advances `i`.
    const atCommandPosition = i === 0
      || CONTROL.has(tokens[i - 1])
      || ENV_ASSIGN_RE.test(tokens[i - 1]);
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
      const r = evaluatePush(args, cwd, patterns, atCommandPosition);
      if (r.deny) deny(r.reason);
    } else if (subcommand === 'fetch') {
      const r = evaluateFetch(args, patterns);
      if (r.deny) deny(r.reason);
    }
    // any other subcommand: not this hook's concern, keep scanning
  }
  process.exit(0);
});
