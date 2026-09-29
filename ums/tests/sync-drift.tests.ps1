Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Cisté stavební bloky ochrany proti driftu (design 3.2): hash stromu po
# normalizaci CRLF, manifest per worktree, trojstavové porovnání cíl / manifest
# / fork a detekce mb-* skillů jen v cíli. Sada nemění nic mimo OS temp; živé
# monorepo ani tento repozitář se jí netýkají (linked worktree vzniká výhradně
# ve fixture repu v temp).
. (Join-Path $PSScriptRoot '..\sync-with-monorepo.ps1') -DotSourceOnly

$work = Join-Path ([IO.Path]::GetTempPath()) ("ums-sync-drift-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Write-Fx([string] $Root, [string] $Rel, [string] $Text) {
    $p = Join-Path $Root $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    Set-Content -LiteralPath $p -Value $Text -NoNewline
}
function New-Tree([string] $Name, [hashtable] $Files) {
    $root = Join-Path $work $Name
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    foreach ($k in $Files.Keys) { Write-Fx $root $k $Files[$k] }
    return $root
}
function Join-Sorted($v) { return (@($v) | Sort-Object) -join '|' }
function Copy-Map([hashtable] $m) { $c = @{}; foreach ($k in $m.Keys) { $c[$k] = $m[$k] }; return $c }
function Invoke-Git([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Dir}: $out" }
    return $out
}

$items = @('skills\shared', 'skills\mb-x', 'settings.json')

try {
    # --- (e) hash: CRLF a LF téhož textu dávají shodný hash ------------------
    $lf   = New-Tree 'e-lf'   @{ 'skills\shared\x.md' = "a`nb`n"; 'settings.json' = "{}`n" }
    $crlf = New-Tree 'e-crlf' @{ 'skills\shared\x.md' = "a`r`nb`r`n"; 'settings.json' = "{}`r`n" }
    $hLf   = Get-UmsTreeHashes $lf $items
    $hCrlf = Get-UmsTreeHashes $crlf $items
    Assert-Eq $hLf.Count 2 '(e) hash: dva soubory (skills\mb-x neexistuje a přeskočí se)'
    Assert-True ($hLf.ContainsKey('skills\shared\x.md')) '(e) hash: klíč je relativní cesta se zpětným lomítkem'
    Assert-True ($hLf.ContainsKey('settings.json')) '(e) hash: položka-soubor je zahrnuta pod svým názvem'
    Assert-Eq $hCrlf['skills\shared\x.md'] $hLf['skills\shared\x.md'] '(e) CRLF vs LF: shodný hash skillu'
    Assert-Eq $hCrlf['settings.json'] $hLf['settings.json'] '(e) CRLF vs LF: shodný hash souboru'
    $hOther = Get-UmsTreeHashes (New-Tree 'e-other' @{ 'skills\shared\x.md' = "a`nc`n" }) @('skills\shared')
    Assert-True ($hOther['skills\shared\x.md'] -cne $hLf['skills\shared\x.md']) '(e) jiný obsah: jiný hash'
    Assert-Match $hLf['settings.json'] '^[0-9a-f]{64}$' '(e) hash je 64 malých hex znaků'

    $h1 = Get-UmsTreeHashes (New-Tree 'e-known' @{ 'k.txt' = "a`n" }) @('k.txt')
    Assert-Eq $h1['k.txt'] '87428fc522803d31065e7bce3cf03fe475096631e5e07bbd7a0fde60c4cf25c7' '(e) hash: SHA-256 obsahu "a\n" (známá hodnota)'

    # vnořené adresáře, skryté soubory, prázdný vstup, lomítka v položce
    $deep = New-Tree 'e-deep' @{ 'skills\shared\sub\deep\y.md' = 'y'; 'skills\shared\.hidden' = 'h' }
    $hDeep = Get-UmsTreeHashes $deep @('skills\shared')
    Assert-True ($hDeep.ContainsKey('skills\shared\sub\deep\y.md')) '(e) hash: vnořený soubor s celou relativní cestou'
    Assert-True ($hDeep.ContainsKey('skills\shared\.hidden')) '(e) hash: skrytý soubor je zahrnut'
    $none = Get-UmsTreeHashes $deep @('nic', 'skills\nic')
    Assert-Eq $none.Count 0 '(e) hash: samé neexistující položky -> prázdná tabulka'
    Assert-True ($none -is [hashtable]) '(e) hash: vždy [hashtable], i prázdná'
    $fwd = Get-UmsTreeHashes $deep @('skills/shared')
    Assert-True ($fwd.ContainsKey('skills\shared\sub\deep\y.md')) '(e) hash: položka s lomítkem dá stejné klíče se zpětným lomítkem'
    Assert-Eq $fwd.Count $hDeep.Count '(e) hash: položka s lomítkem dá stejný počet souborů'

    # --- (a)-(d) drift -------------------------------------------------------
    $forkA   = New-Tree 'a-fork'   @{ 'skills\shared\x.md' = 'one'; 'skills\mb-x\SKILL.md' = 'skill' }
    $targetA = New-Tree 'a-target' @{ 'skills\shared\x.md' = 'one'; 'skills\mb-x\SKILL.md' = 'skill' }
    $fkA = Get-UmsTreeHashes $forkA $items
    $tgA = Get-UmsTreeHashes $targetA $items

    $r = Test-UmsDeployDrift $tgA $null $fkA
    Assert-Eq @($r.Drifted).Count 0 '(a) bez manifestu, cíl = fork: Drifted prázdné'
    Assert-True ($r.NoManifest -eq $true) '(a) bez manifestu: NoManifest je $true'

    $targetB = New-Tree 'b-target' @{ 'skills\shared\x.md' = 'changed'; 'skills\mb-x\SKILL.md' = 'skill' }
    $tgB = Get-UmsTreeHashes $targetB $items
    $r = Test-UmsDeployDrift $tgB $null $fkA
    Assert-Eq (Join-Sorted $r.Drifted) 'skills\shared\x.md' '(b) bez manifestu, cíl ≠ fork v skills\shared\x.md: Drifted = ten soubor'
    Assert-True ($r.NoManifest -eq $true) '(b) NoManifest je $true'

    # bez manifestu: soubor jen v cíli je rozdíl (zrcadlení by ho smazalo), soubor jen ve forku ne
    $targetB2 = New-Tree 'b2-target' @{ 'skills\shared\x.md' = 'one'; 'skills\shared\extra.md' = 'mine' }
    $r = Test-UmsDeployDrift (Get-UmsTreeHashes $targetB2 $items) $null $fkA
    Assert-Eq (Join-Sorted $r.Drifted) 'skills\shared\extra.md' '(b) bez manifestu: soubor jen v cíli je drift'
    $r = Test-UmsDeployDrift @{} $null $fkA
    Assert-Eq @($r.Drifted).Count 0 '(b) bez manifestu: soubory jen ve forku (v cíli chybí) nejsou drift'

    # (c) manifest = cíl, fork změněný -> legitimní nasazení změny
    $forkC = New-Tree 'c-fork' @{ 'skills\shared\x.md' = 'NEW'; 'skills\mb-x\SKILL.md' = 'skill' }
    $fkC = Get-UmsTreeHashes $forkC $items
    $mfC = Copy-Map $tgA
    $r = Test-UmsDeployDrift $tgA $mfC $fkC
    Assert-Eq @($r.Drifted).Count 0 '(c) manifest = cíl, fork změněný: Drifted prázdné'
    Assert-True ($r.NoManifest -eq $false) '(c) s manifestem: NoManifest je $false'

    # (d) manifest ≠ cíl a cíl ≠ fork -> drift
    $r = Test-UmsDeployDrift $tgB $mfC $fkC
    Assert-Eq (Join-Sorted $r.Drifted) 'skills\shared\x.md' '(d) manifest ≠ cíl a cíl ≠ fork: Drifted'
    Assert-True ($r.Drifted -is [string[]]) '(d) Drifted je [string[]] i s jednou položkou'
    # (d2) rozhoduje jen druhá podmínka: cíl ≠ manifest, ale cíl = fork (změna už je ve forku) -> bez driftu
    $r = Test-UmsDeployDrift $tgB $mfC $tgB
    Assert-Eq @($r.Drifted).Count 0 '(d2) cíl ≠ manifest, cíl = fork: bez driftu'
    $r = Test-UmsDeployDrift $tgA $mfC $fkA
    Assert-Eq @($r.Drifted).Count 0 '(d3) vše shodné: bez driftu'
    Assert-True ($r.Drifted -is [string[]]) '(d3) Drifted je [string[]] i prázdné'

    # (h) smazání a nové soubory v cíli; prázdný manifest není žádný manifest
    $tgDel = Copy-Map $tgA; $tgDel.Remove('skills\shared\x.md')
    $r = Test-UmsDeployDrift $tgDel $mfC $fkA
    Assert-Eq (Join-Sorted $r.Drifted) 'skills\shared\x.md' '(h) soubor v manifestu, smazaný v cíli, ve forku je: drift'
    $fkGone = Copy-Map $fkA; $fkGone.Remove('skills\shared\x.md')
    $r = Test-UmsDeployDrift $tgDel $mfC $fkGone
    Assert-Eq @($r.Drifted).Count 0 '(h) smazaný v cíli i ve forku: bez driftu'
    $tgNew = Copy-Map $tgA; $tgNew['skills\shared\mine.md'] = ('0' * 64)
    $r = Test-UmsDeployDrift $tgNew $mfC $fkA
    Assert-Eq (Join-Sorted $r.Drifted) 'skills\shared\mine.md' '(h) nový soubor jen v cíli (není v manifestu ani ve forku): drift'
    $r = Test-UmsDeployDrift $tgB @{} $fkA
    Assert-True ($r.NoManifest -eq $false) '(h) prázdný manifest: NoManifest je $false'
    Assert-Eq (Join-Sorted $r.Drifted) 'skills\shared\x.md' '(h) prázdný manifest: cíl ≠ manifest (chybí) a cíl ≠ fork -> drift'

    # --- manifest: cesta, zápis, čtení ---------------------------------------
    # mimo git
    $plain = New-Tree 'p-plain' @{ 'a.txt' = 'a' }
    $mp = Get-UmsManifestPath $plain 'claude-Monorepo'
    Assert-Eq $mp (Join-Path $plain '.ums-sync-manifest-claude-Monorepo.json') 'cesta mimo git: <TargetRoot>\.ums-sync-manifest-<Key>.json'

    # (f) git repo a linked worktree
    $repo = Join-Path $work 'f-repo'
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    Invoke-Git $repo @('init', '-q') | Out-Null
    Write-Fx $repo '.gitignore' ".superpowers/`n"
    Write-Fx $repo '.gitattributes' "* text=auto eol=lf`n"
    Write-Fx $repo 'a.txt' "a`n"
    Invoke-Git $repo @('add', '.gitignore', '.gitattributes', 'a.txt') | Out-Null
    Invoke-Git $repo @('commit', '-q', '-m', 'base') | Out-Null
    $wt = Join-Path $work 'f-wt'
    Invoke-Git $repo @('worktree', 'add', '-q', '-b', 'fixture-wt', $wt) | Out-Null

    $pMain = Get-UmsManifestPath $repo 'claude-Monorepo'
    $pWt   = Get-UmsManifestPath $wt 'claude-Monorepo'
    Assert-Match $pMain '\.git[\\/]ums-sync-manifest-claude-Monorepo\.json$' '(f) hlavní pracovní strom: manifest přímo v .git'
    Assert-True ($pMain -notmatch '/') '(f) hlavní pracovní strom: cesta má jen zpětná lomítka'
    Assert-Match $pWt '\.git[\\/]worktrees[\\/][^\\/]+[\\/]ums-sync-manifest-claude-Monorepo\.json$' '(f) linked worktree: manifest pod .git\worktrees\<jméno>\'
    Assert-True ($pWt -ne $pMain) '(f) linked worktree: jiná cesta než common dir'
    Assert-True (Test-Path -LiteralPath (Split-Path $pWt)) '(f) adresář manifestu linked worktree existuje'
    Assert-True ($pWt -notmatch '/') '(f) linked worktree: cesta má jen zpětná lomítka'
    $pOtherKey = Get-UmsManifestPath $wt 'codex-UserProfile'
    Assert-Match $pOtherKey 'ums-sync-manifest-codex-UserProfile\.json$' '(f) klíč je součástí názvu souboru'

    # zápis a čtení
    Assert-True ($null -eq (Read-UmsManifest $pWt)) 'čtení neexistujícího manifestu: $null'
    $files = @{ 'skills\shared\x.md' = ('b' * 64); 'settings.json' = ('a' * 64); 'skills\mb-x\SKILL.md' = ('c' * 64) }
    Write-UmsManifest $pWt $files 'deadbeef1234'
    Assert-True (Test-Path -LiteralPath $pWt) 'zápis vytvoří soubor manifestu'
    $m = Read-UmsManifest $pWt
    Assert-True ($null -ne $m) 'čtení zapsaného manifestu: objekt'
    Assert-Eq $m.ForkSha 'deadbeef1234' 'manifest: ForkSha se vrátí'
    Assert-True ($m.Files -is [hashtable]) 'manifest: Files je [hashtable]'
    Assert-Eq $m.Files.Count 3 'manifest: tři soubory'
    Assert-Eq $m.Files['skills\shared\x.md'] ('b' * 64) 'manifest: hash se vrátí pod klíčem s zpětným lomítkem'
    # Written asertuj proti syrovému textu, ne proti hodnotě parsované zpět (datetime koerce)
    $raw = [IO.File]::ReadAllText($pWt)
    Assert-Match $raw '"Written":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z"' 'manifest: Written je ISO-8601 UTC v syrovém JSON'
    Assert-True ($m.Written -is [string]) 'manifest: Written se čte jako řetězec, ne datetime'
    Assert-Match $m.Written '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$' 'manifest: Written se vrátí v ISO-8601 UTC'
    Assert-True (-not $raw.Contains("`r")) 'manifest: LF konce řádků'
    Assert-True ($raw.EndsWith("`n")) 'manifest: končí novým řádkem'
    $iA = $raw.IndexOf('settings.json'); $iB = $raw.IndexOf('skills\\mb-x'); $iC = $raw.IndexOf('skills\\shared')
    Assert-True (($iA -ge 0) -and ($iA -lt $iB) -and ($iB -lt $iC)) 'manifest: klíče Files jsou seřazené (čitelný diff)'
    # deterministický výstup: totéž nasazení v jiném pořadí vkládání dá tytéž Files
    $files2 = @{}; foreach ($k in ($files.Keys | Sort-Object -Descending)) { $files2[$k] = $files[$k] }
    $pWt2 = Join-Path $work 'manifest-2.json'
    Write-UmsManifest $pWt2 $files2 'deadbeef1234'
    $filesPart = { param($t) $t.Substring($t.IndexOf('"Files"'), $t.IndexOf('"ForkSha"') - $t.IndexOf('"Files"')) }
    Assert-Eq (& $filesPart ([IO.File]::ReadAllText($pWt2))) (& $filesPart $raw) 'manifest: Files serializovaná stejně bez ohledu na pořadí vkládání'
    # přepis a vytvoření chybějícího adresáře
    Write-UmsManifest $pWt @{ 'only.txt' = ('d' * 64) } 'cafe'
    $m2 = Read-UmsManifest $pWt
    Assert-Eq $m2.Files.Count 1 'přepis: zůstane jen nový obsah'
    Assert-Eq $m2.ForkSha 'cafe' 'přepis: nový ForkSha'
    $nested = Join-Path $work 'nested\dir\m.json'
    Write-UmsManifest $nested @{} 'x'
    Assert-True (Test-Path -LiteralPath $nested) 'zápis do neexistujícího adresáře ho vytvoří'
    Assert-Eq (Read-UmsManifest $nested).Files.Count 0 'prázdný Files se zapíše i přečte'
    # poškozený manifest = žádný manifest (bezpečný směr: STOP na každý rozdíl)
    $bad = Join-Path $work 'bad.json'
    [IO.File]::WriteAllText($bad, '{ this is not json')
    Assert-True ($null -eq (Read-UmsManifest $bad 3>$null)) 'poškozený manifest: $null'
    [IO.File]::WriteAllText($bad, 'null')
    Assert-True ($null -eq (Read-UmsManifest $bad 3>$null)) 'JSON null: $null'
    [IO.File]::WriteAllText($bad, '[1,2]')
    Assert-True ($null -eq (Read-UmsManifest $bad 3>$null)) 'JSON pole: $null'

    # --- (g) mb-* skilly jen v cíli ------------------------------------------
    $fs = New-Tree 'g-fork' @{ 'mb-common\SKILL.md' = 'c'; 'mb-forkonly\SKILL.md' = 'f'; 'shared\x.md' = 's' }
    $ts = New-Tree 'g-target' @{ 'mb-common\SKILL.md' = 'c'; 'mb-extra\SKILL.md' = 'e'; 'brainstorming\SKILL.md' = 'b'; 'shared\x.md' = 's'; 'mb-file' = 'not a dir' }
    $only = @(Get-UmsTargetOnlySkills $ts $fs)
    Assert-Eq ($only -join '|') 'mb-extra' '(g) jen v cíli: mb-extra (ne mb-common, ne mb-forkonly, ne vendorovaný brainstorming, ne soubor)'
    Assert-Eq @(Get-UmsTargetOnlySkills $fs $fs).Count 0 '(g) shodné adresáře: nic'
    Assert-Eq @(Get-UmsTargetOnlySkills (Join-Path $work 'neexistuje') $fs).Count 0 '(g) neexistující adresář skillů cíle: nic'
    $onlyAll = @(Get-UmsTargetOnlySkills $ts (Join-Path $work 'neexistuje'))
    Assert-Eq ($onlyAll -join '|') 'mb-common|mb-extra' '(g) neexistující fork: všechny mb-* cíle, seřazené'
}
finally {
    # Úklid: linked worktree fixtura nejdřív odpojit, pak smazat celý temp adresář.
    if (Test-Path -LiteralPath (Join-Path $work 'f-repo\.git')) {
        & git -C (Join-Path $work 'f-repo') worktree remove --force (Join-Path $work 'f-wt') 2>&1 | Out-Null
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-Tests
