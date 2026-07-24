<#
.SYNOPSIS
Generates a Jira epic dependency view from an offline snapshot of Jira issues
(or, in -Source Proposals mode, from proposal header fields), and optionally
runs a prose<->links consistency check ("consistency oracle").
Default view is a portable "wave table" (column = dependency wave); the Mermaid
flowchart and the legacy indented list are opt-in.

.DESCRIPTION
READ-ONLY tool. Never calls Jira, git, or the network. Reads JSON snapshot
file(s) produced by Jira read tools (MCP result shape {issues:{nodes:[...]}},
REST search shape {issues:[...]}, a bare issue array, or a single issue
object) plus optional local proposal Markdown files, and prints a Czech
Markdown report to stdout (or -OutFile).

The default "wave table" is the improved form of the old indented list: each
ticket sits in the column of its dependency wave (longest Blocks chain from a
root), so every child is to the RIGHT of its blocker. It renders everywhere
(GitHub, IDE, Jira import — no Mermaid engine needed), carries clickable ticket
links (Jira mode), and marks rows by dynamically assigned stream emoji. Only
Blocks drives the columns; souvisí/vyčleněno are shown in the Mermaid
flowchart (-Mermaid).

Edge semantics (canonical direction = "unlocks"):
  Blocks      A --> B  means A blocks B (A must be done first).
  Issue split A -.split.-> B  means B was split out of A.
  Relates     undirected dotted edge.
  Other types generic directed edge (outward direction).

.PARAMETER InputFile
One or more snapshot JSON files. Issues from all files are merged (later files
win on duplicate keys).

.PARAMETER EpicKey
Key of the epic (e.g. UMS-3304). The epic issue itself is excluded from graph
nodes and (by default) from prose-assertion scanning. If omitted, the first
issue with issuetype "Epic" is used.

.PARAMETER ProposalPath
Files or directories with local proposal Markdown files (directories are
searched recursively for "proposal_*.md"). In -Source Proposals this is the
primary node/edge source: each file becomes a graph node (slug from its
filename) and its header fields ("Blokuje", "Blokováno", "Souvisí",
"Vyčleněno z/do") become graph edges. In -Source Jira (default) it instead
attributes each file's prose to a ticket via its "**Jira:** KEY" header or a
"_1234" slug fragment in the filename, so that prose participates in the
consistency check.

.PARAMETER Check
Include the consistency-oracle section (prose vs links, symmetry, cycles).

.PARAMETER Mermaid
Also emit the Mermaid flowchart section (off by default). The flowchart is the
only view that shows souvisí/vyčleněno edges.

.PARAMETER IndentedList
Also emit the legacy indented list section (off by default; superseded by the
wave table).

.PARAMETER NoStatus
Suppress the per-ticket status glyph in the wave table (the leading symbol
before the stream emoji). By default each ticket shows one merged status glyph
derived from its Jira status category, blocker readiness, and — when
-ProposalPath is given — whether a live proposal exists: ✅ done, 🔨 in
progress, ▶️ ready to implement (proposal + unblocked), ⏳ proposal ready but
still blocked, 🆕 ready to elaborate (unblocked, no proposal), ⛔ blocked.
Without -ProposalPath it degrades to ✅/🔨/▶️/⛔ (no proposal distinction).
In -Source Proposals the glyph comes from the proposal stage folder:
completed/ = done, active/ = in progress, next/ = live proposal.

.PARAMETER JiraBaseUrl
Base URL for ticket links in the wave table (default
https://datasyscz.atlassian.net). A per-issue webUrl in the snapshot wins over
this. Links are "<base>/browse/<KEY>". Jira mode only — in -Source Proposals
keys are not linked.

.PARAMETER IncludeEpicProse
Also scan the epic's own description for prose assertions (off by default:
the epic description carries the GENERATED graph and aggregated narrative,
which would produce false positives).

.PARAMETER OutFile
Write the report to this file instead of stdout. The tool writes nothing else.

.OUTPUTS
Markdown (Czech). Exit code: 0 = OK, 1 = script/input failure,
2 = consistency errors found (missing links, asymmetric links, cycles).
#>
[CmdletBinding()]
param(
    [ValidateSet('Jira','Proposals')] [string] $Source = 'Jira',
    [string[]] $InputFile,
    [string] $EpicKey,
    [string[]] $ProposalPath,
    [string[]] $ProjectKeys,
    [switch] $Check,
    [switch] $IncludeEpicProse,
    [switch] $Mermaid,
    [switch] $IndentedList,
    [switch] $NoStatus,
    [string] $JiraBaseUrl = 'https://datasyscz.atlassian.net',
    [string] $OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ExitCode = 0
$script:missingTargets = @()   # proposal mode: @{Self;Target;Field} for broken links
$proposalLive = @{}    # key/slug -> bool: má živý proposal (next/ nebo active/)
$proposalActive = @{}  # key/slug -> bool: proposal v active/ (běžící implementace)
$proposalInfoAvailable = [bool]$ProposalPath

if ($Source -eq 'Jira' -and -not $InputFile) { Write-Error 'Jira mode requires -InputFile.'; exit 1 }
if ($Source -eq 'Proposals' -and -not $ProposalPath) { Write-Error 'Proposals mode requires -ProposalPath.'; exit 1 }

# ---------- helpers ----------------------------------------------------------

function Remove-Diacritics([string] $s) {
    if (-not $s) { return '' }
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    -join ($norm.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
        [Globalization.UnicodeCategory]::NonSpacingMark })
}

function Get-AdfText($node) {
    # Recursively extract plain text from an ADF (Atlassian Document Format) object.
    if ($null -eq $node) { return '' }
    if ($node -is [string]) { return $node }
    $sb = [Text.StringBuilder]::new()
    if ($node.PSObject.Properties['text']) { [void]$sb.Append([string]$node.text) }
    if ($node.PSObject.Properties['content'] -and $node.content) {
        foreach ($child in $node.content) {
            [void]$sb.Append((Get-AdfText $child))
            [void]$sb.Append(' ')
        }
    }
    return $sb.ToString()
}

function Get-Field($issue, [string] $name) {
    if ($issue.PSObject.Properties['fields'] -and $issue.fields -and
        $issue.fields.PSObject.Properties[$name]) { return $issue.fields.$name }
    return $null
}

# ---------- proposal-mode helpers --------------------------------------------

function ConvertTo-Slug([string] $fileName) {
    $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $base = $base -replace '^proposal_', ''
    $base = $base -replace '-design$', ''
    return $base
}
function Split-HeaderBody([string] $text) {
    # Header = everything before the first '## ' heading; Body = from there on.
    $lines = $text -split '\r?\n'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s') {
            return @{ Header = ($lines[0..([Math]::Max(0,$i-1))] -join "`n"); Body = ($lines[$i..($lines.Count-1)] -join "`n") }
        }
    }
    return @{ Header = $text; Body = '' }
}
function Get-ProposalTitle([string] $header) {
    foreach ($ln in ($header -split '\r?\n')) {
        if ($ln -match '^#\s+(.*)$') {
            return (($Matches[1].Trim()) -replace '^(?:Proposal|Návrh)\s*(?:\((?:next|active)\))?\s*:\s*', '')
        }
    }
    return ''
}
# header dependency field (diacritics-stripped lowercase) -> canonical link shape
$script:FieldMap = @{
    'blokovano'    = @{ TypeName = 'Blocks';      Dir = 'inward'  }   # blocked by X  -> X --> this
    'blokuje'      = @{ TypeName = 'Blocks';      Dir = 'outward' }   # blocks Y      -> this --> Y
    'souvisi'      = @{ TypeName = 'Relates';     Dir = 'outward' }
    'vycleneno z'  = @{ TypeName = 'Issue split'; Dir = 'inward'  }   # split from W  -> W --> this
    'vycleneno do' = @{ TypeName = 'Issue split'; Dir = 'outward' }   # split to V    -> this --> V
    'vycleneno'    = @{ TypeName = 'Issue split'; Dir = 'inward'  }   # alias of 'vycleneno z'
}
$script:MdLinkRx = [regex]'\]\(\s*([^)\s]+\.md)\s*\)'

function Get-ProposalFiles([string[]] $paths) {
    $files = foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -Recurse -Filter 'proposal_*.md' -File }
        elseif (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p }
        else { Write-Warning "Proposal path not found: $p" }
    }
    return @($files | Where-Object { $_ })
}

# ---------- load & normalize snapshot ----------------------------------------

$issues = [ordered]@{}   # key -> normalized node (shared by both modes)

if ($Source -eq 'Jira') {
    # ----- Jira snapshot load & normalize (UNCHANGED behavior) -----
    $rawIssues = @()
    foreach ($file in $InputFile) {
        if (-not (Test-Path -LiteralPath $file)) { Write-Error "Input file not found: $file"; exit 1 }
        $json = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($null -eq $json) { Write-Error "Empty/invalid JSON: $file"; exit 1 }
        if ($json -is [System.Array]) { $rawIssues += $json }
        elseif ($json.PSObject.Properties['issues'] -and $json.issues) {
            if ($json.issues.PSObject.Properties['nodes'] -and $null -ne $json.issues.nodes) { $rawIssues += $json.issues.nodes }
            elseif ($json.issues -is [System.Array]) { $rawIssues += $json.issues }
            else { Write-Error "Unrecognized snapshot shape (issues without nodes/array): $file"; exit 1 }
        }
        elseif ($json.PSObject.Properties['key']) { $rawIssues += $json }
        else { Write-Error "Unrecognized snapshot shape: $file"; exit 1 }
    }
    if ($rawIssues.Count -eq 0) { Write-Error 'No issues found in input.'; exit 1 }
    foreach ($ri in $rawIssues) {
        if (-not $ri.PSObject.Properties['key'] -or -not $ri.key) { continue }
        $desc = Get-Field $ri 'description'
        $descText = if ($desc -is [string]) { $desc } else { Get-AdfText $desc }
        $statusObj = Get-Field $ri 'status'; $typeObj = Get-Field $ri 'issuetype'; $parentObj = Get-Field $ri 'parent'
        $links = @()
        $rawLinks = Get-Field $ri 'issuelinks'
        if ($rawLinks) {
            foreach ($l in $rawLinks) {
                $other = $null; $dir = $null
                if ($l.PSObject.Properties['outwardIssue'] -and $l.outwardIssue) { $other = $l.outwardIssue.key; $dir = 'outward' }
                elseif ($l.PSObject.Properties['inwardIssue'] -and $l.inwardIssue) { $other = $l.inwardIssue.key; $dir = 'inward' }
                if ($other) { $links += [pscustomobject]@{ TypeName = [string]$l.type.name; Dir = $dir; Other = [string]$other } }
            }
        }
        $webUrl = if ($ri.PSObject.Properties['webUrl']) { [string]$ri.webUrl } else { '' }
        $issues[[string]$ri.key] = [pscustomobject]@{
            Key = [string]$ri.key; Summary = [string](Get-Field $ri 'summary')
            Status = if ($statusObj) { [string]$statusObj.name } else { '' }
            StatusCat = if ($statusObj -and $statusObj.PSObject.Properties['statusCategory'] -and $statusObj.statusCategory) { [string]$statusObj.statusCategory.key } else { '' }
            Type = if ($typeObj) { [string]$typeObj.name } else { '' }
            Parent = if ($parentObj) { [string]$parentObj.key } else { '' }
            Desc = [string]$descText; WebUrl = $webUrl; Links = $links
        }
    }
}
else {
    # ----- Proposals load & normalize (nodes = slugs, edges = header fields) -----
    $bySlug = [ordered]@{}
    foreach ($f in Get-ProposalFiles $ProposalPath) {
        $slug = ConvertTo-Slug $f.Name
        if (-not $bySlug.Contains($slug)) { $bySlug[$slug] = @() }
        $bySlug[$slug] += $f
    }
    if ($bySlug.Count -eq 0) { Write-Error 'No proposal files found in -ProposalPath.'; exit 1 }
    foreach ($slug in $bySlug.Keys) {
        $title = ''; $status = ''; $bodyParts = @(); $links = @(); $stages = @()
        foreach ($f in $bySlug[$slug]) {
            # stav proposalu podle složky (completed/abandoned = není živý draft)
            $stages += switch -Regex ($f.FullName) {
                '[\\/]completed[\\/]' { 'completed'; break }
                '[\\/]abandoned[\\/]' { 'abandoned'; break }
                '[\\/]active[\\/]'    { 'active'; break }
                '[\\/]next[\\/]'      { 'next'; break }
                default               { 'next' }
            }
            $raw = Get-Content -LiteralPath $f.FullName -Raw
            $hb = Split-HeaderBody $raw
            $t = Get-ProposalTitle $hb.Header
            if ($t -and -not $title) { $title = $t }
            foreach ($ln in ($hb.Header -split '\r?\n')) {
                if ($ln -match '^\s*[-*]\s*\*\*Stav:\*\*\s*(.*)$' -and -not $status) { $status = $Matches[1].Trim() }
                if ($ln -match '^\s*[-*]\s*\*\*([^:*]+):\*\*\s*(.*)$') {
                    $fname = (Remove-Diacritics $Matches[1]).ToLowerInvariant().Trim()
                    if ($FieldMap.Contains($fname)) {
                        $map = $FieldMap[$fname]
                        foreach ($m in $MdLinkRx.Matches($Matches[2])) {
                            $target = $m.Groups[1].Value
                            $resolved = Join-Path $f.DirectoryName $target
                            if (-not (Test-Path -LiteralPath $resolved)) {
                                $script:missingTargets += @{ Self = $slug; Target = $target; Field = $fname }
                                continue
                            }
                            $links += [pscustomobject]@{ TypeName = $map.TypeName; Dir = $map.Dir; Other = (ConvertTo-Slug (Split-Path $target -Leaf)) }
                        }
                    }
                }
            }
            $bodyParts += $hb.Body
        }
        $stage = if ($stages -contains 'active') { 'active' } elseif ($stages -contains 'next') { 'next' }
                 elseif ($stages -contains 'completed') { 'completed' } else { 'abandoned' }
        if ($stage -eq 'active') { $proposalActive[$slug] = $true }
        if ($stage -eq 'active' -or $stage -eq 'next') { $proposalLive[$slug] = $true }
        $statusCat = switch ($stage) { 'completed' { 'done' } 'active' { 'indeterminate' } default { 'new' } }
        $issues[$slug] = [pscustomobject]@{
            Key = $slug; Summary = $title; Status = $status; StatusCat = $statusCat; Type = 'Proposal'; Parent = ''
            Desc = ($bodyParts -join "`n"); WebUrl = ''; Links = $links
        }
    }
}

if (-not $EpicKey) {
    $epic = $issues.Values | Where-Object { $_.Type -eq 'Epic' } | Select-Object -First 1
    if ($epic) { $EpicKey = $epic.Key }
}
$scopeKeys = @($issues.Keys | Where-Object { $_ -ne $EpicKey })

# base URL for ticket links in the wave table (explicit param wins, else any
# webUrl); Proposals mode: slugs are not Jira tickets — no links.
$jiraBase = ''
if ($Source -eq 'Proposals') { $jiraBase = '' }
elseif ($JiraBaseUrl) { $jiraBase = $JiraBaseUrl.TrimEnd('/') }
else {
    foreach ($i in $issues.Values) {
        if ($i.WebUrl -and $i.WebUrl -match '^(https?://[^/]+)') { $jiraBase = $Matches[1]; break }
    }
}

# ---------- canonical edge set ------------------------------------------------

function Get-EdgeCategory([string] $typeName) {
    switch -Regex ($typeName) {
        '^Blocks$'      { 'blocks' ; break }
        '^Issue split$' { 'split'  ; break }
        '^Relates$'     { 'relates'; break }
        default         { 'other'  }
    }
}

# key: "category|from|to" (relates: sorted endpoints); value: edge object
$edges = [ordered]@{}
foreach ($iss in $issues.Values) {
    foreach ($l in $iss.Links) {
        $cat = Get-EdgeCategory $l.TypeName
        switch ($cat) {
            'blocks'  { if ($l.Dir -eq 'outward') { $from = $iss.Key; $to = $l.Other } else { $from = $l.Other; $to = $iss.Key } }
            'split'   { if ($l.Dir -eq 'outward') { $from = $iss.Key; $to = $l.Other } else { $from = $l.Other; $to = $iss.Key } }
            'relates' { $pair = @($iss.Key, $l.Other) | Sort-Object; $from = $pair[0]; $to = $pair[1] }
            default   { if ($l.Dir -eq 'outward') { $from = $iss.Key; $to = $l.Other } else { $from = $l.Other; $to = $iss.Key } }
        }
        $id = "$cat|$($l.TypeName)|$from|$to"
        if (-not $edges.Contains($id)) {
            $edges[$id] = [pscustomobject]@{
                Category = $cat; TypeName = $l.TypeName; From = $from; To = $to
                SeenFrom = [System.Collections.Generic.HashSet[string]]::new()
            }
        }
        [void]$edges[$id].SeenFrom.Add($iss.Key)
    }
}
$edgeList = @($edges.Values)
$externalKeys = @($edgeList | ForEach-Object { $_.From; $_.To } |
    Where-Object { -not $issues.Contains($_) } | Sort-Object -Unique)

# ---------- proposal files (optional prose corpus) ----------------------------
# Jira mode only: attribute external proposal files to tickets for prose scanning.
# In Proposals mode the proposal bodies are already each node's own Desc, so this
# Jira-flavored attribution (and its PROPOSAL BEZ TIKETU finding) must not run.

$proposalProse = @{}   # ticketKey -> list of @{File; Text}
$unattributed = @()
if ($Source -eq 'Jira' -and $ProposalPath) {
    $mdFiles = foreach ($p in $ProposalPath) {
        if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -Recurse -Filter '*.md' -File }
        elseif (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p }
        else { Write-Warning "Proposal path not found: $p" }
    }
    foreach ($f in @($mdFiles | Where-Object { $_ })) {
        $text = Get-Content -LiteralPath $f.FullName -Raw
        $ticket = $null
        if ($text -match '\*\*Jira:\*\*\s*([A-Z][A-Z0-9]+-\d+)') { $ticket = $Matches[1] }
        elseif ($f.BaseName -match '(?i)(?:^|_)([a-z][a-z0-9]+)[_-](\d{2,})(?:_|$|-)') { $ticket = ('{0}-{1}' -f $Matches[1].ToUpper(), $Matches[2]) }
        if ($ticket) {
            if (-not $proposalProse.ContainsKey($ticket)) { $proposalProse[$ticket] = @() }
            $proposalProse[$ticket] += @{ File = $f.FullName; Text = $text }
            # stav proposalu podle složky (completed/abandoned = není živý draft)
            $stage = switch -Regex ($f.FullName) {
                '[\\/]completed[\\/]' { 'completed'; break }
                '[\\/]abandoned[\\/]' { 'abandoned'; break }
                '[\\/]active[\\/]'    { 'active'; break }
                '[\\/]next[\\/]'      { 'next'; break }
                default               { 'next' }
            }
            if ($stage -eq 'active') { $proposalActive[$ticket] = $true }
            if ($stage -eq 'active' -or $stage -eq 'next') { $proposalLive[$ticket] = $true }
        } else { $unattributed += $f.FullName }
    }
}

# ---------- prose scanning -----------------------------------------------------

# keyword -> assertion category (keywords diacritics-stripped, lowercase).
# Deliberately NO weak keywords ("potřebuje", "předpoklad", bare "závisí") —
# they misfire inside explanatory parentheses. Heuristic favors precision.
$keywordMap = @(
    @{ K = 'vycleneno z';    C = 'splitFrom' }, @{ K = 'vyclenen z'; C = 'splitFrom' },
    @{ K = 'split from';     C = 'splitFrom' },
    @{ K = 'vycleneno do';   C = 'splitTo' },   @{ K = 'vycleneno';  C = 'splitTo' },
    @{ K = 'vyclenuje';      C = 'splitTo' },   @{ K = 'split to';   C = 'splitTo' },
    @{ K = 'blokovano';      C = 'blockedBy' }, @{ K = 'blokovan';   C = 'blockedBy' },
    @{ K = 'blocked by';     C = 'blockedBy' }, @{ K = 'zavisi na';  C = 'blockedBy' },
    @{ K = 'ceka na';        C = 'blockedBy' }, @{ K = 'tvrdy blokator'; C = 'blockedBy' },
    @{ K = 'blokuje';        C = 'blocks' },    @{ K = 'odemyka';    C = 'blocks' },
    @{ K = 'blocks';         C = 'blocks' },    @{ K = 'unlocks';    C = 'blocks' },
    @{ K = 'souvisi';        C = 'relates' },   @{ K = 'relates';    C = 'relates' },
    @{ K = 'related';        C = 'relates' }
)
$quoteChars = [char[]]@([char]0x201E, [char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019,
    [char]0x201A, [char]0x00AB, [char]0x00BB, '"', "'", '`')

function Find-KeywordIn([string] $window, [bool] $fromEnd) {
    # Returns category of the valid keyword occurrence nearest to the mention,
    # skipping occurrences adjacent to a quote char (meta-mentions like
    # (dříve „blokuje")). $fromEnd = window precedes the mention.
    $best = $null; $bestDist = [int]::MaxValue; $bestLen = 0
    foreach ($kw in $keywordMap) {
        $k = [string]$kw.K; $searchFrom = 0
        while (($idx = $window.IndexOf($k, $searchFrom)) -ge 0) {
            $searchFrom = $idx + 1
            $prev = if ($idx -gt 0) { $window[$idx - 1] } else { ' ' }
            $nextPos = $idx + $k.Length
            $next = if ($nextPos -lt $window.Length) { $window[$nextPos] } else { ' ' }
            if ($quoteChars -contains $prev -or $quoteChars -contains $next) { continue }
            $dist = if ($fromEnd) { $window.Length - ($idx + $k.Length) } else { $idx }
            if ($dist -lt $bestDist -or ($dist -eq $bestDist -and $k.Length -gt $bestLen)) {
                $best = [string]$kw.C; $bestDist = $dist; $bestLen = $k.Length
            }
        }
    }
    return $best
}

function Get-ProseAssertions([string] $selfKey, [string] $text, [string] $source, [string[]] $prefixes) {
    # Returns: assertion objects (Self, Category|$null=bare, Other, Source)
    $out = @()
    if (-not $text) { return $out }
    # two parallel strings with identical indexes: original-case (key regex,
    # uppercase keys only -> no hits on URLs like browse/pay-501 or "utf-8")
    # and normalized (diacritics-stripped lowercase, keyword search).
    # Newlines become a sentinel so keyword windows never cross lines.
    $orig = ($text -replace '\r\n?|\n', [string][char]0x00B6) -replace '[ \t]+', ' '
    $flat = (Remove-Diacritics $orig).ToLowerInvariant()
    if ($flat.Length -ne $orig.Length) { $orig = $flat }  # index-alignment guard (exotic chars)
    # Build mentions: Jira mode -> ticket keys; Proposals mode -> markdown links to *.md.
    # NOTE: uses $script:Source (the -Source mode flag), not the same-named
    # local $source parameter above (a corpus-source label like "popis pa") —
    # PowerShell variable names are case-insensitive, so a bare $Source here
    # would silently resolve to the local parameter instead.
    # Len = width of the mention text to skip when scanning the after-window.
    # Jira: skip the whole key (old behavior $m.Index + $m.Length). Proposals:
    # 0 — a markdown link's "](…)" has no trailing token before the after-window.
    $mentions = @()   # @{ Index; Other; Len }
    if ($script:Source -eq 'Proposals') {
        foreach ($m in $MdLinkRx.Matches($orig)) {
            $mentions += @{ Index = $m.Index; Other = (ConvertTo-Slug (Split-Path $m.Groups[1].Value -Leaf)); Len = 0 }
        }
    } else {
        $keyRx = [regex]'\b([A-Z][A-Z0-9]+-\d+)\b'
        foreach ($m in $keyRx.Matches($orig)) { $mentions += @{ Index = $m.Index; Other = $m.Groups[1].Value; Len = $m.Length } }
    }
    $nl = [char]0x00B6
    $seen = @{}
    foreach ($mn in $mentions) {
        $other = $mn.Other
        if ($other -eq $selfKey) { continue }
        if ($prefixes -and $script:Source -eq 'Jira' -and -not ($prefixes | Where-Object { $other.StartsWith("$_-") })) { continue }
        $mIndex = $mn.Index
        # before-window: up to 90 chars back, bounded by start of line
        $winStart = [Math]::Max(0, $mIndex - 90)
        $before = $flat.Substring($winStart, $mIndex - $winStart)
        $cut = $before.LastIndexOf($nl); if ($cut -ge 0) { $before = $before.Substring($cut + 1) }
        $best = Find-KeywordIn $before $true
        if (-not $best) {
            # after-window: up to 40 chars forward, bounded by end of line
            $aStart = $mIndex + $mn.Len
            $after = $flat.Substring($aStart, [Math]::Min(40, $flat.Length - $aStart))
            $cut = $after.IndexOf($nl); if ($cut -ge 0) { $after = $after.Substring(0, $cut) }
            $best = Find-KeywordIn $after $false
        }
        $sig = "$other|$best"
        if ($seen.ContainsKey($sig)) { continue }
        $seen[$sig] = $true
        $out += [pscustomobject]@{ Self = $selfKey; Category = $best; Other = $other; Source = $source }
    }
    return $out
}

# ---------- graph outputs ------------------------------------------------------

function ConvertTo-NodeId([string] $key) { return ($key -replace '[^A-Za-z0-9]', '') }
function Get-Label([string] $key) {
    if ($issues.Contains($key)) {
        $i = $issues[$key]
        $sum = $i.Summary; if ($sum.Length -gt 55) { $sum = $sum.Substring(0, 52) + '…' }
        $sum = $sum -replace '"', "'"
        return ('{0}<br/><i>{1}</i> · {2}' -f $key, $sum, $i.Status)
    }
    return "$key (mimo epic)"
}

$blocksEdges  = @($edgeList | Where-Object Category -eq 'blocks')
$splitEdges   = @($edgeList | Where-Object Category -eq 'split')
$relatesEdges = @($edgeList | Where-Object Category -eq 'relates')
$otherEdges   = @($edgeList | Where-Object Category -eq 'other')

$mermaidSb = [Text.StringBuilder]::new()
[void]$mermaidSb.AppendLine('```mermaid')
[void]$mermaidSb.AppendLine('flowchart TD')
foreach ($k in $scopeKeys) { [void]$mermaidSb.AppendLine(('    {0}["{1}"]' -f (ConvertTo-NodeId $k), (Get-Label $k))) }
foreach ($k in $externalKeys) { [void]$mermaidSb.AppendLine(('    {0}(["{1}"]):::ext' -f (ConvertTo-NodeId $k), (Get-Label $k))) }
foreach ($e in $blocksEdges)  { [void]$mermaidSb.AppendLine(('    {0} --> {1}' -f (ConvertTo-NodeId $e.From), (ConvertTo-NodeId $e.To))) }
foreach ($e in $splitEdges)   { [void]$mermaidSb.AppendLine(('    {0} -. vyčleněno .-> {1}' -f (ConvertTo-NodeId $e.From), (ConvertTo-NodeId $e.To))) }
foreach ($e in $relatesEdges) { [void]$mermaidSb.AppendLine(('    {0} -.- {1}' -f (ConvertTo-NodeId $e.From), (ConvertTo-NodeId $e.To))) }
foreach ($e in $otherEdges)   { [void]$mermaidSb.AppendLine(('    {0} -- {1} --> {2}' -f (ConvertTo-NodeId $e.From), $e.TypeName, (ConvertTo-NodeId $e.To))) }
if ($externalKeys.Count -gt 0) { [void]$mermaidSb.AppendLine('    classDef ext stroke-dasharray: 5 5,opacity:0.75;') }
[void]$mermaidSb.AppendLine('```')

# indented list ("odsazení = odemyká"); issues blocked by N>1 blockers appear under each
$blockedBy = @{}; $blocksOut = @{}
foreach ($k in $scopeKeys + $externalKeys) { $blockedBy[$k] = @(); $blocksOut[$k] = @() }
foreach ($e in $blocksEdges) {
    if ($blocksOut.ContainsKey($e.From)) { $blocksOut[$e.From] += $e.To }
    if ($blockedBy.ContainsKey($e.To))   { $blockedBy[$e.To]   += $e.From }
}
function Get-NodeAnnotations([string] $k) {
    $ann = @()
    foreach ($e in $splitEdges)   { if ($e.To -eq $k) { $ann += "vyčleněno z $($e.From)" }; if ($e.From -eq $k) { $ann += "vyčleňuje $($e.To)" } }
    foreach ($e in $relatesEdges) { if ($e.From -eq $k) { $ann += "souvisí $($e.To)" }; if ($e.To -eq $k) { $ann += "souvisí $($e.From)" } }
    if ($ann.Count -gt 0) { return ' _(' + ($ann -join '; ') + ')_' }
    return ''
}
$listSb = [Text.StringBuilder]::new()
function Write-ListNode([string] $k, [int] $depth, [System.Collections.Generic.HashSet[string]] $path) {
    $indent = '    ' * $depth
    $iss = if ($issues.Contains($k)) { $issues[$k] } else { $null }
    $line = if ($iss) { ('{0}* **{1}** — {2} · _{3}_' -f $indent, $k, $iss.Summary, $iss.Status) }
            else      { ('{0}* **{1}** _(mimo epic)_' -f $indent, $k) }
    $multi = @(@($blockedBy[$k]) | Where-Object { $_ })
    if ($depth -gt 0 -and $multi.Count -gt 1) { $line += (' _(všechny blokátory: {0})_' -f ($multi -join ', ')) }
    $line += (Get-NodeAnnotations $k)
    if ($path.Contains($k)) { [void]$listSb.AppendLine("$line ⚠️ **cyklus!**"); return }
    [void]$listSb.AppendLine($line)
    [void]$path.Add($k)
    foreach ($child in @($blocksOut[$k] | Sort-Object -Unique)) { Write-ListNode $child ($depth + 1) $path }
    [void]$path.Remove($k)
}
$roots    = @($scopeKeys | Where-Object { @($blockedBy[$_]).Count -eq 0 -and @($blocksOut[$_]).Count -gt 0 })
$isolated = @($scopeKeys | Where-Object { @($blockedBy[$_]).Count -eq 0 -and @($blocksOut[$_]).Count -eq 0 })
$extRoots = @($externalKeys | Where-Object { @($blocksOut[$_]).Count -gt 0 })
if ($extRoots.Count -gt 0) {
    [void]$listSb.AppendLine('**Externí předpoklady (mimo epic):**'); [void]$listSb.AppendLine('')
    foreach ($r in $extRoots) { Write-ListNode $r 0 ([System.Collections.Generic.HashSet[string]]::new()) }
    [void]$listSb.AppendLine('')
}
if ($roots.Count -gt 0) {
    [void]$listSb.AppendLine('**Základy (nic je neblokuje):**'); [void]$listSb.AppendLine('')
    foreach ($r in $roots) { Write-ListNode $r 0 ([System.Collections.Generic.HashSet[string]]::new()) }
    [void]$listSb.AppendLine('')
}
if ($isolated.Count -gt 0) {
    [void]$listSb.AppendLine('**Bez tvrdé závislosti:**'); [void]$listSb.AppendLine('')
    foreach ($r in $isolated) { Write-ListNode $r 0 ([System.Collections.Generic.HashSet[string]]::new()) }
}

# ---------- wave table (Gantt-like: column = dependency wave) ------------------
# Wave(node) = longest Blocks chain from a root (0 = nothing blocks it). Each
# node sits in the column of its wave, so every child is to the RIGHT of its
# blocker. Rows are ordered by dependency: a node is placed on the first free
# row right after its LAST-placed blocker (roots first, by area then key). The
# area emoji is inline before the ticket; summaries are not truncated. Improved,
# portable form of the indented list (renders everywhere, clickable ticket
# links; mermaid stays opt-in via -Mermaid).
$wave = @{}
function Resolve-Wave([string] $k, [System.Collections.Generic.HashSet[string]] $stack) {
    if ($wave.ContainsKey($k)) { return $wave[$k] }
    if ($stack.Contains($k)) { return 0 }   # cycle guard (reported by the oracle)
    $preds = @(@($blockedBy[$k]) | Where-Object { $_ })
    if ($preds.Count -eq 0) { $wave[$k] = 0; return 0 }
    [void]$stack.Add($k)
    $max = 0
    foreach ($p in $preds) { $pv = (Resolve-Wave $p $stack) + 1; if ($pv -gt $max) { $max = $pv } }
    [void]$stack.Remove($k)
    $wave[$k] = $max
    return $max
}
$allNodes = @($scopeKeys + $externalKeys)
foreach ($k in $allNodes) { [void](Resolve-Wave $k ([System.Collections.Generic.HashSet[string]]::new())) }
$maxWave = 0; foreach ($k in $allNodes) { if ($wave[$k] -gt $maxWave) { $maxWave = $wave[$k] } }

# area = dependency STREAM, deduced dynamically from a node's primordial
# ancestors (the roots it transitively depends on via Blocks). Each foundational
# root that HAS descendants gets an emoji from a palette (assigned by stream size);
# a node carries the emoji of every such root it descends from (⇒ possibly several).
# Standalone roots (no descendants) are neutral (⬜). No hardcoded taxonomy.
$rootAncestors = @{}   # node -> string[] of root keys it descends from (itself if a root)
function Get-RootAncestors([string] $k, [System.Collections.Generic.HashSet[string]] $stack) {
    if ($rootAncestors.ContainsKey($k)) { return $rootAncestors[$k] }
    if ($stack.Contains($k)) { return @() }   # cycle guard
    $preds = @(@($blockedBy[$k]) | Where-Object { $_ })
    if ($preds.Count -eq 0) { $rootAncestors[$k] = @($k); return $rootAncestors[$k] }
    [void]$stack.Add($k)
    $set = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($p in $preds) { foreach ($r in (Get-RootAncestors $p $stack)) { [void]$set.Add($r) } }
    [void]$stack.Remove($k)
    $rootAncestors[$k] = @($set)
    return $rootAncestors[$k]
}
foreach ($k in $allNodes) { [void](Get-RootAncestors $k ([System.Collections.Generic.HashSet[string]]::new())) }
$rootsAll = @($allNodes | Where-Object { @(@($blockedBy[$_]) | Where-Object { $_ }).Count -eq 0 })
$rootDescCount = @{}; foreach ($r in $rootsAll) { $rootDescCount[$r] = 0 }
foreach ($k in $allNodes) {
    foreach ($r in $rootAncestors[$k]) { if ($r -ne $k -and $rootDescCount.ContainsKey($r)) { $rootDescCount[$r]++ } }
}
# coloring roots = foundational streams (roots with >=1 descendant), biggest first
$coloringRoots = @($rootsAll | Where-Object { $rootDescCount[$_] -gt 0 } |
    Sort-Object @{ E = { $rootDescCount[$_] }; Descending = $true }, @{ E = { $_ } })
$palette = @('🟦', '🟩', '🟨', '🟧', '🟥', '🟪', '🟫', '🔵', '🟢', '🟡', '🟠', '🔴')
$rootEmoji = [ordered]@{}
for ($i = 0; $i -lt $coloringRoots.Count; $i++) { $rootEmoji[$coloringRoots[$i]] = $palette[$i % $palette.Count] }
$colorIndex = @{}; for ($i = 0; $i -lt $coloringRoots.Count; $i++) { $colorIndex[$coloringRoots[$i]] = $i }
function Get-Emoji([string] $k) {
    $rs = @($rootAncestors[$k] | Where-Object { $rootEmoji.Contains($_) } | Sort-Object @{ E = { $colorIndex[$_] } })
    if ($rs.Count -eq 0) { return '⬜' }
    return -join ($rs | ForEach-Object { $rootEmoji[$_] })
}
# dynamic legend (root emoji -> which foundational ticket it marks)
$legendParts = foreach ($r in $coloringRoots) {
    $comp = if ($issues.Contains($r) -and $issues[$r].Summary -match '\[([^\]]+)\]') { " [$($Matches[1])]" } else { '' }
    "$($rootEmoji[$r]) od $r$comp"
}
$emojiLegend = ($legendParts -join ' · ')
if (@($allNodes | Where-Object { (Get-Emoji $_) -eq '⬜' }).Count -gt 0) {
    $emojiLegend = if ($emojiLegend) { "$emojiLegend · ⬜ samostatné" } else { '⬜ samostatné' }
}

function Get-TicketUrl([string] $k) {
    if ($issues.Contains($k) -and $issues[$k].WebUrl) { return $issues[$k].WebUrl }
    if ($jiraBase) { return "$jiraBase/browse/$k" }
    return ''
}
function Test-Unblocked([string] $k) {
    # odblokováno = všechny přímé Blocks-blokátory jsou hotové (statusCategory=done).
    # Blokátor s neznámým stavem (externí, mimo snapshot) se konzervativně počítá
    # jako blokující — pro přesnost doplň externí blokátory druhým snapshotem.
    $preds = @(@($blockedBy[$k]) | Where-Object { $_ })
    if ($preds.Count -eq 0) { return $true }
    foreach ($p in $preds) {
        if (-not ($issues.Contains($p) -and $issues[$p].StatusCat -eq 'done')) { return $false }
    }
    return $true
}
function Get-StatusGlyph([string] $k) {
    # Jedna sloučená stavová ikona (fáze × připravenost × existence proposalu).
    # Kaskáda, první shoda vyhrává. Symbolická rodina (ne čtverec/kolečko), ať
    # se neplete se stream-emoji. V Proposals režimu vychází StatusCat i
    # proposalLive/proposalActive ze stage složky proposalu (uzly = proposaly).
    if ($NoStatus) { return '' }
    if (-not $issues.Contains($k)) { return '' }   # externí uzel bez známého stavu
    $cat = $issues[$k].StatusCat
    if ($cat -eq 'done') { return '✅' }                                    # hotovo
    if ($cat -eq 'indeterminate' -or $proposalActive.ContainsKey($k)) { return '🔨' }  # implementuje se
    # To-Do (kategorie 'new' nebo neznámá): rozliš připravenost × proposal
    $unblocked = Test-Unblocked $k
    if (-not $proposalInfoAvailable) {
        # bez -ProposalPath: 4-stavová degradace (bez rozlišení proposalu)
        if ($unblocked) { return '▶️' } else { return '⛔' }
    }
    if ($proposalLive.ContainsKey($k)) {
        if ($unblocked) { return '▶️' } else { return '⏳' }   # návrh hotov: připraveno / čeká
    }
    if ($unblocked) { return '🆕' } else { return '⛔' }        # bez návrhu: k rozpracování / blokováno
}
function Get-CellText([string] $k) {
    $url = Get-TicketUrl $k
    $keyMd = if ($url) { "[$k]($url)" } else { "**$k**" }
    # full ticket title, verbatim (concrete, incl. component) — no truncation
    $sum = if ($issues.Contains($k)) { $issues[$k].Summary } else { '(mimo epic)' }
    $sum = $sum -replace '\|', '\|' -replace '\[', '\[' -replace '\]', '\]'   # keep brackets literal, not a link
    $statusGlyph = Get-StatusGlyph $k
    $prefix = if ($statusGlyph) { "$statusGlyph $(Get-Emoji $k)" } else { Get-Emoji $k }
    $cell = "$prefix $keyMd $sum"
    $blk = @(@($blockedBy[$k]) | Where-Object { $_ } | ForEach-Object { ($_ -split '-')[-1] })
    if ($blk.Count -gt 0) { $cell += " ←$([string]::Join(',', $blk))" }
    return $cell
}

# dependency-driven row order: roots first (biggest stream first, then key),
# then each node inserted on the first free row right after its last-placed blocker.
$rowsOrder = [System.Collections.Generic.List[string]]::new()
$placedRow = @{}
$rootNodes = @($rootsAll |
    Sort-Object @{ E = { if ($colorIndex.ContainsKey($_)) { $colorIndex[$_] } else { 999 } } }, @{ E = { $_ } })
foreach ($r in $rootNodes) { [void]$rowsOrder.Add($r); $placedRow[$r] = $true }
while ($rowsOrder.Count -lt $allNodes.Count) {
    $ready = @($allNodes | Where-Object {
            -not $placedRow.ContainsKey($_) -and
            @(@($blockedBy[$_]) | Where-Object { $_ } | Where-Object { -not $placedRow.ContainsKey($_) }).Count -eq 0 })
    if ($ready.Count -eq 0) {   # cycle / unreachable — append deterministically
        foreach ($k in @($allNodes | Where-Object { -not $placedRow.ContainsKey($_) } | Sort-Object)) {
            [void]$rowsOrder.Add($k); $placedRow[$k] = $true
        }
        break
    }
    $withAnchor = foreach ($k in $ready) {
        $ai = 0
        foreach ($b in @(@($blockedBy[$k]) | Where-Object { $_ })) { $bi = $rowsOrder.IndexOf($b); if ($bi -gt $ai) { $ai = $bi } }
        [pscustomobject]@{ Key = $k; Anchor = $ai; Wave = $wave[$k] }
    }
    $pick = @($withAnchor | Sort-Object Anchor, Wave, Key)[0]
    $insertAt = $pick.Anchor + 1
    while ($insertAt -lt $rowsOrder.Count -and $wave[$rowsOrder[$insertAt]] -ge $pick.Wave) { $insertAt++ }
    $rowsOrder.Insert($insertAt, $pick.Key)
    $placedRow[$pick.Key] = $true
}

$tableSb = [Text.StringBuilder]::new()
$hdr = '|'; $sep = '|'
for ($w = 0; $w -le $maxWave; $w++) {
    $hdr += (' {0} |' -f $(if ($w -eq 0) { 'Vlna 0 (ihned)' } else { "Vlna $w" }))
    $sep += '---|'
}
[void]$tableSb.AppendLine($hdr)
[void]$tableSb.AppendLine($sep)
foreach ($k in $rowsOrder) {
    $cells = @('') * ($maxWave + 1)
    $cells[$wave[$k]] = Get-CellText $k
    [void]$tableSb.AppendLine('| ' + ($cells -join ' | ') + ' |')
}

# ---------- consistency oracle -------------------------------------------------

$findings = @()   # @{Severity('CHYBA'|'VAROVÁNÍ'|'INFO'); Code; Text}
# Mode-aware finding lexicon (Jira wording vs proposal wording).
$script:Lex = if ($Source -eq 'Proposals') {
    @{ Noun='odkaz'; Asym='ASYMETRICKÝ ODKAZ'; ProseNoLink='PROSE BEZ ODKAZU'; LinkTypeMismatch='TYP ODKAZU NESOUHLASÍ';
       LinkNoProse='ODKAZ BEZ PROSE'; External='EXTERNÍ CÍL'; SourcePhrase='hlaviček proposalů' }
} else {
    @{ Noun='link'; Asym='ASYMETRICKÝ LINK'; ProseNoLink='PROSE BEZ LINKU'; LinkTypeMismatch='TYP LINKU NESOUHLASÍ';
       LinkNoProse='LINK BEZ PROSE'; External='EXTERNÍ TIKET'; SourcePhrase='Jira linků' }
}
if ($Check) {
    # 1. asymmetric intra-scope links (both endpoints in snapshot, link listed by one)
    foreach ($e in $edgeList) {
        $bothIn = $issues.Contains($e.From) -and $issues.Contains($e.To)
        if ($bothIn -and $e.SeenFrom.Count -lt 2) {
            $listedBy = @($e.SeenFrom) -join ', '
            $sev = if ($Source -eq 'Proposals') { 'VAROVÁNÍ' } else { 'CHYBA' }
            $tail = if ($Source -eq 'Proposals') { 'protistrana zrcadlové pole neuvádí (nezrcadleno — hrana platí).' } `
                    else { 'protistrana ho nemá (nekonzistentní snapshot / poškozená data).' }
            $findings += @{ Severity = $sev; Code = $Lex.Asym
                Text = "$($e.TypeName) $($e.From) → $($e.To): $($Lex.Noun) uvádí jen $listedBy, $tail" }
        }
    }
    # 2+3. prose vs links
    # mention regex is limited to project prefixes seen in the snapshot (plus
    # -ProjectKeys) so finding IDs like WF-6/KI-1 are not mistaken for tickets
    $allowedPrefixes = @(
        @($issues.Keys) + @($externalKeys) + @($EpicKey) + @($ProjectKeys) |
        Where-Object { $_ } | ForEach-Object { ($_ -split '-')[0] } | Sort-Object -Unique)
    $assertions = @(); $mentionsByIssue = @{}
    foreach ($iss in $issues.Values) {
        if ($iss.Key -eq $EpicKey -and -not $IncludeEpicProse) { continue }
        $corpus = @(@{ Text = $iss.Desc; Source = "popis $($iss.Key)" })
        if ($proposalProse.ContainsKey($iss.Key)) {
            foreach ($p in $proposalProse[$iss.Key]) { $corpus += @{ Text = $p.Text; Source = "proposal $(Split-Path $p.File -Leaf)" } }
        }
        foreach ($c in $corpus) {
            $res = Get-ProseAssertions $iss.Key $c.Text $c.Source $allowedPrefixes
            foreach ($a in $res) {
                if (-not $mentionsByIssue.ContainsKey($iss.Key)) { $mentionsByIssue[$iss.Key] = @{} }
                $mentionsByIssue[$iss.Key][$a.Other] = $true
                if ($a.Category) { $assertions += $a }
            }
        }
    }
    function Test-EdgeExists([string] $cat, [string] $from, [string] $to) {
        switch ($cat) {
            'blocks'  { return [bool]($blocksEdges | Where-Object { $_.From -eq $from -and $_.To -eq $to }) }
            'split'   { return [bool]($splitEdges  | Where-Object { $_.From -eq $from -and $_.To -eq $to }) }
            'relates' { $p = @($from, $to) | Sort-Object
                        return [bool]($relatesEdges | Where-Object { $_.From -eq $p[0] -and $_.To -eq $p[1] }) }
        }
        return $false
    }
    foreach ($a in $assertions) {
        $ok = switch ($a.Category) {
            'blockedBy' { Test-EdgeExists 'blocks' $a.Other $a.Self }
            'blocks'    { Test-EdgeExists 'blocks' $a.Self $a.Other }
            'splitFrom' { Test-EdgeExists 'split' $a.Other $a.Self }
            'splitTo'   { Test-EdgeExists 'split' $a.Self $a.Other }
            'relates'   { Test-EdgeExists 'relates' $a.Self $a.Other }
        }
        if (-not $ok) {
            $anyEdge = @($edgeList | Where-Object {
                ($_.From -eq $a.Self -and $_.To -eq $a.Other) -or ($_.From -eq $a.Other -and $_.To -eq $a.Self) })
            $catCz = @{ blockedBy = 'blokováno'; blocks = 'blokuje'; splitFrom = 'vyčleněno z'; splitTo = 'vyčleněno do'; relates = 'souvisí' }[$a.Category]
            if ($anyEdge.Count -gt 0) {
                $have = ($anyEdge | ForEach-Object { "$($_.TypeName) $($_.From)→$($_.To)" }) -join '; '
                $findings += @{ Severity = 'VAROVÁNÍ'; Code = $Lex.LinkTypeMismatch
                    Text = "$($a.Source): prose tvrdí «$($a.Self) $catCz $($a.Other)», ale v Jira je: $have." }
            } else {
                $findings += @{ Severity = 'CHYBA'; Code = $Lex.ProseNoLink
                    Text = "$($a.Source): prose tvrdí «$($a.Self) $catCz $($a.Other)», ale žádný Jira link mezi nimi neexistuje." }
            }
        }
    }
    foreach ($e in $edgeList) {
        if (-not ($issues.Contains($e.From) -and $issues.Contains($e.To))) { continue }
        if ($e.From -eq $EpicKey -or $e.To -eq $EpicKey) { continue }
        $mentioned = ($mentionsByIssue.ContainsKey($e.From) -and $mentionsByIssue[$e.From].ContainsKey($e.To)) -or
                     ($mentionsByIssue.ContainsKey($e.To)   -and $mentionsByIssue[$e.To].ContainsKey($e.From))
        if (-not $mentioned) {
            $findings += @{ Severity = 'VAROVÁNÍ'; Code = $Lex.LinkNoProse
                Text = "Link $($e.TypeName) $($e.From) → $($e.To) není zmíněn v popisu ani proposalu žádné strany — chybí zdůvodnění (prose vysvětluje PROČ)." }
        }
    }
    # 4. externals
    foreach ($k in $externalKeys) {
        $rel = ($edgeList | Where-Object { $_.From -eq $k -or $_.To -eq $k } |
            ForEach-Object { "$($_.TypeName) $($_.From)→$($_.To)" }) -join '; '
        $findings += @{ Severity = 'INFO'; Code = $Lex.External
            Text = "$k je mimo snapshot (externí závislost): $rel. Zvaž doplnění do snapshotu druhým dotazem." }
    }
    # 4b. broken header links (proposal mode)
    foreach ($mt in $script:missingTargets) {
        $findings += @{ Severity = 'CHYBA'; Code = 'CHYBĚJÍCÍ CÍL'
            Text = "$($mt.Self): pole «$($mt.Field)» odkazuje na «$($mt.Target)», ale soubor neexistuje." }
    }
    # 5. Blocks cycles (DFS)
    $visited = @{}; $inStack = @{}
    function Find-Cycle([string] $k, [System.Collections.Generic.List[string]] $stack) {
        $visited[$k] = $true; $inStack[$k] = $true; $stack.Add($k)
        foreach ($n in @($blocksOut[$k])) {
            if (-not $blocksOut.ContainsKey($n)) { continue }
            if ($inStack.ContainsKey($n) -and $inStack[$n]) {
                $ix = $stack.IndexOf($n)
                $cyc = ($stack.GetRange($ix, $stack.Count - $ix) + $n) -join ' → '
                $script:findings += @{ Severity = 'CHYBA'; Code = 'CYKLUS'; Text = "Cyklus v Blocks závislostech: $cyc." }
            } elseif (-not $visited.ContainsKey($n)) { Find-Cycle $n $stack }
        }
        $inStack[$k] = $false; $stack.RemoveAt($stack.Count - 1)
    }
    foreach ($k in $scopeKeys) { if (-not $visited.ContainsKey($k)) { Find-Cycle $k ([System.Collections.Generic.List[string]]::new()) } }
    foreach ($f in $unattributed) {
        $findings += @{ Severity = 'INFO'; Code = 'PROPOSAL BEZ TIKETU'
            Text = "Proposal $f nemá rozpoznatelný tiket (chybí «**Jira:** KEY» i kód v názvu) — z prose kontroly vynechán." }
    }
    # 6. ticket <-> proposal link presence/currency (Jira mode with -ProposalPath only —
    #    in Proposals mode the nodes ARE the proposal files, there is no reverse link).
    #    The proposal->ticket binding comes from the proposal's "**Jira:**" header;
    #    here we check the REVERSE convenience link (ticket description -> proposal).
    #    Severity is VAROVÁNÍ, not CHYBA: a commit-pinned link cannot exist before the
    #    window's commit, so a pre-commit -Check would hard-fail on freshly created
    #    tickets — the workflow refreshes links post-commit, the oracle just surfaces drift.
    if ($Source -eq 'Jira' -and $proposalInfoAvailable) {
        $knownProposalNames = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($lst in $proposalProse.Values) { foreach ($p in $lst) { [void]$knownProposalNames.Add((Split-Path $p.File -Leaf)) } }
        foreach ($p in $unattributed) { [void]$knownProposalNames.Add((Split-Path $p -Leaf)) }
        # 6a. ticket has an attributed proposal but its description does not reference it
        foreach ($iss in $issues.Values) {
            if ($iss.Key -eq $EpicKey -or -not $proposalProse.ContainsKey($iss.Key)) { continue }
            $names = @($proposalProse[$iss.Key] | ForEach-Object { Split-Path $_.File -Leaf } | Sort-Object -Unique)
            $referenced = @($names | Where-Object { $iss.Desc -and $iss.Desc.Contains($_) })
            if ($referenced.Count -eq 0) {
                $findings += @{ Severity = 'VAROVÁNÍ'; Code = 'TIKET BEZ ODKAZU NA PROPOSAL'
                    Text = "$($iss.Key): má přiřazený proposal ($($names -join ', ')), ale popis tiketu na něj neodkazuje. Doplň řádek «**Návrh (proposal):**» s commit-pinned odkazem (tvar viz mb-jira-update §7)." }
            }
        }
        # 6b. description references a proposal_*.md that is not among known proposals (renamed/moved/deleted)
        $propRefRx = [regex]'proposal_[A-Za-z0-9_]+(?:-design)?\.md'
        foreach ($iss in $issues.Values) {
            if ($iss.Key -eq $EpicKey -or -not $iss.Desc) { continue }
            $seenRef = @{}
            foreach ($m in $propRefRx.Matches($iss.Desc)) {
                $name = $m.Value
                if ($seenRef.ContainsKey($name)) { continue }
                $seenRef[$name] = $true
                if (-not $knownProposalNames.Contains($name)) {
                    $findings += @{ Severity = 'VAROVÁNÍ'; Code = 'ODKAZ NA NEEXISTUJÍCÍ PROPOSAL'
                        Text = "$($iss.Key): popis odkazuje na «$name», ale takový proposal mezi známými (-ProposalPath) není — přejmenován/přesunut/smazán? Obnov odkaz." }
                }
            }
        }
    }
    if (@($findings | Where-Object { $_.Severity -eq 'CHYBA' }).Count -gt 0) { $script:ExitCode = 2 }
}

# ---------- report -------------------------------------------------------------

$report = [Text.StringBuilder]::new()
$epicLabel = if ($EpicKey) { $EpicKey } else { '(epic nenalezen)' }
[void]$report.AppendLine("# Graf závislostí epiku $epicLabel")
[void]$report.AppendLine('')
if ($Source -eq 'Proposals') {
    [void]$report.AppendLine(("_Vygenerováno z {0} (vstup: {1}; uzlů: {2}; hran: {3}). Graf needitovat ručně — regenerovat tímto nástrojem._" -f `
        $Lex.SourcePhrase, (($ProposalPath | Where-Object { $_ } | ForEach-Object { Split-Path $_ -Leaf }) -join ', '), $scopeKeys.Count, $edgeList.Count))
} else {
    [void]$report.AppendLine(("_Vygenerováno z Jira linků (snapshot: {0}; tiketů: {1}; hran: {2}). Graf needitovat ručně — regenerovat tímto nástrojem._" -f `
        (($InputFile | Where-Object { $_ } | ForEach-Object { Split-Path $_ -Leaf }) -join ', '), $scopeKeys.Count, $edgeList.Count))
}
[void]$report.AppendLine('')
if ($Mermaid) {
    [void]$report.AppendLine('## Mermaid')
    [void]$report.AppendLine('')
    [void]$report.AppendLine("_Plná šipka `A --> B` = A blokuje B (A odemyká B). Tečkovaně: vyčlenění (se šipkou) a souvislost (bez šipky). Čárkovaný uzel = mimo epic._")
    [void]$report.AppendLine('')
    [void]$report.Append($mermaidSb.ToString())
    [void]$report.AppendLine('')
}
if ($Source -eq 'Proposals') {
    [void]$report.AppendLine('## Tabulka vln (do přehledového dokumentu)')
} else {
    [void]$report.AppendLine('## Tabulka vln (do popisu epicu)')
}
[void]$report.AppendLine('')
$keyNote = if ($Source -eq 'Proposals') { 'Klíč = slug proposalu.' } else { 'Klíč odkazuje na Jiru.' }
[void]$report.AppendLine("Sloupec = vlna (nejdřívější start podle tvrdých ``Blocks`` závislostí; vlna 0 = nic neblokuje). Tiket je ve sloupci své vlny, takže každé dítě stojí napravo od svého blokátoru; ``←NNNN`` = přímý blokátor (poslední segment klíče). Řádky jsou seřazené podle závislostí — tiket je na řádku hned za posledním svým blokátorem. $keyNote Vazby ``souvisí``/``vyčleněno`` zde nejsou (nejsou to tvrdé závislosti) — pro plný obrázek generuj Mermaid přes ``-Mermaid``.")
[void]$report.AppendLine('')
if (-not $NoStatus) {
    if ($Source -eq 'Proposals') {
        [void]$report.AppendLine('**První ikona = stav proposalu** (fáze složky + připravenost, sloučeno do jedné): ✅ hotovo (completed) · 🔨 implementuje se (active) · ▶️ připraveno k implementaci (odblokováno) · ⏳ čeká na blokátory · ⛔ blokováno. Odblokováno = všechny `Blocks`-blokátory hotové.')
    } else {
        [void]$report.AppendLine('**První ikona = stav tiketu** (JIRA stav + připravenost + existence návrhu, sloučeno do jedné): ✅ hotovo · 🔨 implementuje se · ▶️ připraveno k implementaci (návrh hotov, odblokováno) · ⏳ návrh hotov, čeká na blokátory · 🆕 k rozpracování (odblokováno, bez návrhu) · ⛔ blokováno. Odblokováno = všechny `Blocks`-blokátory hotové.')
    }
    [void]$report.AppendLine('')
}
[void]$report.AppendLine(("**Barevný čtverec/kolečko = stream** = od kterého prvotního předka (kořene) tiket pochází; při více předcích nese víc. " + $emojiLegend))
[void]$report.AppendLine('')
[void]$report.Append($tableSb.ToString())
if ($IndentedList) {
    [void]$report.AppendLine('')
    [void]$report.AppendLine('## Odsazený seznam')
    [void]$report.AppendLine('')
    [void]$report.AppendLine('Odsazení = odemyká / musí být hotové dřív. Tiket blokovaný více tikety je uveden pod každým z nich; úplný seznam blokátorů má v závorce.')
    [void]$report.AppendLine('')
    [void]$report.Append($listSb.ToString())
}
if ($Check) {
    [void]$report.AppendLine('')
    [void]$report.AppendLine('## Kontrola konzistence (prose ↔ linky ↔ graf)')
    [void]$report.AppendLine('')
    $scanNote = if ($IncludeEpicProse) { 'včetně popisu epicu' } else { 'popis epicu vynechán (nese generovaný graf)' }
    if ($Source -eq 'Proposals') {
        [void]$report.AppendLine("_Heuristická kontrola: klíčová slova v okolí zmínek v tělech proposalů/popisech, porovnaná s $($Lex.Noun)y ($scanNote). Nálezy ověř ručně._")
    } else {
        [void]$report.AppendLine("_Heuristická kontrola: klíčová slova v okolí zmínek tiketů v popisech a proposalech, porovnaná s Jira linky ($scanNote). Nálezy ověř ručně._")
    }
    [void]$report.AppendLine('')
    if ($findings.Count -eq 0) {
        [void]$report.AppendLine('✅ Žádný nesoulad nenalezen.')
    } else {
        foreach ($sev in 'CHYBA', 'VAROVÁNÍ', 'INFO') {
            $group = @($findings | Where-Object { $_.Severity -eq $sev })
            if ($group.Count -eq 0) { continue }
            $icon = @{ 'CHYBA' = '❌'; 'VAROVÁNÍ' = '⚠️'; 'INFO' = 'ℹ️' }[$sev]
            [void]$report.AppendLine("### $icon $sev ($($group.Count))")
            [void]$report.AppendLine('')
            foreach ($f in $group) { [void]$report.AppendLine("- **[$($f.Code)]** $($f.Text)") }
            [void]$report.AppendLine('')
        }
    }
}

$text = $report.ToString()
if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $text -Encoding utf8NoBOM } else { Write-Output $text }
exit $script:ExitCode
