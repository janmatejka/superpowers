Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '_assert.ps1')
$ErrorActionPreference = 'Stop'

# Bez znacky se hook v danem harnessu sam vypne, takze by tam agent bezel
# uplne bez dozoru - ne jen bez predbezneho varovani. settings.json se na
# ne-Claude cile zamerne nenasazuje, proto vlastni injektaz.
. (Join-Path $PSScriptRoot '..\..\..\sync-with-monorepo.ps1') -DotSourceOnly

foreach ($agent in @('codex', 'gemini', 'kilocode')) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("mbmarker-$agent-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-AgentMarker $dir $agent
    $written = (Get-ChildItem -Recurse -File $dir | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    Assert-Match $written 'MB_AGENT_SESSION' "$agent`: značka je zapsaná do konfigurace harnesse"
    # Opakovaný běh nesmí značku duplikovat.
    Set-AgentMarker $dir $agent
    $again = (Get-ChildItem -Recurse -File $dir | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    Assert-Eq ([regex]::Matches($again, 'MB_AGENT_SESSION').Count) 1 "$agent`: opakovaný běh značku neduplikuje"
    Remove-Item -Recurse -Force $dir
}

Complete-Tests
