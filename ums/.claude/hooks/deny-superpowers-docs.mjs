// PreToolUse guard: superpowers spec/plan documents belong to
// <PLAN_MB>/proposals/active/ in this repository (see
// .claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md, "Superpowers Document
// Placement"). Deny Write/Edit into the upstream default locations so a
// session that skipped Target-MB discovery fails closed instead of creating
// docs/superpowers/.
let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let input = {};
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0); // unparseable input -> do not block
  }
  const filePath = String(input?.tool_input?.file_path ?? '').replaceAll('\\', '/');
  if (/(^|\/)docs\/(superpowers|plans)\//i.test(filePath)) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason:
            'UMS: spec/plan dokumenty patří do <PLAN_MB>/proposals/active/ ' +
            '(proposal_<slug>-design.md / proposal_<slug>.md), ne do docs/superpowers/ ani docs/plans/. ' +
            'Pokud Target MB Pin chybí, proveď Target-MB discovery dle ' +
            '.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md (Superpowers Document Placement, Target-MB Discovery & Pinning).',
        },
      }),
    );
  }
  process.exit(0);
});
