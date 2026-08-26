Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')

# guard-git-push.mjs is NOT the enforcement boundary — the git `pre-push` hook
# is, and its own fixture-driven suite is pre-push.tests.ps1. What this file
# pins is the rule this layer DOES carry alone: the ACTOR rule, that the
# moment of integration belongs to a human. Only the agent's own tool calls
# reach a PreToolUse hook, so a push arriving here is the agent's, and a
# protected branch is off limits to it even as a fast-forward the hook would
# accept.
#
# A RECOGNIZED push — a `git` token at a command position — leans FAIL-CLOSED
# here: the guard's default answer to an invocation it cannot read is deny, not
# wave-through. Where the `git` token is not recognized as one at all (`bash -c
# '…'`, whose token is `'git`), the command never reaches evaluatePush and no
# opinion about a push comes out of it; `fetch` outside its own refspec rule
# and every other subcommand do not reach it either. A recognized `git` that is
# merely not at a command position is a different thing and is NOT in that
# group — `echo git push origin develop` denies, and cases below pin it. Where
# a given case sits on that boundary is said at the case; what the verdict IS
# is decided in guard-git-push.mjs's evaluatePush, and comments here point
# there instead of restating the shape of the whole decision — that restatement
# is what has gone stale in this file repeatedly.

function Test-Cmd([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-Hook ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# Same shape as Test-Cmd with the OTHER tool name. The guard is registered on
# `Bash|PowerShell` (settings.json, asserted below), and this fork's sessions
# run on the PowerShell tool — so every rule that reads the command TEXT has to
# be pinned in PowerShell's spelling too, not only in POSIX shell's. Until this
# helper existed the whole suite spoke `Bash`, and the escape containment was
# measurably absent on the tool actually in use.
function Test-CmdPs([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'PowerShell'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-Hook ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# Same shape as Test-Cmd, but returns exit code and stderr too (via
# Invoke-HookFull) — for assertions whose point is "must not throw", where
# stdout alone cannot distinguish a crash from a clean allow.
function Test-CmdFull([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-HookFull ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# For `cwd` shapes Test-CmdFull's [string] parameter cannot carry — explicit
# JSON null, a number, an object — always emits the `cwd` key, whatever its
# value.
function Test-CmdRawFull([string] $Command, $CwdValue) {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command }; cwd = $CwdValue }
    return Invoke-HookFull ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# ---------------------------------------------------------------------------
# allowed: ordinary, unprotected pushes/fetches and unrelated commands
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa') '' 'push tiketové větve projde'
Assert-Eq (Test-Cmd 'git push -u origin feature/ums-1-alfa') '' 'push s -u projde'
Assert-Eq (Test-Cmd 'git push -q origin feature/ums-1-alfa') '' 'push s -q projde'
Assert-Eq (Test-Cmd 'git -C /repo push origin feature/ums-1-alfa') '' 'push s -C projde'
Assert-Eq (Test-Cmd 'git status') '' 'jiný git příkaz se neřeší'
Assert-Eq (Test-Cmd 'echo "git push origin develop"') '' 'zmínka v echu se neřeší'
Assert-Eq (Test-Cmd 'git fetch origin') '' 'fetch bez refspecu projde'

# ---------------------------------------------------------------------------
# denied: a push whose target is a protected branch and whose invocation parses
# cleanly enough to read that target — the actor rule this layer carries
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push origin develop',
    'git push origin main',
    'git push origin release/2026.1',
    'git push origin HEAD:refs/heads/develop',
    'cd /repo && git push origin develop',
    'git -C /repo push origin master',
    'FOO=bar git push origin develop',
    'git -c protocol.version=2 push origin develop'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto (jednoduchý push na chráněnou větev): $c" }

# multi-invocation scan still finds a push on the second "line" of a command
Assert-Match (Test-Cmd "git status`ngit push origin develop") 'permissionDecision.*deny' 'zamítnuto: push za jiným git příkazem ve stejném řádku/víceřádku'

# ---------------------------------------------------------------------------
# DENIED, and this is the direction reversed by task 6: a RECOGNIZED `git push`
# this file cannot read with confidence as harmless now leans fail-CLOSED. These
# assertions used to pin the opposite ("unknown flag -> allow, the pre-push
# hook decides"), which was defensible while this layer carried no rule of its
# own; it now carries the actor rule, so waving through the shapes it does not
# understand would be waving through the very thing it exists to catch.
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push --force origin feature/ums-1-alfa',
    'git push -f origin feature/ums-1-alfa',
    'git push --force-with-lease origin feature/ums-1-alfa',
    'git push origin +feature/ums-1-alfa',
    'git push origin :feature/ums-1-alfa',
    'git push --delete origin feature/ums-1-alfa',
    'git push --all origin',
    'git push --mirror origin',
    'git push -fu origin feature/ums-1-alfa',
    'git push -uf origin feature/ums-1-alfa',
    'git push -dq origin feature/ums-1-alfa',
    'git push --force-with-lease=refs/heads/x:deadbeef origin x',
    'git push --force origin develop'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto (rozpoznaný push, kterému guard nerozumí): $c" }

# ---------------------------------------------------------------------------
# The PRICE of the reversal above, pinned rather than hidden: shapes that
# round 2 deliberately let through as "not cleanly parseable" are denied now,
# because each of these IS a push — `git` at a command position — that this
# file cannot read. Erring toward denying costs the agent a rewrite; erring
# the other way hands it a protected branch.
#
# `git push origin feature/ums-1-alfa 2>&1` USED TO SIT IN THIS LIST and does
# not any more. It was never a shape the guard could not read — the push is
# spelled out in full and `2>&1` is the shell's, not git's. Paying the price
# there fired on the agent's own ticket-branch push whenever it carried
# ordinary plumbing, which the publication rule asks for after every commit.
# Redirection is now stepped over; the block near the end of this file pins
# that, its limits, and the controls that keep it from loosening anything else.
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push origin "feature/ums-1-alfa"',
    'git push origin feature/ums-1-alfa # nasazení'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto (rozpoznaný push v tvaru, kterému guard nerozumí): $c" }

# ... and the LINE that keeps the price from being paid on text that is not a
# push at all: the tightening needs `git` at a COMMAND POSITION. In a commit
# message the inner `git` is preceded by `"vysvetli`, so it is a word in a
# string, not an invocation, and the old fail-open answer stands.
Assert-Eq (Test-Cmd 'git commit -m "vysvetli git push origin develop"') '' 'povoleno: `git push` uvnitř commit message není příkaz na command position'

# ---------------------------------------------------------------------------
# `--no-verify` next to `push`: read straight off the command TEXT, without
# asking whether it is an invocation, because that flag would skip the real
# guarantee (the pre-push hook)
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git push --no-verify origin feature/ums-1-alfa') 'permissionDecision.*deny' 'zamítnuto: --no-verify u pushe'
Assert-Match (Test-Cmd 'git push origin feature/ums-1-alfa --no-verify') 'permissionDecision.*deny' 'zamítnuto: --no-verify u pushe (na konci)'
Assert-Eq (Test-Cmd 'git commit --no-verify -m msg') '' '--no-verify bez zmínky o push neřeší (commit, ne push)'
Assert-Eq (Test-Cmd 'npm run push -- --no-verify') '' '--no-verify bez zmínky o gitu neřeší (žádný git v příkazu)'

# ---------------------------------------------------------------------------
# denied: fetch that would overwrite a protected local ref (unchanged from
# round 1 — best effort, same footing, not fail-closed for the rest of fetch)
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git fetch https://example.com/evil.git feature:refs/heads/develop') 'permissionDecision.*deny' 'zamítnuto: fetch přepisující lokální develop'

# a WILDCARD destination names no branch, so the protected-name test alone
# never matched it — yet it overwrites every local branch, develop included
Assert-Match (Test-Cmd 'git fetch https://example.com/evil.git +refs/heads/*:refs/heads/*') 'permissionDecision.*deny' 'zamítnuto: fetch se žolíkem do lokálních větví'
# the WORDING is asserted too, not just the deny — otherwise a revert of the
# fix-round-1 message change (dropping the hardcoded "develop, main, master,
# release/*" list, which lies whenever the configured list differs) would
# pass unnoticed
Assert-Match (Test-Cmd 'git fetch https://example.com/evil.git +refs/heads/*:refs/heads/*') 'chráněné větve tohoto repozitáře' 'zamítnutí žolíkového fetchu mluví o chráněných větvích repozitáře, ne o natvrdo vypsaném seznamu'
Assert-NotMatch (Test-Cmd 'git fetch https://example.com/evil.git +refs/heads/*:refs/heads/*') 'develop, main, master' 'zamítnutí žolíkového fetchu už nejmenuje natvrdo vypsaný vestavěný seznam (lhal by, kdyby byl nakonfigurovaný seznam jiný)'
Assert-Match (Test-Cmd 'git fetch origin refs/heads/*:*') 'permissionDecision.*deny' 'zamítnuto: žolík bez prefixu refs/ je taky lokální větev'
# ... while the everyday refspec into remote-tracking refs must keep passing
Assert-Eq (Test-Cmd 'git fetch origin +refs/heads/*:refs/remotes/origin/*') '' 'běžný refspec do remote-tracking refů projde'

# ---------------------------------------------------------------------------
# protected branches come from memory-bank/ums-repo.json's `protectedBranches`
# (task 3), the SAME source of truth as the pre-push hook — the contract
# explicitly warns that the two enforcement layers disagreeing is a defect.
# ---------------------------------------------------------------------------
function New-ConfigFixture([string] $Json) {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("mbhookcfg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join-Path $r 'memory-bank') | Out-Null
    Set-Content -LiteralPath (Join-Path $r 'memory-bank\ums-repo.json') -Value $Json
    return $r
}

# 1. Configured pattern the built-in list does NOT know: `Branches/*` denies
# a push to `Branches/5.37` only once it comes from configuration.
$cfg1 = New-ConfigFixture @'
{
  "protectedBranches": ["Branches/*"]
}
'@
Assert-Match (Test-Cmd 'git push origin Branches/5.37' $cfg1) 'permissionDecision.*deny' 'zamítnuto: konfigurace obsahuje Branches/*, push na Branches/5.37 je zamítnutý'
# glob -> regex must stay case-insensitive: a pattern written as `Branches/*`
# has to match the lower-cased spelling too.
Assert-Match (Test-Cmd 'git push origin branches/5.37' $cfg1) 'permissionDecision.*deny' 'zamítnuto: shoda vzoru je case-insensitive (branches/5.37 vs. konfigurovaný Branches/*)'
Remove-Item -Recurse -Force $cfg1

# 2. THE LOAD-BEARING NEGATIVE: without any configuration, the SAME push must
# be ALLOWED, because the built-in fallback list does not know `Branches/*`.
# If this passed as denied, it would prove the guard denies everything rather
# than actually reading the configured list.
$noCfg = Join-Path ([IO.Path]::GetTempPath()) ("mbhooknocfg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $noCfg | Out-Null
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $noCfg) '' 'povoleno: bez konfigurace zná guard jen vestavěný seznam, Branches/* v něm není'

# 3. Without configuration, a BUILT-IN name is still protected — the fallback
# itself must still work, not just "fall back to nothing".
Assert-Match (Test-Cmd 'git push origin develop' $noCfg) 'permissionDecision.*deny' 'zamítnuto i bez konfigurace: develop je součástí vestavěného seznamu'

# 4. Broken configuration (malformed JSON) must behave exactly like a missing
# one: MORE protection than "no fallback", never less.
$cfgBroken = New-ConfigFixture '{ this is not valid json'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgBroken) '' 'povoleno: rozbitá konfigurace padá na vestavěný seznam (Branches/* v něm chybí)'
Assert-Match (Test-Cmd 'git push origin develop' $cfgBroken) 'permissionDecision.*deny' 'zamítnuto: rozbitá konfigurace stále chrání vestavěný seznam'
Remove-Item -Recurse -Force $cfgBroken

# 4b. Valid JSON that is NOT AN OBJECT (array / number / null) — same fallback
# trap that hit task 3's PowerShell loader (a Critical there), in JS shape:
# `parsed.protectedBranches` on a non-object must not throw, it must miss.
foreach ($json in @('[1,2,3]', '42', 'null')) {
    $cfgNonObj = New-ConfigFixture $json
    Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgNonObj) '' "povoleno: konfigurace '$json' (validní JSON, ne objekt) padá na vestavěný seznam bez vyhození výjimky"
    Assert-Match (Test-Cmd 'git push origin develop' $cfgNonObj) 'permissionDecision.*deny' "zamítnuto: konfigurace '$json' stále chrání vestavěný seznam"
    Remove-Item -Recurse -Force $cfgNonObj
}

# 5. The rejection message must advise the REFSPEC form (task 4 changed the
# pre-push hint the same way) — a bare `git push origin <branch>` fails on a
# ticket clone that never had a local copy of the shared branch.
Assert-Match (Test-Cmd 'git push origin develop') 'HEAD:' 'zamítnutí radí refspecový tvar (obsahuje HEAD:)'

# ---------------------------------------------------------------------------
# fix round 1, IMPORTANT: an array whose entries are all non-strings must
# fall back, not silently replace the built-in list with useless patterns.
# `Array.isArray(list) && list.length > 0` alone accepted [1, null, ["x"],
# {"a":1}] and globToRe() stringified each entry into /^1$/, /^null$/, /^x$/,
# /^\[object Object\]$/ — none of which match any real branch, so `develop`
# passed through UNPROTECTED with no warning. Filtering to usable (string,
# non-empty-after-trim) entries BEFORE the length test fixes this: "nothing
# usable remains" now degrades exactly like "the key is absent".
# ---------------------------------------------------------------------------
$cfgNonStr = New-ConfigFixture '{ "protectedBranches": [1, null, ["x"], {"a":1}] }'
Assert-Match (Test-Cmd 'git push origin develop' $cfgNonStr) 'permissionDecision.*deny' 'zamítnuto: pole se samými non-string prvky padá na vestavěný seznam (develop je v něm)'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgNonStr) '' 'povoleno: pole se samými non-string prvky nedává žádnou ochranu navíc (Branches/* ve vestavěném seznamu není)'
$fullNonStr = Test-CmdFull 'git push origin develop' $cfgNonStr
Assert-Eq $fullNonStr.Code 0 'exit 0: pole se samými non-string prvky nezpůsobí pád procesu'
Assert-Eq $fullNonStr.Err '' 'žádný stderr: pole se samými non-string prvky nevyhodí nezachycenou výjimku'
Remove-Item -Recurse -Force $cfgNonStr

# minimal repro of the same trap: a single non-string entry
$cfgSingleNonStr = New-ConfigFixture '{ "protectedBranches": [1] }'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgSingleNonStr) '' 'povoleno: protectedBranches: [1] (jediný prvek, ne string) padá na vestavěný seznam'
Remove-Item -Recurse -Force $cfgSingleNonStr

# ---------------------------------------------------------------------------
# fix round 1, minor: configuration shapes that previously had no coverage
# ---------------------------------------------------------------------------

# protectedBranches: null (key present, value null)
$cfgNull = New-ConfigFixture '{ "protectedBranches": null }'
Assert-Match (Test-Cmd 'git push origin develop' $cfgNull) 'permissionDecision.*deny' 'zamítnuto: protectedBranches: null padá na vestavěný seznam'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgNull) '' 'povoleno: protectedBranches: null nedává ochranu navíc'
Remove-Item -Recurse -Force $cfgNull

# protectedBranches: [] (key present, explicitly empty array)
$cfgEmptyArr = New-ConfigFixture '{ "protectedBranches": [] }'
Assert-Match (Test-Cmd 'git push origin develop' $cfgEmptyArr) 'permissionDecision.*deny' 'zamítnuto: protectedBranches: [] padá na vestavěný seznam'
Remove-Item -Recurse -Force $cfgEmptyArr

# protectedBranches as a bare STRING instead of an array: NORMALIZED to a
# single-element list, exactly as the PowerShell loader's @() wrapping does.
#
# This assertion used to pin the opposite behaviour — the fall-back to the
# built-in list — and that made the two enforcement layers DISAGREE about one
# configuration: Get-UmsRepoConfig.ps1 accepted the bare string, the installer
# baked it into the generated list and `pre-push` REJECTED a push to
# `Branches/5.37`, while this guard required Array.isArray, fell back to the
# built-in four and ALLOWED the very same push (reproduced empirically). No
# protection was lost — the stricter layer is the real boundary — but the
# pre-push hook states in its own comment that the layers must not disagree, so
# the layer was shipping an invariant it violated.
$cfgStrShape = New-ConfigFixture '{ "protectedBranches": "develop" }'
Assert-Match (Test-Cmd 'git push origin develop' $cfgStrShape) 'permissionDecision.*deny' 'zamítnuto: protectedBranches jako string se normalizuje na jednoprvkový seznam (develop je v něm)'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $cfgStrShape) '' 'povoleno: protectedBranches: "develop" chrání jen develop, nic navíc'
Remove-Item -Recurse -Force $cfgStrShape

# CROSS-LAYER PARITY for the bare-string shape. The same input the PowerShell
# side is asserted on in shared/tests/repo-config.tests.ps1: `"Branches/*"` as a
# bare string must yield the single-element list ["Branches/*"], which means the
# configured pattern REPLACES the built-in list here exactly as an array would —
# `Branches/5.37` denied, `develop` allowed. Under the old Array.isArray-only
# read both answers were inverted, and the pre-push side's answers were not.
$cfgStrParity = New-ConfigFixture '{ "protectedBranches": "Branches/*" }'
Assert-Match (Test-Cmd 'git push origin Branches/5.37' $cfgStrParity) 'permissionDecision.*deny' 'parita s pre-push: bare string "Branches/*" zamítá Branches/5.37 (dřív oba layery odpovídaly různě)'
Assert-Eq (Test-Cmd 'git push origin develop' $cfgStrParity) '' 'parita s pre-push: bare string "Branches/*" nahrazuje vestavěný seznam stejně jako pole, takže develop projde'
$fullStrParity = Test-CmdFull 'git push origin Branches/5.37' $cfgStrParity
Assert-Eq $fullStrParity.Err '' 'žádný stderr: normalizace bare stringu nevyhodí nezachycenou výjimku'
Remove-Item -Recurse -Force $cfgStrParity

# a configured pattern carrying a regex metacharacter must stay LITERAL — "."
# must not mean "any character" the way it would in a raw regex. Confined to
# the parseable branch-name charset (letters/digits/./_/-//), since the outer
# refspec parser (REFSPEC_RE) only trusts those characters as a readable
# destination — a pattern outside it could never be MATCHED against a target,
# so the case would prove nothing about the protected list. (Since task 6 such
# a refspec is denied as unreadable rather than waved through, which is a
# different answer for a different reason and still not a test of the list.)
$cfgDot = New-ConfigFixture '{ "protectedBranches": ["release.1"] }'
Assert-Eq (Test-Cmd 'git push origin releaseX1' $cfgDot) '' 'povoleno: literální "." se neinterpretuje jako regex "libovolný znak" (releaseX1 neodpovídá release.1)'
Assert-Match (Test-Cmd 'git push origin release.1' $cfgDot) 'permissionDecision.*deny' 'zamítnuto: přesná shoda s literálním vzorem release.1'
Remove-Item -Recurse -Force $cfgDot

# invalid / nonexistent cwd must not throw, and must degrade toward the
# built-in list like every other unreadable-configuration case
$cfgProof = New-ConfigFixture '{ "protectedBranches": ["Branches/*"] }'
$nonexistentCwd = Join-Path $cfgProof 'does-not-exist-zzz'
Assert-Match (Test-Cmd 'git push origin develop' $nonexistentCwd) 'permissionDecision.*deny' 'zamítnuto: neexistující cwd padá na vestavěný seznam (develop je v něm)'
Assert-Eq (Test-Cmd 'git push origin Branches/5.37' $nonexistentCwd) '' 'povoleno: neexistující cwd nemůže přečíst Branches/*, žádná ochrana navíc'
$fullNonexistentCwd = Test-CmdFull 'git push origin develop' $nonexistentCwd
Assert-Eq $fullNonexistentCwd.Code 0 'exit 0: neexistující cwd nezpůsobí pád procesu'
Assert-Eq $fullNonexistentCwd.Err '' 'žádný stderr: neexistující cwd nevyhodí nezachycenou výjimku'
Remove-Item -Recurse -Force $cfgProof

# cwd: JSON null — falsy in JS, so `cwd || process.cwd()` falls through to
# the guard's own process cwd. Whichever repository that happens to be, it
# must not throw and `develop` (in every repository's fallback OR real list
# this suite could run against) must still be denied.
$fullNullCwd = Test-CmdRawFull 'git push origin develop' $null
Assert-Eq $fullNullCwd.Code 0 'exit 0: cwd: null nezpůsobí pád procesu'
Assert-Eq $fullNullCwd.Err '' 'žádný stderr: cwd: null nevyhodí nezachycenou výjimku'
Assert-Match $fullNullCwd.Out 'permissionDecision.*deny' 'cwd: null nezablokuje ochranu: develop zůstává zamítnutý'

# cwd: a NUMBER — truthy in JS, so it is used as-is; `path.join(42, ...)`
# throws a TypeError, which must be caught by loadProtected's own try/catch,
# not escape to the top level.
$fullNumCwd = Test-CmdRawFull 'git push origin Branches/5.37' 42
Assert-Eq $fullNumCwd.Code 0 'exit 0: cwd jako číslo nezpůsobí pád procesu'
Assert-Eq $fullNumCwd.Err '' 'žádný stderr: cwd jako číslo nevyhodí nezachycenou výjimku'
Assert-Eq $fullNumCwd.Out '' 'povoleno: cwd jako číslo padá na vestavěný seznam (Branches/* v něm chybí)'

# cwd: an OBJECT — same shape of trap as the number, different JS falsy/truthy
# path (an object is always truthy).
$fullObjCwd = Test-CmdRawFull 'git push origin Branches/5.37' (@{ x = 1 })
Assert-Eq $fullObjCwd.Code 0 'exit 0: cwd jako objekt nezpůsobí pád procesu'
Assert-Eq $fullObjCwd.Err '' 'žádný stderr: cwd jako objekt nevyhodí nezachycenou výjimku'
Assert-Eq $fullObjCwd.Out '' 'povoleno: cwd jako objekt padá na vestavěný seznam (Branches/* v něm chybí)'

# cwd key ABSENT entirely from the JSON (not merely empty) — the exit-code/
# stderr half of a shape the suite already exercises via Test-Cmd elsewhere
$fullMissingCwd = Test-CmdFull 'git push origin develop'
Assert-Eq $fullMissingCwd.Code 0 'exit 0: chybějící cwd (klíč v JSON vůbec není) nezpůsobí pád procesu'
Assert-Eq $fullMissingCwd.Err '' 'žádný stderr: chybějící cwd nevyhodí nezachycenou výjimku'

# unparseable stdin — Invoke-Hook (below) already pins the stdout shape;
# this adds the exit-code/stderr half of "must not block", which stdout
# alone cannot prove (a crash with no stdout looks identical to a clean
# allow under Assert-Eq ... '').
$fullBadStdin = Invoke-HookFull 'not json'
Assert-Eq $fullBadStdin.Code 0 'exit 0: nerozparsovatelný vstup nezpůsobí pád procesu'
Assert-Eq $fullBadStdin.Err '' 'žádný stderr: nerozparsovatelný vstup nevyhodí nezachycenou výjimku'

# ---------------------------------------------------------------------------
# MB_HUMAN_PUSH=1 — the human escape the pre-push hook honours, DENIED here.
# These assertions used to pin the opposite (the escape passes through),
# which was right while the hook's escape was narrow and this layer carried no
# rule: the layer would otherwise have blocked the command it hands the user.
# It no longer does, on a measured premise: only the agent's own tool calls
# reach a PreToolUse hook, a command the user types with a leading `!` never
# does (task 1). So the variable turning up HERE means an agent wrote it —
# a contract violation on its own. On the hook side the escape lifts the whole
# guard and nothing downstream re-examines the push, so this deny is where that
# examination happens instead.
# ---------------------------------------------------------------------------
$rEscape = Test-Cmd 'MB_HUMAN_PUSH=1 git push origin HEAD:develop'
Assert-Match $rEscape 'permissionDecision.*deny' 'guard zamítne agentní push nesoucí lidskou výjimku'
Assert-Match $rEscape 'MB_HUMAN_PUSH' 'zamítnutí pojmenuje proměnnou, kvůli které padlo'
# ... and hands over the command with the variable stripped, the same way the
# shared-branch rejection does — a deny that only scolds leaves the agent to
# improvise the way out
Assert-Match $rEscape '! git push origin HEAD:develop' 'zamítnutí podává příkaz bez výjimky, ne jen výtku'
# the old name is the same violation while it is still honoured by the hook,
# and the message must name the one that ACTUALLY triggered it
$rOldEscape = Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push origin develop'
Assert-Match $rOldEscape 'permissionDecision.*deny' 'guard zamítne i staré jméno výjimky'
Assert-Match $rOldEscape 'UMS_ALLOW_SHARED_PUSH' 'zamítnutí jmenuje proměnnou, která ho spustila, ne tu druhou'
Assert-Match $rOldEscape '! git push origin develop' 'zamítnutí u starého jména podává příkaz taky'

# ---------------------------------------------------------------------------
# Fix round 1, Important 3: the containment is only as wide as the SHELL's own
# reading of the variable. `[ "$MB_HUMAN_PUSH" = "1" ]` in the hook is
# satisfied by every spelling below, so a regex bounded by a bare `=1` and
# whitespace would let an agent set the escape and be waved through — the very
# hole this deny exists to close, now that the hook's escape lifts everything.
# ---------------------------------------------------------------------------
foreach ($c in @(
    'MB_HUMAN_PUSH="1" git push origin develop',
    "MB_HUMAN_PUSH='1' git push origin develop",
    'MB_HUMAN_PUSH=1; git push origin develop',
    'MB_HUMAN_PUSH=1;git push origin develop',
    'MB_HUMAN_PUSH="1"; git push origin feature/ums-1-alfa',
    'export MB_HUMAN_PUSH=1 && git push origin feature/ums-1-alfa',
    'UMS_ALLOW_SHARED_PUSH="1" git push origin develop'
)) {
    $rSpelling = Test-Cmd $c
    Assert-Match $rSpelling 'permissionDecision.*deny' "výjimka rozpoznaná i v tomto zápisu: $c"
    # ... and the deny must be the ESCAPE's, not the shared-branch one that
    # would fire anyway for a `develop` target - otherwise half these cases
    # would pass without the pattern recognizing the spelling at all
    Assert-Match $rSpelling 'MB_HUMAN_PUSH|UMS_ALLOW_SHARED_PUSH' "zamítnutí patří výjimce, ne sdílené větvi: $c"
}

# ---------------------------------------------------------------------------
# Fix round 2, Minor C: the handed command has to be RUNNABLE. It is built by
# stripping the assignment out of the agent's own command, and that is textual
# surgery — a fragment, a stray line continuation or a SECOND escape left in
# place would all still contain the word `git`. Each of those must fall back to
# the generic sentence rather than hand over something that would fail on
# paste. What the guard's `runnable` test actually excludes (and what it still
# lets through, a redirection and a command substitution among them) is written
# out at the escape block in guard-git-push.mjs; the cases below pin the three
# shapes named here, not the whole of it. The colon after `uživateli` is the
# discriminator: with a command it reads `uživateli: …`, without one it reads
# `uživateli.`.
# ---------------------------------------------------------------------------
$rFragment = Test-Cmd 'export MB_HUMAN_PUSH=1 && git push origin develop'
Assert-Match $rFragment 'permissionDecision.*deny' 'zbytek po odstranění výjimky: zamítnutí platí dál'
Assert-NotMatch $rFragment 'uživateli: ' 'zbytek po odstranění výjimky: nespustitelný fragment se nepodává'

$rBothNames = Test-Cmd 'MB_HUMAN_PUSH=1 UMS_ALLOW_SHARED_PUSH=1 git push origin develop'
Assert-Match $rBothNames 'permissionDecision.*deny' 'obě jména naráz: zamítnutí platí dál'
Assert-NotMatch $rBothNames 'uživateli: ' 'obě jména naráz: nepodává se příkaz, ve kterém zbyla druhá výjimka'

$rContinuation = Test-Cmd "MB_HUMAN_PUSH=1 \`ngit push origin develop"
Assert-Match $rContinuation 'permissionDecision.*deny' 'pokračovací lomítko: zamítnutí platí dál'
Assert-NotMatch $rContinuation 'uživateli: ' 'pokračovací lomítko: nepodává se příkaz se zbylým lomítkem'

# LOAD-BEARING POSITIVE: the clean case must still hand a command over, or the
# three assertions above would be satisfied by never handing one at all.
Assert-Match (Test-Cmd 'MB_HUMAN_PUSH=1 git push origin develop') 'uživateli: ' 'čistý případ příkaz podá'

# Fix round 3, Minor C: the remainder has to BE a `git push …` to the end of
# the string, not merely start with one. A prefix test lets everything APPENDED
# to the push ride along into the handed command — a chained second command, or
# a whole second line — which is the part the human would paste and run without
# noticing.
$rTrailingChain = Test-Cmd 'MB_HUMAN_PUSH=1 git push origin develop && echo hotovo'
Assert-Match $rTrailingChain 'permissionDecision.*deny' 'přívěsek za pushem: zamítnutí platí dál'
Assert-NotMatch $rTrailingChain 'uživateli: ' 'přívěsek za pushem: nepodává se příkaz i s navěšeným druhým'

$rTrailingLine = Test-Cmd "MB_HUMAN_PUSH=1 git push origin develop`necho hotovo"
Assert-Match $rTrailingLine 'permissionDecision.*deny' 'druhý řádek za pushem: zamítnutí platí dál'
Assert-NotMatch $rTrailingLine 'uživateli: ' 'druhý řádek za pushem: nepodává se dvouřádkový blok'

# LOAD-BEARING NEGATIVES for the widened pattern: it must still key on the
# VALUE 1, and must not fire on a different variable that merely ends in the
# same name.
foreach ($c in @(
    'MB_HUMAN_PUSH="0" git push origin feature/ums-1-alfa',
    "MB_HUMAN_PUSH='0' git push origin feature/ums-1-alfa",
    'MB_HUMAN_PUSH=10 git push origin feature/ums-1-alfa',
    'NOT_MB_HUMAN_PUSH=1 git push origin feature/ums-1-alfa'
)) { Assert-Eq (Test-Cmd $c) '' "výjimkou není: $c" }
# ... and the target does not matter: writing the variable IS the violation,
# so an UNPROTECTED branch (which would otherwise pass) is denied too
Assert-Match (Test-Cmd 'MB_HUMAN_PUSH=1 git push origin feature/ums-1-alfa') 'permissionDecision.*deny' 'výjimka je porušením i u nechráněné větve'
# LOAD-BEARING NEGATIVE for the pattern: a different value is not the escape,
# so the very same command on an unprotected branch must still pass
Assert-Eq (Test-Cmd 'MB_HUMAN_PUSH=0 git push origin feature/ums-1-alfa') '' 'jiná hodnota než 1 výjimkou není'
# order preserved: --no-verify is judged BEFORE the escape, so its own (more
# specific) reason is the one the agent gets
Assert-Match (Test-Cmd 'MB_HUMAN_PUSH=1 git push --no-verify origin develop') 'no-verify' 'výjimka nepřebíjí dřívější kontrolu --no-verify'
# the rejection of a plain push hands over the command instead: the moment of
# integration belongs to the human, and the hook then lets that push through
# by its own content rule when the commits are already published
Assert-Match (Test-Cmd 'git push origin develop') '! git push origin HEAD:develop' 'zamítnutí podává uživateli hotový příkaz bez výjimky'

# ---------------------------------------------------------------------------
# bare push resolves the current branch from cwd when it can
# ---------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init -b develop $tmp | Out-Null
Assert-Match (Test-Cmd 'git push' $tmp) 'permissionDecision.*deny' 'bare push na develop je zamítnut'
& git -C $tmp checkout -q -b feature/ums-9-x
Assert-Eq (Test-Cmd 'git push' $tmp) '' 'bare push na tiketové větvi projde'
Remove-Item -Recurse -Force $tmp

# unresolvable current branch (detached HEAD): a RECOGNIZED push that is still
# ALLOWED, because it hands the guard no target to judge at all. Round 1 denied
# this case, round 2 allowed it as part of a blanket fail-open posture, and
# task 6 kept it while making the rest fail-closed: an unguessable branch names
# no protected target, and denying would block legitimate work from a detached
# HEAD (this very session pushes from one).
$tmp2 = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp2 | Out-Null
& git init -q -b wip $tmp2 | Out-Null
& git -C $tmp2 config user.email 'test@example.com'
& git -C $tmp2 config user.name 'Test'
'x' | Out-File -FilePath (Join-Path $tmp2 'f.txt') -Encoding utf8
& git -C $tmp2 add -A
& git -C $tmp2 commit -q -m init
$sha = (& git -C $tmp2 rev-parse HEAD).Trim()
& git -C $tmp2 checkout -q $sha
Assert-Eq (Test-Cmd 'git push' $tmp2) '' 'bare push v odpojeném HEAD teď projde (nejistota = allow, ne deny)'
Remove-Item -Recurse -Force $tmp2

# ---------------------------------------------------------------------------
# unparseable input must not block
# ---------------------------------------------------------------------------
Assert-Eq (Invoke-Hook 'not json') '' 'nerozparsovatelný vstup neblokuje'

# ---------------------------------------------------------------------------
# hook registration must cover every tool a session can push through
# ---------------------------------------------------------------------------
# Registrace hooku je konfigurace, ne kód - ale díra v ní znamená, že guard
# na polovinu volání vůbec nevystřelí. Sezení s CLAUDE_CODE_USE_POWERSHELL_TOOL=1
# jede přes PowerShell tool; s matcherem jen na Bash by push tudy prošel bez
# jediné kontroly.
$settingsPath = Join-Path $PSScriptRoot '..\..\settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$bashMatchers = @($settings.hooks.PreToolUse | Where-Object {
    ($_.hooks | Where-Object { $_.command -match 'guard-git-push' })
} | ForEach-Object { $_.matcher })
Assert-Eq @($bashMatchers).Count 1 'guard-git-push je registrovaný právě jednou'
Assert-Match $bashMatchers[0] 'Bash' 'matcher guardu pokrývá Bash tool'
Assert-Match $bashMatchers[0] 'PowerShell' 'matcher guardu pokrývá i PowerShell tool'

# ---------------------------------------------------------------------------
# FAIL-CLOSED for a recognized `push`: where a `git` token sits at a command
# position and the guard cannot read the invocation, the default answer is
# deny; the blocks below pin the conditions that hold that answer back. The
# tightening reaches no further than that subcommand — `fetch` and every other
# subcommand keep the answer they had — otherwise false alarms would multiply
# on ordinary document text (this guard once denied writing up the very design
# of this plan).
# ---------------------------------------------------------------------------
$r = Test-Cmd 'git push --mirror origin'
Assert-Match $r 'permissionDecision.*deny' 'guard zamítne rozpoznaný push s neznámým přepínačem'
Assert-Match $r 'neumím spolehlivě přečíst' 'zamítnutí říká, že push nešel přečíst, ne že je větev chráněná'

$r = Test-Cmd 'git push origin a:b c:d'
Assert-Match $r 'permissionDecision.*deny' 'guard zamítne rozpoznaný push s víc refspecy, kterým nerozumí'

# non-plain remote — the third converted return; a URL is not a remote NAME
$r = Test-Cmd 'git push https://example.com/evil.git HEAD:feature/x'
Assert-Match $r 'permissionDecision.*deny' 'guard zamítne rozpoznaný push s nesrozumitelným jménem remote'

# Control case: an obviously harmless push to an unprotected branch must keep
# passing, otherwise fail-closed would be denying everything and the
# assertions above would prove nothing.
$r = Test-Cmd 'git push -u origin feature/x'
Assert-Eq $r '' 'kontrola: srozumitelný push na nechráněnou větev prochází'

# Residual pass-through admitted in the design: a shape whose `git` token is
# not recognized at all never reaches the fail-closed branch. `bash -c '…'` is
# exactly the case that defeated this guard in adversarial review, and this
# plan does not close it.
$r = Test-Cmd "bash -c 'git push --mirror origin'"
Assert-Eq $r '' 'zbytkový průchod: nerozpoznaný tvar guard nezamítá'

# ---------------------------------------------------------------------------
# THE COMMAND-POSITION BOUNDARY (fix round 1, Important 1). Fail-closed does
# not fire on the words `git push` alone; this block and the next pin two of
# the conditions in front of it, each from BOTH sides.
#
# Question 1 — is this `git` token an invocation at all? Only at index 0,
# after a shell control operator, or after a NAME=value env assignment.
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'echo git push --mirror') '' 'command position: `git` po `echo` není příkaz, fail-closed nevystřelí'
Assert-Eq (Test-Cmd "cat <<'EOF'`ngit push --force origin develop`nEOF") '' 'command position: řádek uvnitř heredocu není příkaz'
# ... and THE LIMIT of what command position buys, pinned because two rounds of
# header prose in these files put `echo` in the fail-open group and no
# assertion contradicted them: command position gates the FAIL-CLOSED arm, not
# the reading of a destination. The same `echo` with a readable protected
# destination is denied, on the protected-target path.
Assert-Match (Test-Cmd 'echo git push origin develop') 'permissionDecision.*deny' 'command position drží jen fail-closed větev: čitelný chráněný cíl se posuzuje i v echu'
# ACCEPTED COST, pinned so it is visible rather than folklore: the tokenizer
# splits on whitespace only, so a separator GLUED to the previous token hides
# the command position just as a newline does. Promoting either to a separator
# would re-open the heredoc case above, which is the case this rule exists for.
Assert-Eq (Test-Cmd 'cd /repo; git push --mirror origin') '' 'přiznaná mezera: přilepený oddělovač skryje command position'
# ... and the three shapes that DO sit at a command position still deny
Assert-Match (Test-Cmd 'git push --mirror origin') 'permissionDecision.*deny' 'command position: index 0 je příkaz'
Assert-Match (Test-Cmd 'cd /repo && git push --mirror origin') 'permissionDecision.*deny' 'command position: po řídicím operátoru je příkaz'
Assert-Match (Test-Cmd 'FOO=bar git push --mirror origin') 'permissionDecision.*deny' 'command position: po přiřazení proměnné prostředí je příkaz'

# ---------------------------------------------------------------------------
# Question 2 — was the thing it could not read even IN the command? A token
# carrying shell EXPANSION names a remote or ref that is simply not in the
# string, the same state as `bash -c '…'` above, not "a literal I refuse to
# read". Asked per problem, never about the invocation as a whole: it excuses
# the ONE problem those tokens caused, and the `omluvený problém nezakrývá
# neomluvený` cases below are where that distinction is pinned. QUOTING is not
# expansion either, so the obvious evasion (quote the branch name) stays
# closed — that pair is the point here.
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'git push "$remote" "$branch"') '' 'expanze: skutečný push s proměnnými se nezamítá, guard cíl prostě nezná'
Assert-Eq (Test-Cmd 'git push $remote $branch') '' 'expanze: totéž bez uvozovek'
Assert-Match (Test-Cmd 'git push origin "develop"') 'permissionDecision.*deny' 'úniková cesta zavřená: uvozovky kolem jména větve expanze nejsou'
Assert-Match (Test-Cmd 'git push "origin" "release/2026.1"') 'permissionDecision.*deny' 'úniková cesta zavřená: uvozovky kolem obojího expanze nejsou'

# ---------------------------------------------------------------------------
# Fix round 2, Important A. Expansion excuses the token it actually made
# unreadable — NOT the whole invocation. One `$` anywhere on the line must not
# buy silence about a destination that is written out in plain text; before
# this fix all three of these were ALLOW.
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git push $r develop') 'permissionDecision.*deny' 'expanze: nečitelný remote nemaže čitelný chráněný cíl'
Assert-Match (Test-Cmd 'git push --mirror $r') 'permissionDecision.*deny' 'expanze: nečitelný remote neomlouvá --mirror'
Assert-Match (Test-Cmd 'git push origin "develop" $x') 'permissionDecision.*deny' 'expanze: refspec navíc, který přečíst nejde, nemaže čitelný chráněný cíl'
# controls: the same shapes without any expansion must keep denying, so the
# three above cannot be passing for a reason unrelated to the fix
Assert-Match (Test-Cmd 'git push --mirror origin') 'permissionDecision.*deny' 'kontrola: --mirror bez expanze zůstává zamítnutý'
Assert-Match (Test-Cmd 'git push origin develop') 'permissionDecision.*deny' 'kontrola: prostý push na chráněnou větev zůstává zamítnutý'
# ... and THE BOUNDARY: where the destination genuinely cannot be read, the
# guard stays silent. Same epistemic state as `bash -c '…'`, which the design
# names and accepts, and the pre-push hook still resolves the real refs.
Assert-Eq (Test-Cmd 'R=origin; B=develop; git push $R $B') '' 'expanze: když cíl opravdu přečíst nejde, guard mlčí'

# ---------------------------------------------------------------------------
# Fix round 3, Important A. Problems are judged ONE BY ONE against their own
# causing tokens, so an EXCUSED problem cannot shadow an unexcused one. Both
# shapes below carry expansion in the remote — excused — and an entirely
# expansion-free defect in the refspecs, which is not: the second is a wildcard
# push into every branch of the remote, the exact "cannot rule out a protected
# branch" case the fail-closed arm exists for. Recording only the FIRST problem
# let both through.
#
# The boundary asserted just above is what these must NOT disturb: where EVERY
# problem is expansion-caused, the guard still stays silent.
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git push $r a:b c:d') 'permissionDecision.*deny' 'expanze: omluvený problém nezakrývá neomluvený (víc refspeců)'
Assert-Match (Test-Cmd 'git push $r refs/heads/*:refs/heads/*') 'permissionDecision.*deny' 'expanze: omluvený problém nezakrývá neomluvený (žolík do všech větví)'

# ---------------------------------------------------------------------------
# Fix round 5, Important C. Round 3 stopped an excused problem from shadowing
# an unexcused one; the masking that survived was INSIDE a single problem and
# in the arm that recorded it. Every not-plain refspec went into ONE problem
# carrying all of those tokens, and the excuse test is `some`, so appending a
# single expanded token bought silence about the rest of the list — a wildcard
# push into every branch of the remote among them. The arity defect ("more
# than one refspec") sat in an `else` arm behind that same list, so any
# not-plain token suppressed it outright. Both shapes below were ALLOW.
#
# Neither is covered by the assertions above: the protected-target path cannot
# reach them (no readable protected destination) and the round-3 pair carries
# its expansion in the REMOTE, a different token from a different problem.
# ---------------------------------------------------------------------------
Assert-Match (Test-Cmd 'git push origin refs/heads/*:refs/heads/* $x') 'permissionDecision.*deny' 'expanze: přilepený $x neomlouvá žolíka do všech větví'
Assert-Match (Test-Cmd 'git push origin a:b c:d $x') 'permissionDecision.*deny' 'expanze: přilepený $x neomlouvá víc refspeců vedle sebe'
# controls: the same shapes without the appended expansion denied before this
# fix and must keep denying after it, or the two above prove nothing
Assert-Match (Test-Cmd 'git push origin refs/heads/*:refs/heads/*') 'permissionDecision.*deny' 'kontrola: žolík do všech větví zůstává zamítnutý i bez expanze'
Assert-Match (Test-Cmd 'git push origin a:b c:d') 'permissionDecision.*deny' 'kontrola: víc refspeců zůstává zamítnutých i bez expanze'
# ... and THE BOUNDARY this fix must not disturb. Where not one destination can
# be read, the guard still says nothing — including when there are several such
# tokens, which is the case that separates "I can see two refspecs" from
# "I can see nothing and there happen to be two tokens".
Assert-Eq (Test-Cmd 'git push $r $a $b') '' 'hranice: víc refspeců, ze kterých ani jeden přečíst nejde, guard nezamítá'
Assert-Eq (Test-Cmd 'R=origin; B=develop; git push $R $B') '' 'hranice: cíl, který přečíst nejde, guard dál nezamítá'
Assert-Eq (Test-Cmd 'git push "$remote" "$branch"') '' 'hranice: push s proměnnými dál prochází'

# The exit-code/stderr half: a deny must be a CLEAN deny, not a crash that
# merely happens to print JSON (or, worse, nothing).
$rFull = Test-CmdFull 'git push --mirror origin'
Assert-Eq $rFull.Code 0 'exit 0: fail-closed zamítnutí nepadá, jen zamítá'
Assert-Eq $rFull.Err '' 'žádný stderr: fail-closed zamítnutí nevyhodí nezachycenou výjimku'

# The unresolvable current branch (detached HEAD) deliberately KEEPS its
# fail-open answer and is asserted further up, unchanged: an unguessable
# branch is not a recognized protected target, and denying there would block
# legitimate work from a detached HEAD.


# ---------------------------------------------------------------------------
# FINAL WHOLE-BRANCH REVIEW, Critical: THE ESCAPE CONTAINMENT IN POWERSHELL'S
# SPELLING. Everything above speaks POSIX shell, but the guard is registered on
# `Bash|PowerShell` (asserted further up) because this fork's sessions run on
# the PowerShell tool. `$env:NAME='1'; git push …` sets the very environment
# `git` inherits, and on the hook side the escape lifts the WHOLE guard — the
# protected-branch rule, the deletion ban and the force-push ban alike.
#
# Measured against the real hook with `tool_name: "PowerShell"` BEFORE the fix:
#   $env:<escape>='1'; git push origin HEAD:develop         -> deny, but by the
#                                                              TARGET rule, not
#                                                              by the escape one
#   $env:<escape>='1'; git push --force origin HEAD:develop -> ALLOW
#   $env:<escape>='1'; git push --force origin feature/x    -> ALLOW
# Both ALLOWs share one mechanism and cost two different things. The mechanism:
# the bad flag makes a `problem`, and the assignment statement is neither a
# CONTROL token nor a NAME=value assignment, so command position is false —
# which suppresses the fail-closed arm. The cost differs with the target. The
# `HEAD:develop` one is an agent force-pushing a PROTECTED branch through both
# layers in ordinary syntax; there the same false command position suppresses
# the protected-target deny as well. The `feature/x` one targets a branch that
# is NOT protected, so there is no protected-target deny to suppress: it is a
# history rewrite of the agent's own published branch, which the pre-push hook's
# force-push ban would have refused had the escape not lifted its whole guard.
# ---------------------------------------------------------------------------
foreach ($c in @(
    "`$env:MB_HUMAN_PUSH='1'; git push origin develop",
    "`$env:MB_HUMAN_PUSH=`"1`"; git push origin develop",
    "`$env:MB_HUMAN_PUSH=1; git push origin develop",
    "`${env:MB_HUMAN_PUSH}='1'; git push origin feature/ums-1-alfa",
    "`$Env:MB_HUMAN_PUSH = '1'; git push origin feature/ums-1-alfa",
    'Set-Item -Path Env:MB_HUMAN_PUSH 1; git push origin feature/ums-1-alfa',
    'Set-Item Env:\MB_HUMAN_PUSH -Value 1; git push origin feature/ums-1-alfa',
    "[Environment]::SetEnvironmentVariable('MB_HUMAN_PUSH','1'); git push origin feature/ums-1-alfa"
)) {
    $rPs = Test-CmdPs $c
    Assert-Match $rPs 'permissionDecision.*deny' "výjimka rozpoznaná i v PowerShellovém zápisu: $c"
    # ... and the deny must be the ESCAPE's. Half these targets are `develop`,
    # which the shared-branch rule would reject anyway, so without this the
    # table would pass without the pattern recognizing the spelling at all.
    Assert-Match $rPs 'vědomá výjimka ČLOVĚKA' "zamítnutí patří výjimce, ne sdílené větvi ani nečitelnosti: $c"
    Assert-Match $rPs 'MB_HUMAN_PUSH' "zamítnutí jmenuje proměnnou, kvůli které padlo: $c"
}
# the transitional old name, in PowerShell's spelling too, and the message must
# name the one that ACTUALLY triggered it
$rPsOld = Test-CmdPs "`$env:UMS_ALLOW_SHARED_PUSH='1'; git push origin develop"
Assert-Match $rPsOld 'permissionDecision.*deny' 'PowerShell: staré jméno výjimky je zamítnuté taky'
Assert-Match $rPsOld 'UMS_ALLOW_SHARED_PUSH' 'PowerShell: zamítnutí jmenuje staré jméno, které ho spustilo'

# THE THREE MEASURED CASES from the review, each an ALLOW before this fix. The
# first one denied even before, but on the TARGET rule — so it is asserted on
# the escape's own reason, otherwise it would go green without the fix.
foreach ($c in @(
    "`$env:MB_HUMAN_PUSH='1'; git push origin HEAD:develop",
    "`$env:MB_HUMAN_PUSH='1'; git push --force origin HEAD:develop",
    "`$env:MB_HUMAN_PUSH='1'; git push --force origin feature/x"
)) {
    $rMeasured = Test-CmdPs $c
    Assert-Match $rMeasured 'permissionDecision.*deny' "měřený obchvat je zamítnutý: $c"
    Assert-Match $rMeasured 'vědomá výjimka ČLOVĚKA' "měřený obchvat padá na výjimce, ne na cíli: $c"
}

# ---------------------------------------------------------------------------
# THE POWERSHELL RESIDUAL, closed after the final whole-branch review. Two more
# spellings reached a child process's environment and were measured ALLOW
# against the guard as it stood at 312737b — after which the hook would have
# lifted its WHOLE guard on the push riding behind them:
#
#   [System.Environment]::SetEnvironmentVariable('<escape>','1'); git push --force origin feature/x
#   New-Item -Path Env:<escape> -Value 1;                         git push --force origin feature/x
#
# The first slipped past because the pattern read `[Environment]::` only, while
# the fully-qualified spelling is if anything the more common one; the second
# construct was not covered at all. NEITHER IS A NEW CONSTRUCT CLASS, and that
# is why both inherit the value-free rule stated in guard-git-push.mjs rather
# than a rule of their own: `[System.Environment]` and `[Environment]` are the
# same type, and `New-Item` is `Set-Item`'s sibling on the Env: drive. Writing
# the construct at the escape's name IS the violation — see the `-Value 0`
# rows in the negatives below, which deny for exactly that reason, on both
# verbs.
#
# `New-Item` is read as a GAP up to `Env:NAME` because its argument order is
# free: `-Path` is positional, the value may be positional or `-Value`, and the
# name may be split off into `-Name`. The gap is whole tokens on one line and
# stops at `;`, `|` and `&`; the negatives below pin that at `;` and at a line
# break, the two shapes an agent would actually write.
# ---------------------------------------------------------------------------
foreach ($c in @(
    "[System.Environment]::SetEnvironmentVariable('MB_HUMAN_PUSH','1'); git push --force origin feature/x",
    '[System.Environment]::SetEnvironmentVariable("MB_HUMAN_PUSH","1"); git push --force origin feature/x',
    "[system.environment]::SetEnvironmentVariable('MB_HUMAN_PUSH','1'); git push --force origin feature/x",
    "[System.Environment]::SetEnvironmentVariable('UMS_ALLOW_SHARED_PUSH','1'); git push --force origin feature/x",
    'New-Item -Path Env:MB_HUMAN_PUSH -Value 1; git push --force origin feature/x',
    'New-Item -Path Env:\MB_HUMAN_PUSH -Value 1; git push --force origin feature/x',
    'New-Item Env:MB_HUMAN_PUSH 1; git push --force origin feature/x',
    'New-Item -Path Env:MB_HUMAN_PUSH 1; git push --force origin feature/x',
    'New-Item -Value 1 -Path Env:MB_HUMAN_PUSH; git push --force origin feature/x',
    'New-Item -Path Env: -Name MB_HUMAN_PUSH -Value 1; git push --force origin feature/x',
    'New-Item -Path Env:UMS_ALLOW_SHARED_PUSH -Value 1; git push --force origin feature/x'
)) {
    $rNew = Test-CmdPs $c
    Assert-Match $rNew 'permissionDecision.*deny' "zbytkové PowerShellové hláskování je zamítnuté: $c"
    # `feature/x` is deliberately NOT protected in any of these, so nothing but
    # the escape rule can produce the deny — without this line the table could
    # pass on the shared-branch rule instead.
    Assert-Match $rNew 'vědomá výjimka ČLOVĚKA' "zamítnutí patří výjimce, ne cíli ani nečitelnosti: $c"
}
# ... and the deny names the variable that ACTUALLY matched, the deprecated one
# included — the new alternatives capture the name in a group of their own for
# exactly this.
Assert-Match (Test-CmdPs "[System.Environment]::SetEnvironmentVariable('UMS_ALLOW_SHARED_PUSH','1'); git push --force origin feature/x") 'UMS_ALLOW_SHARED_PUSH' 'System.Environment: zamítnutí jmenuje staré jméno, které ho spustilo'
Assert-Match (Test-CmdPs 'New-Item -Path Env:UMS_ALLOW_SHARED_PUSH -Value 1; git push --force origin feature/x') 'UMS_ALLOW_SHARED_PUSH' 'New-Item: zamítnutí jmenuje staré jméno, které ho spustilo'
Assert-Match (Test-CmdPs 'New-Item -Path Env:MB_HUMAN_PUSH -Value 1; git push --force origin feature/x') 'MB_HUMAN_PUSH' 'New-Item: zamítnutí jmenuje proměnnou, kvůli které padlo'

# LOAD-BEARING NEGATIVES for the two constructs above, on the same three axes
# the table further down uses — and they are what separates a real widening
# from an alternation that matches almost anything, which positive rows alone
# would never catch.
#
# NAME PREFIX / SUFFIX and the name boundary: the pattern keys on the escape's
# name, not on a substring of it.
foreach ($c in @(
    'New-Item -Path Env:NOT_MB_HUMAN_PUSH -Value 1; git push origin feature/ums-1-alfa',
    'New-Item -Path Env:MB_HUMAN_PUSH_TOO -Value 1; git push origin feature/ums-1-alfa',
    'New-Item -Path Env:MB_HUMAN_PUSHX -Value 1; git push origin feature/ums-1-alfa',
    'New-Item -Path Env: -Name MB_HUMAN_PUSH_TOO -Value 1; git push origin feature/ums-1-alfa',
    "[System.Environment]::SetEnvironmentVariable('NOT_MB_HUMAN_PUSH','1'); git push origin feature/ums-1-alfa",
    "[System.Environment]::SetEnvironmentVariable('MB_HUMAN_PUSH_TOO','1'); git push origin feature/ums-1-alfa",
    "[System.Environment]::SetEnvironmentVariable('MB_HUMAN_PUSHX','1'); git push origin feature/ums-1-alfa"
)) { Assert-Eq (Test-CmdPs $c) '' "jiné jméno není výjimka: $c" }
# TERMINATOR — what has to stand around the name for the construct to be a
# write of THIS variable at all: the `Env:` drive for the cmdlet, the quoted
# NAME argument (first, not second) for the method, and the statement separator
# the New-Item gap must not cross.
foreach ($c in @(
    'New-Item -Path Foo:MB_HUMAN_PUSH -Value 1; git push origin feature/ums-1-alfa',
    'New-Item -Path C:\tmp\MB_HUMAN_PUSH.txt -Value 1; git push origin feature/ums-1-alfa',
    'New-Item -Path C:\tmp\a.txt; Get-Content Env:MB_HUMAN_PUSH',
    "New-Item -Path C:\tmp\a.txt`nGet-Content Env:MB_HUMAN_PUSH",
    'Get-Item Env:MB_HUMAN_PUSH; git push origin feature/ums-1-alfa',
    "[System.Environment]::GetEnvironmentVariable('MB_HUMAN_PUSH'); git push origin feature/ums-1-alfa",
    "[System.Environment]::SetEnvironmentVariable('OTHER','MB_HUMAN_PUSH'); git push origin feature/ums-1-alfa",
    "[System.Foo]::SetEnvironmentVariable('MB_HUMAN_PUSH','1'); git push origin feature/ums-1-alfa"
)) { Assert-Eq (Test-CmdPs $c) '' "konstrukce nezapisuje tuhle proměnnou: $c" }
# VALUE — and here the answer is DENY, not allow, which is the ONE axis where
# these two constructs part company with `$env:NAME=`. That one has a READ
# spelling (`echo $env:NAME`), so it has to carry the value to tell a write
# from a read; `Set-Item`/`New-Item`/`SetEnvironmentVariable` have none, so the
# construct at the escape's name is the write. Asserted on both verbs and both
# type spellings side by side, because the value-free rule is inherited, not
# newly invented — and because a value-carrying pattern would have waved
# through `-Value $x`, a value this tokenizer cannot read at all.
foreach ($c in @(
    'New-Item -Path Env:MB_HUMAN_PUSH -Value 0; git push origin feature/ums-1-alfa',
    'New-Item -Path Env:MB_HUMAN_PUSH -Value "0"; git push origin feature/ums-1-alfa',
    'New-Item -Path Env:MB_HUMAN_PUSH -Value 10; git push origin feature/ums-1-alfa',
    # the value the value-free rule is actually FOR: an expansion this
    # tokenizer cannot read, which a value-carrying pattern would wave through
    'New-Item -Path Env:MB_HUMAN_PUSH -Value $x; git push --force origin feature/x',
    'Set-Item -Path Env:MB_HUMAN_PUSH -Value 0; git push origin feature/ums-1-alfa',
    "[System.Environment]::SetEnvironmentVariable('MB_HUMAN_PUSH','0'); git push origin feature/ums-1-alfa",
    '[System.Environment]::SetEnvironmentVariable("MB_HUMAN_PUSH","0"); git push origin feature/ums-1-alfa',
    "[System.Environment]::SetEnvironmentVariable('MB_HUMAN_PUSH',10); git push origin feature/ums-1-alfa",
    "[Environment]::SetEnvironmentVariable('MB_HUMAN_PUSH','0'); git push origin feature/ums-1-alfa"
)) { Assert-Match (Test-CmdPs $c) 'vědomá výjimka ČLOVĚKA' "u konstrukce bez čtecího tvaru nerozhoduje hodnota: $c" }
# CONTROL for the whole New-Item group: an ordinary environment variable written
# the same way is not the escape, so these rows cannot be green because every
# New-Item is denied.
Assert-Eq (Test-CmdPs 'New-Item -Path Env:FOO -Value 1; git push origin feature/ums-1-alfa') '' 'kontrola: New-Item na cizí proměnnou prochází'

# LOAD-BEARING NEGATIVES for the PowerShell pattern, on the same three axes the
# POSIX table uses. Without them the pattern could have been widened into a bare
# name match, which is the one repair this containment must NOT take.
foreach ($c in @(
    # different VALUE
    "`$env:MB_HUMAN_PUSH='0'; git push origin feature/ums-1-alfa",
    "`$env:MB_HUMAN_PUSH=`"0`"; git push origin feature/ums-1-alfa",
    # different TERMINATOR after the value
    "`$env:MB_HUMAN_PUSH=10; git push origin feature/ums-1-alfa",
    "`$env:MB_HUMAN_PUSH='1'x; git push origin feature/ums-1-alfa",
    # different name PREFIX / suffix
    "`$env:NOT_MB_HUMAN_PUSH='1'; git push origin feature/ums-1-alfa",
    "`$env:MB_HUMAN_PUSH_TOO='1'; git push origin feature/ums-1-alfa"
)) { Assert-Eq (Test-CmdPs $c) '' "výjimkou v PowerShellu není: $c" }

# ... and the READ spelling is not the write spelling. `$env:NAME` is also how
# PowerShell READS the variable, which is why this alternative (unlike
# `Set-Item Env:` and `SetEnvironmentVariable`, which have no read spelling)
# has to carry the value at all.
Assert-Eq (Test-CmdPs "if (`$env:MB_HUMAN_PUSH -eq '1') { git status }") '' 'čtení proměnné není její nastavení'

# THE PROPERTY THE BARE-NAME REPAIR WOULD HAVE COST, asserted rather than left
# to the comment that promises it: searching the layer's own sources for the
# escape's name is ordinary read-only work and must keep passing, on both tools.
Assert-Eq (Test-Cmd 'grep -rn MB_HUMAN_PUSH ums/') '' 'hledání jména výjimky ve zdrojích vrstvy projde (Bash)'
Assert-Eq (Test-CmdPs 'Select-String -Pattern MB_HUMAN_PUSH -Path ums/.claude/hooks/pre-push') '' 'hledání jména výjimky ve zdrojích vrstvy projde (PowerShell)'

# The POSIX spellings must keep denying EXACTLY as before — the widening is
# additive, and a shared `HUMAN_ESCAPE_RE` is easy to break while extending it.
foreach ($c in @(
    'MB_HUMAN_PUSH=1 git push origin HEAD:develop',
    'MB_HUMAN_PUSH=1 git push --force origin HEAD:develop',
    'MB_HUMAN_PUSH="1" git push origin develop',
    'UMS_ALLOW_SHARED_PUSH=1 git push origin develop'
)) {
    $rStill = Test-Cmd $c
    Assert-Match $rStill 'vědomá výjimka ČLOVĚKA' "bashové hláskování zamítá dál: $c"
}
# ... including the hand-over, which is what separates "still denies" from
# "still denies for the right reason and still helps"
Assert-Match (Test-Cmd 'MB_HUMAN_PUSH=1 git push origin develop') 'uživateli: ' 'bashové hláskování dál podává příkaz bez výjimky'

# THE HAND-OVER FALLS BACK for a PowerShell shape. Stripping `$env:NAME='1';`
# out of a command is textual surgery on a statement, not on an argument-list
# prefix, so the guard hands over nothing and says so in the generic sentence.
$rPsHandover = Test-CmdPs "`$env:MB_HUMAN_PUSH='1'; git push origin develop"
Assert-Match $rPsHandover 'permissionDecision.*deny' 'PowerShellový tvar: zamítnutí platí'
Assert-NotMatch $rPsHandover 'uživateli: ' 'PowerShellový tvar: příkaz se nepodává, jde generická věta'
# ... and the same fallback catches a remainder that would RE-SET the escape in
# PowerShell's spelling once the POSIX one was stripped out of it. Without the
# PowerShell half of that test the guard would hand a human a command carrying
# the escape it had just refused.
$rMixed = Test-Cmd "MB_HUMAN_PUSH=1 git push origin `$env:MB_HUMAN_PUSH=1"
Assert-Match $rMixed 'permissionDecision.*deny' 'smíšené hláskování: zamítnutí platí'
Assert-NotMatch $rMixed 'uživateli: ' 'smíšené hláskování: nepodává se příkaz, ve kterém zbyla PowerShellová výjimka'

# CONTROLS on the PowerShell tool, so the table above cannot be green because
# the guard denies everything arriving with that tool name — or allows it.
Assert-Match (Test-CmdPs 'git push origin develop') 'sdílená větev' 'kontrola: pravidlo o sdílené větvi platí i na PowerShell toolu'
Assert-Eq (Test-CmdPs 'git push origin feature/ums-1-alfa') '' 'kontrola: srozumitelný push na nechráněnou větev prochází i na PowerShell toolu'

# ---------------------------------------------------------------------------
# SHELL REDIRECTION IS NOT A REFSPEC (see REDIR_RE in the guard). A redirection
# token used to be collected as an argument, fail REFSPEC_RE and become an
# expansion-free problem, so the fail-closed arm denied the agent's own
# ticket-branch push the moment the command carried ordinary plumbing — the
# one command class the publication rule most wants run, and for `> /tmp/out`
# under a reason ("víc nebo poškozené refspecy") that named a cause the
# command did not have. Measured DENY before the fix, all four:
#   git push 2>&1 | tail -3
#   git push origin feature/ums-1-alfa 2>&1 | tail -3
#   git push origin feature/ums-1-alfa > /tmp/out.txt
#   (the same, on the PowerShell tool)
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa 2>&1 | tail -3') '' 'přesměrování: pipe za pushem tiketové větve projde'
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa > /tmp/out.txt') '' 'přesměrování: výstup do souboru projde'
Assert-Eq (Test-CmdPs 'git push origin feature/ums-1-alfa 2>&1 | Select-Object -Last 3') '' 'přesměrování: totéž na PowerShell toolu projde'
Assert-Eq (Test-CmdPs 'git push origin feature/ums-1-alfa > /tmp/out.txt') '' 'přesměrování: výstup do souboru projde i na PowerShell toolu'
# ... and the spellings the operator can take, each stepped over rather than
# read as an argument. `<<` is NOT among them on purpose — see the heredoc
# assertion further down in this block.
foreach ($c in @(
    'git push origin feature/ums-1-alfa 2> err.txt',
    'git push origin feature/ums-1-alfa 2>> err.txt',
    'git push origin feature/ums-1-alfa >> log.txt',
    'git push origin feature/ums-1-alfa 2>/dev/null',
    'git push origin feature/ums-1-alfa &> all.txt',
    'git push origin feature/ums-1-alfa &>> all.txt',
    'git push origin feature/ums-1-alfa 1>&2',
    'git push origin feature/ums-1-alfa < /dev/null'
)) { Assert-Eq (Test-Cmd $c) '' "přesměrování: tvar operátoru se přeskakuje: $c" }

# THE REDIRECTION TARGET IS A FILE NAME, NOT A REFSPEC. `> develop` writes a
# file called develop; a real shell never hands that word to git, so the guard
# must not read it as a push to the protected branch. Both spacings, because
# they take the two different arms of REDIR_RE (target in the next token vs.
# glued to the operator).
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa > develop') '' 'přesměrování: cíl přesměrování není refspec (oddělený)'
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa >develop') '' 'přesměrování: cíl přesměrování není refspec (přilepený)'

# AND WHAT A REDIRECTION MUST NOT DO IS HIDE A TARGET BEHIND ITSELF. In bash a
# redirection may stand anywhere and is REMOVED from the argument list, so
# `git push origin 2>&1 develop` really does push `develop` — the tokens after
# it are still arguments. This is why redirections are stepped over rather than
# treated as CONTROL: ending the argument list at `2>&1` would have opened a
# one-token way to hide a protected branch from the guard.
Assert-Match (Test-Cmd 'git push origin 2>&1 develop') 'sdílená větev' 'přesměrování neschovává chráněný cíl za sebou'
Assert-Match (Test-CmdPs 'git push origin 2>&1 develop') 'sdílená větev' 'přesměrování neschovává chráněný cíl ani na PowerShell toolu'
Assert-Match (Test-Cmd 'git push origin develop 2>&1 | tail -3') 'sdílená větev' 'přesměrování před pipou nemaže chráněný cíl'
Assert-Match (Test-CmdPs 'git push origin develop > /tmp/out.txt') 'sdílená větev' 'přesměrování do souboru nemaže chráněný cíl'

# CONTROLS: nothing else loosened. Each of these denied before the change and
# must deny after it, or the ALLOWs above prove only that the guard went quiet.
foreach ($c in @(
    'git push origin develop',
    'git push --force origin HEAD:develop',
    'git push --mirror origin',
    'git push origin refs/heads/*:refs/heads/*',
    'git push origin a:b c:d'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "kontrola: nezvolnilo se nic dalšího: $c" }

# THE HEREDOC CASE MUST NOT RE-OPEN. `<<` is excluded from the redirection
# shapes, and `EOF` is still collected as an argument, so the trailing token
# still makes a problem off command position and the body stays document text.
Assert-Eq (Test-Cmd "cat <<'EOF'`ngit push --force origin develop`nEOF") '' 'heredoc: tělo zůstává textem dokumentu i po zavedení přesměrování'

# A REDIRECTION AS THE FIRST TOKEN AFTER `push` leaves an EMPTY argument list,
# which is a bare `git push` — it resolves the current branch and is judged
# exactly as a bare push is. Both halves, against a real repository, the same
# fixture shape the bare-push block above uses.
$tmpRedir = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpRedir | Out-Null
& git init -b develop $tmpRedir | Out-Null
Assert-Match (Test-Cmd 'git push 2>&1 | tail -3' $tmpRedir) 'sdílená větev' 'přesměrování hned za push: pořád bare push, na develop zamítnut'
& git -C $tmpRedir checkout -q -b feature/ums-9-x
Assert-Eq (Test-Cmd 'git push 2>&1 | tail -3' $tmpRedir) '' 'přesměrování hned za push: na tiketové větvi projde'
Remove-Item -Recurse -Force $tmpRedir


Complete-Tests
