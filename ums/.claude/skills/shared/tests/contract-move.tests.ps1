#Requires -Version 7
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Test-UmsContractMove.ps1')

$orig = @('# Title', '', 'Rule A.', 'Rule B.', 'Rule B.', '## Section', 'Why: measured once.')
$moved = @('# Title', 'Rule A.', '## Section', 'Rule B.', 'Rule B.', 'Why: measured once.')
$r = Compare-UmsLineMultiset $orig $moved
Assert-Eq @($r.Missing).Count 0 'přeuspořádání bez ztráty nemá Missing'
Assert-Eq @($r.Extra).Count 0 'přeuspořádání bez ztráty nemá Extra'

$lost = @('# Title', 'Rule A.', 'Rule B.', '## Section', 'Why: measured once.')
$r2 = Compare-UmsLineMultiset $orig $lost
Assert-Eq @($r2.Missing).Count 1 'jedna ze dvou stejných řádek chybí → Missing 1 (multiset, ne množina)'
Assert-Eq $r2.Missing[0] 'Rule B.' 'chybějící řádek je pojmenovaný'

$added = @('# Title', 'Rule A.', 'Rule B.', 'Rule B.', '## Section', 'Why: measured once.', 'Part of contract 3.x')
$r3 = Compare-UmsLineMultiset $orig $added
Assert-Eq @($r3.Extra).Count 1 'nový řádek je Extra'

# Test-UmsContractMove proti dočasnému git repu
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbmove-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmp 'a') | Out-Null
git -C $tmp init -q
Set-Content -Path (Join-Path $tmp 'a\src.md') -Value $orig -Encoding utf8
git -C $tmp add -A; git -C $tmp -c user.name=t -c user.email=t@t commit -q -m snap
$sha = (git -C $tmp rev-parse HEAD).Trim()
Set-Content -Path (Join-Path $tmp 'a\core.md') -Value @('# Title', 'Rule A.') -Encoding utf8
Set-Content -Path (Join-Path $tmp 'a\ref.md') -Value @('Part of contract 3.x', '## Section', 'Rule B.', 'Rule B.', 'Why: measured once.') -Encoding utf8
$m = Test-UmsContractMove -RepoRoot $tmp -SnapshotRef "$sha`:a/src.md" -TargetGlobs @('a/core.md', 'a/ref.md') -AllowExtraPattern '^Part of contract'
Assert-True $m.Ok 'přesun s povoleným strukturálním řádkem prochází'
Set-Content -Path (Join-Path $tmp 'a\ref.md') -Value @('Part of contract 3.x', '## Section', 'Rule B.', 'Why: measured once.', 'Brand new sentence.') -Encoding utf8
$m2 = Test-UmsContractMove -RepoRoot $tmp -SnapshotRef "$sha`:a/src.md" -TargetGlobs @('a/core.md', 'a/ref.md') -AllowExtraPattern '^Part of contract'
Assert-True (-not $m2.Ok) 'ztracený řádek i nepovolený nový řádek shodí verdikt'
Assert-Eq @($m2.Missing).Count 1 'ztracený Rule B.'
Assert-Eq @($m2.UnexpectedExtra).Count 1 'nová věta je nepovolený Extra'
Remove-Item -Recurse -Force $tmp
Complete-Tests
