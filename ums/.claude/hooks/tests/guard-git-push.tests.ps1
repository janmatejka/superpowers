Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')

# guard-git-push.mjs is NOT the enforcement boundary (fix round 2 demoted it
# after two rounds of adversarial review — see the real guarantee's own
# fixture-driven suite in pre-push.tests.ps1). This file only pins its
# reduced, best-effort, FAIL-OPEN responsibility: a friendly early warning
# for the common accident (a plainly-typed push that resolves to a protected
# branch), plus the one context-free `--no-verify` substring check, plus the
# fetch protected-destination check. Everything else must ALLOW.

function Test-Cmd([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
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
# denied: the one thing this layer still catches — a push that can be
# confidently parsed as simple AND whose target is a protected branch
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
# allowed now (regression pinned in the NEW direction): an unrecognized flag
# means "not simple" and this layer is no longer the boundary — it defers to
# the pre-push hook instead of guessing. Real force/delete/mirror pushes are
# proven rejected end-to-end in pre-push.tests.ps1, not here.
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
)) { Assert-Eq (Test-Cmd $c) '' "povoleno (neznámý přepínač, o rozhodnutí se stará pre-push hook): $c" }

# ---------------------------------------------------------------------------
# allowed now (former over-denial from round 1, fixed by failing open on
# anything not cleanly parseable): quoted branch names, redirections,
# trailing comments, and a commit message that happens to mention "push"
# ---------------------------------------------------------------------------
foreach ($c in @(
    'git push origin "feature/ums-1-alfa"',
    'git push origin feature/ums-1-alfa 2>&1',
    'git push origin feature/ums-1-alfa # nasazení',
    'git commit -m "vysvetli git push origin develop"'
)) { Assert-Eq (Test-Cmd $c) '' "povoleno (dřívější nadměrné zamítnutí opraveno): $c" }

# ---------------------------------------------------------------------------
# `--no-verify` next to `push`: the one context-free substring check, since
# that flag would skip the real guarantee (the pre-push hook)
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
# refspec parser (REFSPEC_RE) only trusts those characters as "simple" and
# would fail-open on anything else regardless of the protected list.
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
# UMS_ALLOW_SHARED_PUSH=1 — the human escape the pre-push hook honours. This
# early-warning layer must not stand in front of the command the layer itself
# hands the user, otherwise the escape is unusable in-session.
# ---------------------------------------------------------------------------
Assert-Eq (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push origin develop') '' 'push sdílené větve s lidskou výjimkou projde'
Assert-Eq (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push origin main') '' 'výjimka platí pro každou sdílenou větev'
# the escape lifts ONE rule; it is not a licence to disable every hook
Assert-Match (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=1 git push --no-verify origin develop') 'permissionDecision.*deny' 'výjimka neomlouvá --no-verify'
# a different value is not the escape
Assert-Match (Test-Cmd 'UMS_ALLOW_SHARED_PUSH=0 git push origin develop') 'permissionDecision.*deny' 'jiná hodnota než 1 výjimkou není'
# the rejection itself must teach the way out
Assert-Match (Test-Cmd 'git push origin develop') 'UMS_ALLOW_SHARED_PUSH=1' 'zamítnutí pojmenuje únikovou cestu pro člověka'

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

# unresolvable current branch (detached HEAD): round 1 denied this
# fail-closed; round 2 deliberately ALLOWS it — this layer no longer
# guesses when uncertain, it defers to the pre-push hook.
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

Complete-Tests
