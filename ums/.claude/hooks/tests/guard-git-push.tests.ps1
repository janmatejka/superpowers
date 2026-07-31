Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')

function Test-Cmd([string] $Command, [string] $Cwd = '') {
    $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($Cwd) { $payload.cwd = $Cwd }
    return Invoke-Hook ($payload | ConvertTo-Json -Depth 5 -Compress)
}

# allowed: the actor's own ticket branch
Assert-Eq (Test-Cmd 'git push origin feature/ums-1-alfa') '' 'push tiketové větve projde'
Assert-Eq (Test-Cmd 'git push -u origin feature/ums-1-alfa') '' 'push s -u projde'
Assert-Eq (Test-Cmd 'git status') '' 'jiný git příkaz se neřeší'
Assert-Eq (Test-Cmd 'echo "git push origin develop"') '' 'zmínka v echu se neřeší'

# denied: shared branches
foreach ($c in @(
    'git push origin develop',
    'git push origin main',
    'git push origin release/2026.1',
    'git push origin HEAD:refs/heads/develop',
    'cd /repo && git push origin develop',
    'git -C /repo push origin master'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto: $c" }

# denied: destructive shapes even on a ticket branch
foreach ($c in @(
    'git push --force origin feature/ums-1-alfa',
    'git push -f origin feature/ums-1-alfa',
    'git push --force-with-lease origin feature/ums-1-alfa',
    'git push origin +feature/ums-1-alfa',
    'git push origin :feature/ums-1-alfa',
    'git push --delete origin feature/ums-1-alfa',
    'git push --all origin',
    'git push --mirror origin'
)) { Assert-Match (Test-Cmd $c) 'permissionDecision.*deny' "zamítnuto: $c" }

# clustered short flags: any cluster containing 'f' means force
Assert-Match (Test-Cmd 'git push -fu origin feature/ums-1-alfa') 'permissionDecision.*deny' 'zamítnuto: -fu (force+set-upstream cluster)'
Assert-Match (Test-Cmd 'git push -uf origin feature/ums-1-alfa') 'permissionDecision.*deny' 'zamítnuto: -uf (force+set-upstream cluster)'
Assert-Eq (Test-Cmd 'git push -u origin feature/ums-1-alfa') '' 'push s -u (bez f) projde'
Assert-Eq (Test-Cmd 'git push -q origin feature/ums-1-alfa') '' 'push s -q projde'
Assert-Eq (Test-Cmd 'git push -v origin feature/ums-1-alfa') '' 'push s -v projde'
Assert-Eq (Test-Cmd 'git push --set-upstream origin feature/ums-1-alfa') '' 'push s --set-upstream projde'

# bare push resolves the current branch from cwd
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mbhook-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& git init -b develop $tmp | Out-Null
Assert-Match (Test-Cmd 'git push' $tmp) 'permissionDecision.*deny' 'bare push na develop je zamítnut'
& git -C $tmp checkout -q -b feature/ums-9-x
Assert-Eq (Test-Cmd 'git push' $tmp) '' 'bare push na tiketové větvi projde'
Remove-Item -Recurse -Force $tmp

# unparseable input must not block
Assert-Eq (Invoke-Hook 'not json') '' 'nerozparsovatelný vstup neblokuje'

Complete-Tests
