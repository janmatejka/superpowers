# Declared intent must not make the run scale with COMMIT COUNT.
#
# Measured defect (UMS-3495): declared intent used to switch the enumeration
# window OFF, so the main traversal walked the history of every remote branch
# and resolved each commit's branches with `git branch -r --contains` — one call
# PER COMMIT. On the target monorepo (337 remote branches) that ran over 25
# minutes with no output and had to be killed, which left the entry gate's
# fail-closed collision STOP unreachable exactly where it matters.
#
# The fix keeps the main traversal WINDOWED (so its `--contains` fan-out stays
# bounded by the window, as it always was) and answers declared intent with a
# separate WIDE pass: one `git log --stdin --source` over all refs, restricted
# to proposals/active/, with %S naming the ref. Constant process count, no
# per-commit branch resolution.
#
# THE PROPERTY UNDER TEST is therefore NOT "zero --contains" — the windowed
# traversal legitimately still uses it. It is: declaring intent adds NO
# per-commit branch resolution on top of the windowed run. Before the fix the
# two counts diverged (declared intent widened the walk); now they must match.
#
# A per-REF walk was also tried and abandoned: it removes `--contains` entirely
# but pays one PROCESS per ref, and process spawn dominates on Windows
# (playbook.md measures 100x on a comparable rewrite). The run that prompted
# abandoning it came out at ~122 s, but against a baseline nobody had measured
# at the time — so that is the reason it was dropped, not a proven regression.
#
# What IS controlled, measured on the target monorepo (337 remote branches),
# alternating the two versions back to back because the repo is live and other
# sessions push into it: the windowed path is 106 / 107 / 106 / 103 s before and
# after this change, i.e. unchanged, and its entry set comes out identical in
# the round where the repo did not move under the runs. Declared intent went
# from "25+ minutes, killed" to ~160 s.
#
# HOW THIS IS MEASURED, and why it is not a mock: a `git.bat` earlier in PATH
# records the real argv and forwards to the real git. Verified empirically
# before this suite was written — the script's output under the shim is
# byte-identical to a run without it (the `--format=%x01%H...` argument survives
# batch's own `%` handling). So the instrument observes the real thing.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
. (Join-Path $PSScriptRoot 'new-fixture-repo.ps1')

$fx = New-FixtureRepo

# --- the recording shim ------------------------------------------------------
$shimDir = Join-Path ([IO.Path]::GetTempPath()) ("doc-index-shim-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
$callLog = Join-Path $shimDir 'calls.log'
$realGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source
@"
@echo off
>>"$callLog" echo %*
"$realGit" %*
"@ | Set-Content -Path (Join-Path $shimDir 'git.bat') -Encoding ascii

function Get-Calls { if (Test-Path -LiteralPath $callLog) { @(Get-Content -LiteralPath $callLog) } else { @() } }
function Reset-Calls { Remove-Item -LiteralPath $callLog -ErrorAction SilentlyContinue }
function Count-Contains { param([string[]] $Calls) @(@($Calls) | Where-Object { $_ -match 'branch\s+-r\s+--contains' }).Count }

$savedPath = $env:PATH
$env:PATH = "$shimDir;$savedPath"
try {
    # --- 1) BASELINE: the windowed run, no intent declared -------------------
    Reset-Calls
    $plain = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch')
    $plainCalls = Get-Calls
    $plainContains = Count-Contains $plainCalls

    # POSITIVE CONTROL for the instrument. Without it every count comparison
    # below would also hold for a shim that was never invoked at all.
    Assert-True (@($plainCalls).Count -gt 0) 'kontrola instrumentu: shim zaznamenal volání gitu'
    Assert-True ([bool](@($plainCalls) -match 'for-each-ref')) 'kontrola instrumentu: shim vidí volání z potomka, ne jen z testu'
    # And a control that the measured construct is actually PRESENT in the
    # baseline: if the windowed traversal stopped using --contains for some
    # unrelated reason, the equality assertions would go green while measuring
    # nothing at all.
    Assert-True ($plainContains -gt 0) 'kontrola měřidla: okenní traversal --contains skutečně používá'
    Assert-Eq $plain.Code 0 'okenní běh bez deklarovaného záměru nezastaví'

    # --- 2) THE PROOF: declared intent adds no per-commit resolution ---------
    Reset-Calls
    $dup = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Jira', 'UMS-1')
    $dupContains = Count-Contains (Get-Calls)
    Assert-Eq $dupContains $plainContains 'deklarovaný záměr nepřidá ani jedno branch -r --contains nad okenní běh'

    # --- 3) ...and it is not cheap because it stopped doing the job ----------
    Assert-Eq $dup.Code 2 'deklarovaný tiket aktivní na cizí větvi je pořád kolize (exit 2)'
    Assert-Match $dup.Out 'KOLIZE AKTIVNÍ PRÁCE' 'kolize se pořád hlásí jako CHYBA'
    Assert-Match $dup.Out 'origin/feature/ums-1-alfa' 'hlášení pořád nese větev cizího aktéra'
    Assert-Match $dup.Out '\d{4}-\d{2}-\d{2}' 'hlášení pořád nese datum posledního commitu'

    # --- 4) the DORMANT branch is still reached ------------------------------
    # This is the whole reason declared intent ever widened anything: a
    # colleague's branch whose tip fell outside the window. The wide pass must
    # find it without widening the main traversal.
    Reset-Calls
    $uspana = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Jira', 'UMS-11')
    $uspanaContains = Count-Contains (Get-Calls)
    Assert-Eq $uspana.Code 2 'uspaná větev se stejným tiketem je kolize i po zúžení traversalu'
    Assert-Match $uspana.Out 'KOLIZE AKTIVNÍ PRÁCE.*ums_11_uspana' 'kolize s uspanou větví se pořád hlásí'
    Assert-Match $uspana.Out 'origin/feature/ums-11-uspana' 'hlášení nese větev uspaného aktéra'
    Assert-NotMatch $uspana.Out '\| ums_11_uspana \|' 'uspaná větev se přitom netiskne do tabulky — okno filtruje jen výpis'
    Assert-Eq $uspanaContains $plainContains 'ani dosažení uspané větve nepřidá branch -r --contains'

    # --- 5) the wide picture survives, not just the declared slug -----------
    # Declared intent narrows NOTHING about what gets reported: a run declaring
    # UMS-7 still reports another actor's work on UMS-1 as information. This is
    # what forbids replacing the traversal with a scan for the declared slug.
    $other = Invoke-Index @('-RepoPath', $fx.Work, '-BaseRef', 'origin/develop', '-NoFetch', '-Jira', 'UMS-7')
    Assert-Eq $other.Code 0 'deklarovaný záměr na jiném tiketu běh nezastaví'
    Assert-Match $other.Out 'CIZÍ AKTIVNÍ PRÁCE.*ums_1_alfa' 'cizí práce jiného tiketu se pořád hlásí jako informace'
}
finally {
    $env:PATH = $savedPath
    Remove-Item -LiteralPath $shimDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Split-Path $fx.Work) -ErrorAction SilentlyContinue
}

Complete-Tests
