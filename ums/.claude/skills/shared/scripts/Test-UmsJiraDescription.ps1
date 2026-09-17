#Requires -Version 7
Set-StrictMode -Version Latest
function Test-UmsJiraDescription {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [int] $Budget = 2500, [switch] $RequireSections)
    $f = @()
    $len = $Text.Length
    if ($len -gt $Budget) { $f += "Popis má $len znaků, rozpočet je $Budget" }
    foreach ($m in [regex]::Matches($Text, '\[(?<t>[^\]]*)\]\((?<u>https?://[^)]+)\)')) {
        if ($m.Groups['t'].Value -match '`') { $f += "Text odkazu obsahuje backticks: «$($m.Groups['t'].Value)»" }
    }
    foreach ($m in [regex]::Matches($Text, '\*\*[^*\n]*`[^`\n]*`[^*\n]*\*\*')) { $f += "Tučné obaluje code span: «$($m.Value)»" }
    foreach ($m in [regex]::Matches($Text, '<[^>\n]+>')) { $f += "Popis obsahuje ostré závorky, které Jira zahodí: «$($m.Value)»" }
    if ($RequireSections) {
        foreach ($s in @('**Cíl**', '**Rozsah**')) { if ($Text -notmatch [regex]::Escape($s)) { $f += "Chybí sekce $s" } }
        if ($Text -notmatch '\*\*Návrh \(design\):\*\*') { $f += 'Chybí řádek **Návrh (design):**' }
    }
    return @{ Ok = ($f.Count -eq 0); Findings = @($f); Length = $len }
}
