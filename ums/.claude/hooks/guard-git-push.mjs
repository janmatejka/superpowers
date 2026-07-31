// PreToolUse guard for `git push` (contract v2.2, "Publication Contract"):
// the actor's own ticket branch is pushed freely, shared branches never by the
// agent. Deny-list of protected refs plus destructive push shapes.
import { execFileSync } from 'node:child_process';

const PROTECTED = [/^develop$/i, /^main$/i, /^master$/i, /^release\//i];
const DENY_FLAGS = ['--force', '--force-with-lease', '--force-if-includes',
                    '--all', '--mirror', '--delete', '-d', '--prune'];
// A clustered short flag (e.g. `-fu`, `-uf`) is a force push if any letter in
// the cluster is `f`. Plain flags like `-u`, `-q`, `-v` must stay allowed.
const isForceCluster = (t) => /^-[A-Za-z]*f[A-Za-z]*$/.test(t);

const isProtected = (ref) => {
  const name = String(ref).replace(/^refs\/heads\//, '');
  return PROTECTED.some((re) => re.test(name));
};

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

let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch { process.exit(0); }
  const command = String(input?.tool_input?.command ?? '');
  // Only real invocations: `git push` or `git -C <path> push`, not a mention
  // inside a quoted string.
  const m = command.match(/(^|[;&|]\s*)git(\s+-[A-Za-z-]+(=\S+)?|\s+-C\s+\S+)*\s+push\b([^;&|]*)/);
  if (!m) process.exit(0);
  const tail = (m[4] || '').trim();
  const tokens = tail.split(/\s+/).filter(Boolean);

  if (tokens.some((t) => DENY_FLAGS.includes(t) || isForceCluster(t))) {
    deny('UMS: destruktivní push (force / delete / all / mirror) je zakázaný — viz Publication Contract v .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md.');
  }
  const refspecs = tokens.filter((t) => !t.startsWith('-'));
  // drop the remote name (first positional)
  const specs = refspecs.slice(1);
  if (specs.length === 0) {
    const cur = currentBranch(input?.cwd);
    if (!cur) {
      deny('UMS: nelze zjistit aktuální větev, takže push nelze posoudit — spusť ho s explicitní větví (`git push origin <vetev>`).');
    }
    if (isProtected(cur)) {
      deny(`UMS: '${cur}' je sdílená větev — agent do ní nepushuje. Připrav příkaz a nech ho uživateli: \`! git push origin ${cur}\` (Publication Contract, dvouúrovňová push policy).`);
    }
    process.exit(0);
  }
  for (const spec of specs) {
    if (spec.startsWith('+') || spec.startsWith(':')) {
      deny('UMS: vynucený (+) ani mazací (:) refspec není povolený — viz Publication Contract.');
    }
    const dst = spec.includes(':') ? spec.split(':').pop() : spec;
    if (isProtected(dst)) {
      deny(`UMS: '${dst}' je sdílená větev — agent do ní nepushuje. Připrav příkaz a nech ho uživateli: \`! git push origin ${String(dst).replace(/^refs\/heads\//, '')}\` (Publication Contract, dvouúrovňová push policy).`);
    }
  }
  process.exit(0);
});
