// PreToolUse guard for `git push` / `git fetch` (contract v2.2, "Publication
// Contract"): the actor's own ticket branch is pushed freely, shared branches
// never by the agent. Design: DENY BY DEFAULT. A push is allowed only if the
// whole command can be parsed with confidence into a simple, non-destructive
// push to an unprotected branch; anything the parser cannot fully account
// for — an unrecognized flag, a non-plain remote, an unparseable refspec, an
// unrecognized shell shape around the invocation — denies. A fetch is
// allowed unless it names an explicit refspec whose local destination is a
// protected branch (fetch is otherwise frequent and harmless).
import { execFileSync } from 'node:child_process';

const PROTECTED = [/^develop$/i, /^main$/i, /^master$/i, /^release\//i];

const stripRef = (ref) => String(ref).replace(/^refs\/heads\//, '');
const isProtected = (ref) => PROTECTED.some((re) => re.test(stripRef(ref)));

// One shared message for every "this would touch a shared branch" deny, so
// the wording only lives in one place.
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

// Shell control-flow tokens that end the current invocation's argument list
// (so a chained command after `&&`/`;`/`|`/`&` is scanned independently).
const CONTROL = new Set(['&&', '||', ';', '|', '&']);

// Only these flags are recognized for `push`. Anything else — long or
// short, valued or not, clustered or not — denies. This single rule covers
// `--force-with-lease=…`, `-dq`, `--no-verify`, `--tags`, `--mirror`,
// `--all` and every future flag nobody enumerated.
const PUSH_ALLOWED_FLAGS = new Set([
  '-u', '--set-upstream', '-q', '--quiet', '-v', '--verbose',
  '--progress', '--no-progress',
]);
const REMOTE_RE = /^[A-Za-z0-9._-]+$/;
const REFSPEC_RE = /^[A-Za-z0-9._/-]+(:[A-Za-z0-9._/-]+)?$/;

// A token is a git invocation start if, after stripping a leading subshell
// or backtick marker, it is exactly `git`/`git.exe` or ends in `/git` — no
// matter what precedes it (leading spaces, newlines, env assignments,
// subshells, pipes are all irrelevant; we no longer rely on a
// preceding-context pattern).
const isGitToken = (tok) => {
  const t = tok.replace(/^(\$\(|\(|`)/, '');
  return t === 'git' || t === 'git.exe' || /\/git$/.test(t);
};

function evaluatePush(args, cwd) {
  const flags = args.filter((t) => t.startsWith('-'));
  const positionals = args.filter((t) => !t.startsWith('-'));

  for (const f of flags) {
    if (!PUSH_ALLOWED_FLAGS.has(f)) {
      return {
        deny: true,
        reason: `UMS: tenhle tvar \`git push\` neumím bezpečně rozpoznat (neznámý přepínač \`${f}\`) — ` +
          'napiš jednoduchý explicitní push (`git push origin <větev>`) a nech mě ho posoudit (Publication Contract).',
      };
    }
  }

  if (positionals.length === 0) {
    const cur = currentBranch(cwd);
    if (!cur) {
      return {
        deny: true,
        reason: 'UMS: nelze zjistit aktuální větev, takže push nelze posoudit — spusť ho s explicitní větví ' +
          '(`git push origin <vetev>`).',
      };
    }
    return isProtected(cur) ? { deny: true, reason: sharedBranchMessage(cur) } : { deny: false };
  }

  const [remote, ...refspecs] = positionals;
  if (!REMOTE_RE.test(remote)) {
    return {
      deny: true,
      reason: 'UMS: vzdálený repozitář musí být prostý název (ne URL) — použij `git push origin <větev>` ' +
        '(Publication Contract).',
    };
  }

  if (refspecs.length === 0) {
    const cur = currentBranch(cwd);
    if (!cur) {
      return {
        deny: true,
        reason: 'UMS: nelze zjistit aktuální větev, takže push nelze posoudit — spusť ho s explicitní větví ' +
          '(`git push origin <vetev>`).',
      };
    }
    return isProtected(cur) ? { deny: true, reason: sharedBranchMessage(cur) } : { deny: false };
  }

  for (const spec of refspecs) {
    if (!REFSPEC_RE.test(spec)) {
      return {
        deny: true,
        reason: 'UMS: tenhle refspec neumím bezpečně rozparsovat — napiš jednoduchý explicitní push ' +
          '(`git push origin <větev>`) (Publication Contract).',
      };
    }
    const dst = spec.includes(':') ? spec.split(':').pop() : spec;
    if (isProtected(dst)) {
      return { deny: true, reason: sharedBranchMessage(stripRef(dst)) };
    }
  }
  return { deny: false };
}

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
  const tokens = command.split(/\s+/).filter(Boolean);

  let i = 0;
  while (i < tokens.length) {
    if (!isGitToken(tokens[i])) { i++; continue; }
    i++; // past the `git` token itself

    // Consume pre-subcommand options: `-C <path>` / `-c <k=v>` (two-token
    // form) skip both tokens; any attached form (`-C/repo`, `-cfoo=bar`) or
    // other global flag skips just the one token it occupies.
    while (i < tokens.length && tokens[i].startsWith('-')) {
      i += (tokens[i] === '-C' || tokens[i] === '-c') ? 2 : 1;
    }
    if (i >= tokens.length) break; // no subcommand found
    const subcommand = tokens[i];
    i++;

    // Collect this invocation's own argument tokens: stop at a shell
    // control operator, or at the start of another git invocation (handles
    // two `git` commands on separate lines of a multi-line command, with no
    // operator between them).
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
