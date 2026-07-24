# PostToolUse hook: po Write/Edit .bpmn souboru spustí WfKicBpmnValidator.
# Fail-open pouze pro chybějící binár (validátor není postaven) — nálezy blokují (exit 2).
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$path = $payload.tool_input.file_path
if (-not $path -or $path -notmatch '\.bpmn$') { exit 0 }
if (-not (Test-Path $path)) { exit 0 }

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # .claude/hooks -> repo root
$exe = Get-ChildItem -Path (Join-Path $repoRoot 'MobilChange\SMSInfo3\KicWorkflow\WfKic\WfKicBpmnValidator\bin') `
    -Recurse -Filter 'WfKicBpmnValidator.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) {
    Write-Output "bpmn-validate hook: validátor není postaven (msbuild KicWorkflow.sln) — kontrola přeskočena"
    exit 0
}

$output = & $exe.FullName validate $path 2>&1
if ($LASTEXITCODE -eq 1) {
    [Console]::Error.WriteLine("BPMN validace selhala pro ${path}:")
    $output | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2   # exit 2 = stderr se vrátí agentovi jako blokující feedback
}
$output | Write-Output
exit 0
