# Upgrade na superpowers v6.4.2, sync jako master a epik s povinnými odpověďmi — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zvednout vrstvu UMS na upstream superpowers v6.4.2 (pátý overlay pro Native exekuci, přežití kompaktace), udělat z `sync-with-monorepo.ps1` master nasazení včetně vendorovaných skillů a 15 harnessů a zavést v epiku povinné odpovědi a nechráněnou linii epiku.

**Architecture:** Fáze 0–5 podle návrhu. Revendor dostane testovatelné funkce (pin, sada skillů, víc fragmentů na cíl) a sync ho volá do každého cíle; kontrakt 3.2 rozprostře pravidla exekuce do existujících referencí; sync dostane manifest a ochranu proti driftu; epik dostane outbox a helper pro založení linie. Každá změna chování má sadu v prostém PowerShellu vedle kódu.

**Tech Stack:** PowerShell 7 (nástroje a testy bez Pesteru), Node.js ESM (`guard-git-push.mjs`), POSIX sh (`pre-push`), Markdown (kontrakt, overlaye, skilly), git.

**Spec:** [design_upgrade_superpowers_6_4_2.md](design_upgrade_superpowers_6_4_2.md)

## Global Constraints

- Na větvi se mění jen `ums/**`, `memory-bank/**` a `CLAUDE.md`; upstream soubory mimo ně mění výhradně merge `vanila/main` (Task 2).
- Vendorované skilly se nikdy needitují ručně mimo bloky `<!-- UMS-OVERLAY BEGIN/END -->`; změna jde do `ums/.claude/skills/shared/overlays/*.overlay.md`.
- Language Contract: AI-facing text (kontrakt, reference, overlaye, dispatch, ledger) anglicky; commit messages, MB dokumenty, reporty uživateli česky; konzolový výstup nástrojů vrstvy (`revendor-superpowers.ps1`, `sync-with-monorepo.ps1`) anglicky.
- Testy: prostý `.ps1`, žádný Pester, offline (vzdálený repozitář = lokální bare klon), vlastní `_assert.ps1` v každém adresáře `tests/`, `$ErrorActionPreference = 'Stop'` v každé sadě, která dot-sourcuje svůj předmět.
- Jádro kontraktu nejvýš 800 řádků a jádro + obálka pod stropem `$MaxPayloadBytes` hooku (`contract-shape.tests.ps1`).
- Citace `(contract[/soubor.md], "Sekce")` celá na jedné fyzické řádce, sekce doslova podle nadpisu, žádné `#fragment` odkazy.
- Vendorované skilly: 14 (celý upstream v6.4.2 kromě `Excluded: diagnosing-superpowers`); overlay bloků 5 cílů, každý s hlavičkovým ukazatelem.
- `epicBranchPattern`: chybějící klíč = `epic/*`; explicitně prázdná nebo neřetězcová hodnota = žádná linie epiku.
- Commit message česky, zapsaná nástrojem Write do `.superpowers/commit-msg.txt` a commitnutá `git commit -F`; po commitu ověřit bajtově diakritiku. Po KAŽDÉM commitu push vlastní větve `upgrade-superpowers-6-4-2`.
- Revendor spouštět z PowerShellu, nikdy z Git Bash (msys `tar` čte `C:` jako host).
- Nasazení do kořene forku (`.claude/`, `.agents/skills/`) jen na hranici fáze (Task 20), nikdy uprostřed tasku.

## Rulings plánu vůči návrhu

- **Čekání tiketu na „go" během finishing:** návrh (sekce 4.1) jmenuje pro tiketovou stranu blok NOW, ten ale během finishing neexistuje (`now-block.md`, „Where the block does NOT exist"). Plán: kde blok NOW existuje (SDD i Native exekuce), čekání nese on; ve finishing se čekání jmenuje v reportu (jádro, Escalation & Autonomy) a v řádku `## Předání` souboru tiketu epiku. Věcně (CO) beze změny, jen JAK.
- **Rozhodnutí o novém upstream skillu** (návrh 1.2, STOP na neznámý skill) padá při bumpu pinu (`-PinOnly`), ne při každém nasazení: nasazení bere sadu skillů z pinu forku, takže neznámý skill v nasazení vzniknout nemůže.

## Ověřovací sada

```
for t in $(find ums -name "*.tests.ps1"); do echo "== $t"; pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done
pwsh -NoProfile -File ums/.claude/scripts/revendor-superpowers.ps1 -VerifyOnly -UmsRoot .
pwsh -NoProfile -File ums/sync-with-monorepo.ps1 -Scope Fork -Agent claude,codex -WhatIf
```

Známé prostředí: dvě asercie `pool-launch.tests.ps1` (Gate 3, skutečné spuštění procesu) v sandboxu selhávají i na bázi — baseline je zaznamená a porovnává se proti nim.

---

## Fáze 0 — Převzetí driftu z monorepa

### Task 1: Převzetí záznamů UMS-3588 do `playbook-contract.md`

**Files:**
- Modify: `ums/.claude/skills/shared/contract/playbook-contract.md` (sekce „Recorded extensions", za položku UMS-3552)

**Interfaces:**
- Consumes: soubor monorepa `D:\_datasys\ums\.claude\skills\shared\contract\playbook-contract.md` (jen čtení)
- Produces: fork a monorepo mají v `shared/` shodný obsah (předpoklad prvního `ToMonorepo`, Task 15)

- [ ] **Step 1: Ověř rozsah driftu**

Run: `git -c core.autocrlf=false diff --no-index --ignore-cr-at-eol --stat D:/_datasys/ums/.claude/skills/shared ums/.claude/skills/shared`
Expected: `1 file changed, 53 deletions(-)` a jediný soubor `contract/playbook-contract.md`. Jiný výsledek = STOP a report (drift se mezitím změnil).

- [ ] **Step 2: Zkopíruj soubor z monorepa a normalizuj konce řádků na LF**

Obsah souboru monorepa zapiš do forku beze změny textu; konce řádků LF (stejně jako ostatní `.md` ve stromu).

- [ ] **Step 3: Ověř, že diff je čistě aditivní**

Run: `git diff --numstat -- ums/.claude/skills/shared/contract/playbook-contract.md`
Expected: `53	0	ums/.claude/skills/shared/contract/playbook-contract.md`

- [ ] **Step 4: Spusť sady `shared/tests`**

Run: `for t in ums/.claude/skills/shared/tests/*.tests.ps1; do pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done`
Expected: žádný řádek `FAILED:` (citace a tvar kontraktu drží).

- [ ] **Step 5: Commit a push**

Zpráva: „upgrade_superpowers_6_4_2: převzetí záznamů UMS-3588 z monorepa do playbook-contract.md"

---

## Fáze 1 — Upstream v6.4.2

### Task 2: Merge `vanila/main` (v6.4.2) a fork-vlastní `CLAUDE.md`

**Files:**
- Modify: celý upstream strom mergem
- Modify: `CLAUDE.md` (řešení konfliktu modify/delete)

**Interfaces:**
- Produces: `skills/` v tomto repu = upstream v6.4.2 (zdroj revendoru pro Task 5 a dál); `CLAUDE.md` = první řádek `@AGENTS.md`, prázdný řádek, pak blok `UMS-MEMORY-BANK` forku

- [ ] **Step 1: Ověř tip upstreamu**

Run: `git fetch vanila --tags; git rev-parse vanila/main "v6.4.2^{commit}"`
Expected: obě hodnoty `8ca22dba9a94f28898bbce59f2537ff4d87c747d`. Jinak STOP (upstream se pohnul za release).

- [ ] **Step 2: Merge**

Run: `git merge --no-ff vanila/main`
Expected: jediný konflikt `CONFLICT (modify/delete): CLAUDE.md deleted in vanila/main and modified in HEAD`.

- [ ] **Step 3: Vyřeš `CLAUDE.md`**

Nový obsah: řádek `@AGENTS.md`, prázdný řádek, pak doslova řádky od `<!-- UMS-MEMORY-BANK BEGIN (fork-only section, …` do `<!-- UMS-MEMORY-BANK END -->` z `git show HEAD:CLAUDE.md`. Upstream text „Contributor Guidelines" z něj zmizí — nese ho `AGENTS.md`. `git add CLAUDE.md`.

- [ ] **Step 4: Ověř aditivitu mergu**

Run: `git diff --name-only HEAD -- ums memory-bank` (před commitem mergu, vůči HEAD)
Expected: prázdný výstup — merge nesahá na `ums/` ani `memory-bank/`.
Run: `git diff --cached --stat -- CLAUDE.md`
Expected: jen `CLAUDE.md`, obsah začíná `@AGENTS.md`.

- [ ] **Step 5: Commit mergu a push**

Zpráva: „upgrade_superpowers_6_4_2: merge upstreamu v6.4.2, CLAUDE.md forku jako import AGENTS.md + blok UMS"

- [ ] **Step 6: Připrav příkaz pro fast-forward zrcadla `main`**

Nespouštěj. Do reportu uveď pro uživatele: `! git push origin vanila/main:main` (chráněná větev, fast-forward 55 commitů, spouští člověk).

### Task 3: Revendor — pin, sada skillů a `-SkillsRoot`

**Files:**
- Modify: `ums/.claude/scripts/revendor-superpowers.ps1`
- Create: `ums/.claude/scripts/tests/_assert.ps1` (kopie `ums/.claude/skills/shared/tests/_assert.ps1`)
- Create: `ums/.claude/scripts/tests/new-revendor-fixture.ps1`
- Create: `ums/.claude/scripts/tests/revendor.tests.ps1`

**Interfaces:**
- Produces (v revendor skriptu, dot-sourcovatelné přes nový přepínač `-DotSourceOnly`):
  - `Read-UmsVendorPin([string] $PinFile)` → `[pscustomobject]@{ Tag; Commit; Skills = [string[]]; Excluded = [string[]] }`, `$null` když soubor chybí; řádek `- Excluded:` s odsazenými jmény pod ním jako `Skills:`, chybějící sekce = prázdné pole.
  - `Write-UmsVendorPin([string] $PinFile, [string] $Tag, [string] $Commit, [string[]] $Skills, [string[]] $Excluded, [string] $RepoStateDate)` — tvar dnešního `VENDORED_FROM.md` plus sekce `- Excluded:`; procedura v souboru popisuje `-PinOnly` a dvoufázový sync.
  - `Resolve-UmsPinSkills([string[]] $UpstreamSkills, $PreviousPin, [string[]] $Include, [string[]] $Exclude)` → `@{ Skills = [string[]]; Excluded = [string[]]; Unknown = [string[]] }`; Unknown = upstream skill, který není v `$PreviousPin.Skills`, `$PreviousPin.Excluded`, `$Include` ani `$Exclude`; Excluded = předchozí vyloučené ∪ `$Exclude`, minus `$Include`.
  - `Get-UmsRemovedSkills($TargetPin, [string[]] $NewSkills)` → `[string[]]` (skilly z `$TargetPin.Skills` mimo `$NewSkills`; `$null` pin = prázdné).
  - Nové parametry skriptu: `-SkillsRoot [string]` (default `<UmsRoot>\.claude\skills`), `-PinSource [string]` (default `<SkillsRoot>\shared\VENDORED_FROM.md`), `-PinOnly`, `-Include [string[]]`, `-Exclude [string[]]`, `-DotSourceOnly`. `-Tag` je volitelný: bez něj se čte z `-PinSource`.
- Chování: `-PinOnly -Tag X` spočte skilly z `git ls-tree` tagu, zavolá `Resolve-UmsPinSkills`; neprázdné `Unknown` = `Fail` s výčtem jmen a pokynem použít `-Include`/`-Exclude`; jinak zapíše pin do `-PinSource`. Vendor fáze vendoruje právě `Skills` z pinu, smaže adresáře z `Get-UmsRemovedSkills` (předchozí pin = pin v `<SkillsRoot>\shared\VENDORED_FROM.md` před zápisem) a skill z pinu chybějící v tagu je `Fail`.

- [ ] **Step 1: Fixture builder**

Soubor `new-revendor-fixture.ps1` exportuje `New-RevendorFixture` → `@{ SpRepo; UmsRoot; SkillsRoot }`: git repo `SpRepo` se dvěma tagy — `t1` se skilly `alpha`, `beta`, `subagent-driven-development` (se soubory, které vyžaduje `Invoke-Verify`, a funkčním bash skriptem `scripts/sdd-workspace`, který vytvoří `.superpowers/sdd/<basename>/` a vypíše cestu), a `t2`, kde `beta` chybí a přibyl `gamma`; `UmsRoot` je git repo s `.claude/skills/shared/overlays/` (prázdné) a pinem pro `t1`.

- [ ] **Step 2: Napiš testy (RED)**

V `revendor.tests.ps1` (dot-source skriptu s `-DotSourceOnly`) asercie:

```powershell
$pin = Read-UmsVendorPin (Join-Path $fx.SkillsRoot 'shared\VENDORED_FROM.md')
Assert-Eq $pin.Tag 't1' 'pin: tag'
Assert-Eq (@($pin.Excluded).Count) 0 'pin bez sekce Excluded = prázdné pole'
$r = Resolve-UmsPinSkills @('alpha','gamma','subagent-driven-development') $pin @() @()
Assert-Eq ($r.Unknown -join ',') 'gamma' 'nový upstream skill je Unknown'
$r = Resolve-UmsPinSkills @('alpha','gamma','subagent-driven-development') $pin @() @('gamma')
Assert-Eq (@($r.Unknown).Count) 0 '-Exclude rozhodne neznámý skill'
Assert-Eq ($r.Excluded -join ',') 'gamma' 'vyloučený skill jde do Excluded'
Assert-Eq ((Get-UmsRemovedSkills $pin @('alpha','subagent-driven-development')) -join ',') 'beta' 'zrušený skill se smaže'
```

Plus end-to-end (volání skriptu jako procesu z PowerShellu): `-PinOnly -Tag t2` bez rozhodnutí skončí nenulovým exitem a výstupem obsahujícím `gamma`; s `-Exclude gamma` zapíše pin s `Tag: t2`, `Skills` bez `beta` a `Excluded: gamma`; následný běh `-NoOverlays -SkillsRoot <temp mimo UmsRoot>` bez `-Tag` vendoruje `t2` (adresář `beta` v cíli po běhu neexistuje, `gamma` taky ne) a `VENDORED_FROM.md` v cíli nese `Tag: t2`.

- [ ] **Step 3: Spusť, ověř RED**

Run: `pwsh -NoProfile -File ums/.claude/scripts/tests/revendor.tests.ps1`
Expected: FAIL — funkce `Read-UmsVendorPin` neexistuje.

- [ ] **Step 4: Implementuj**

Funkce a parametry podle Interfaces; `$Skills` natvrdo zmizí; `Invoke-Vendor` čte tag a sadu z pinu, CRLF normalizace zůstává; `$today` se bere z gitu cíle, mimo git `unknown`.

- [ ] **Step 5: Spusť, ověř GREEN**

Run: `pwsh -NoProfile -File ums/.claude/scripts/tests/revendor.tests.ps1`
Expected: `<N> passed`, exit 0.

- [ ] **Step 6: Commit a push**

Zpráva: „upgrade_superpowers_6_4_2: revendor čte tag a sadu skillů z pinu, -PinOnly, -SkillsRoot, vyloučené skilly"

### Task 4: Revendor — víc fragmentů na cíl a verifikace

**Files:**
- Modify: `ums/.claude/scripts/revendor-superpowers.ps1` (`Invoke-Overlays`, `Invoke-Verify`)
- Modify: `ums/.claude/scripts/tests/revendor.tests.ps1`, `ums/.claude/scripts/tests/new-revendor-fixture.ps1`
- Modify: `ums/.claude/skills/shared/overlays/README.md` (formát: víc fragmentů na cíl, hlavičkový ukazatel)

**Interfaces:**
- Consumes: Task 3 (`-SkillsRoot`, `-DotSourceOnly`)
- Produces:
  - `Invoke-Overlays` seskupí fragmenty podle `TARGET`, kontrolu „cíl už nese UMS-OVERLAY" provede jednou na cíl PŘED prvním fragmentem, fragmenty téhož cíle aplikuje v abecedním pořadí jmen souborů.
  - `Test-UmsOverlayPointerPosition([string] $SkillFile, [int] $MaxChars = 12000)` → `[bool]`: soubor s aspoň jedním `UMS-OVERLAY BEGIN` má PRVNÍ výskyt do `$MaxChars` znaků od začátku.
  - `Invoke-Verify`: vypuštěn požadavek `writing-plans\plan-document-reviewer-prompt.md`; přidány `executing-plans\scripts\task-start` a `executing-plans\scripts\task-done`; funkční test `sdd-workspace` běží proti `<SkillsRoot>\subagent-driven-development\scripts\sdd-workspace` a v cíli mimo git repozitář se přeskočí s řádkem `SKIP: sdd-workspace functional test (target is not inside a git repository)`; každý overlayovaný skill musí projít `Test-UmsOverlayPointerPosition`; počet aplikovaných bloků = počet fragmentů.

- [ ] **Step 1: Rozšiř fixturu** o dva fragmenty na `alpha/SKILL.md` (`alpha.pointer.overlay.md` s `ANCHOR-BEFORE: # Alpha`, `alpha.overlay.md` s `ANCHOR: EOF`) a o soubory, které `Invoke-Verify` nově vyžaduje.

- [ ] **Step 2: Napiš testy (RED)**

Asercie: plný běh do cíle v git repu projde a `alpha/SKILL.md` nese dva páry `UMS-OVERLAY BEGIN/END`, ukazatel před `# Alpha`, tělo na konci; `Test-UmsOverlayPointerPosition` vrátí `$false` pro soubor, kde první blok začíná za 12 000 znaky, a `$true` pro výsledný `alpha/SKILL.md`; běh do cíle mimo git repo skončí exit 0 a výstup obsahuje `SKIP: sdd-workspace functional test`; druhé spuštění `-OverlaysOnly` nad už overlayovaným cílem selže hláškou o pristine souboru (jednou, ne dvakrát).

- [ ] **Step 3: Spusť, ověř RED** — Run: `pwsh -NoProfile -File ums/.claude/scripts/tests/revendor.tests.ps1`; Expected: FAIL na aserci dvou párů bloků.

- [ ] **Step 4: Implementuj** podle Interfaces.

- [ ] **Step 5: Spusť, ověř GREEN** — Expected: `<N> passed`, exit 0.

- [ ] **Step 6: Commit a push** — „upgrade_superpowers_6_4_2: revendor aplikuje víc fragmentů na cíl, hlídá polohu ukazatele a verifikuje v6.4.2"

### Task 5: Bump pinu na v6.4.2

**Files:**
- Modify: `ums/.claude/skills/shared/VENDORED_FROM.md`

**Interfaces:**
- Consumes: Task 3 (`-PinOnly`), Task 2 (tag v6.4.2 v repu)
- Produces: pin `Tag: v6.4.2`, `Commit: 8ca22dba9a94f28898bbce59f2537ff4d87c747d`, 14 skillů, `Excluded: diagnosing-superpowers` — zdroj pravdy pro všechna nasazení

- [ ] **Step 1: Ověř STOP na neznámý skill**

Run (PowerShell): `pwsh -NoProfile -File ums/.claude/scripts/revendor-superpowers.ps1 -PinOnly -Tag v6.4.2 -UmsRoot ums -SkillsRoot ums/.claude/skills`
Expected: nenulový exit, výstup jmenuje `diagnosing-superpowers`.

- [ ] **Step 2: Zapiš pin s rozhodnutím**

Run: tentýž příkaz s `-Exclude diagnosing-superpowers`
Expected: exit 0; `git diff ums/.claude/skills/shared/VENDORED_FROM.md` ukáže nový tag, commit, 14 skillů a sekci `- Excluded:` s `diagnosing-superpowers`.

- [ ] **Step 3: Commit a push** — „upgrade_superpowers_6_4_2: pin vendorovaných skillů na v6.4.2, diagnosing-superpowers vyloučen"

---

## Fáze 2 — Kontrakt 3.2 a overlaye

### Task 6: Kontrakt 3.2 — rozprostření pravidel exekuce a jádro

**Files:**
- Modify: `ums/.claude/skills/shared/contract/session-intent-baton.md`, `now-block.md`, `playbook-contract.md`, `repository-configuration.md`
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`
- Modify: `ums/.claude/skills/shared/CHANGELOG.md`
- Create: `ums/.claude/skills/shared/contract/doklad/compaction.md`
- Modify: `ums/.claude/skills/shared/contract/doklad/…` jen pokud citace změněných sekcí vyžaduje

**Interfaces:**
- Produces (nadpisy, na které budou citovat overlaye v Task 7–8; nové nadpisy doslova):
  - `session-intent-baton.md`: podsekce `### The context-rotation stop` — rotace jen na hranici tasku (po řádku dokončení v ledgeru a odškrtnutí toda, před dalším taskem); obnovené sezení NEspouští znovu base sync ani baseline (`Next task: N` říká, zda jde o task 1 plánu); úsudek, ne měření; `Instruction:` jmenuje právě běžící exekutor (`subagent-driven-development` nebo `executing-plans`); do ledgeru poznámka, ne `Ruling:`. Zapisovatelé batonu: writing-plans (plan-execution, obě metody), SDD i executing-plans (plan-resume).
  - `now-block.md`: podsekce `### When the block is rewritten` — SDD: při každém dispatchi, návratu reportu a před koncem tahu; Native: na začátku tasku (`task-start`), po `task-done` a před koncem tahu. Domov ledgeru se určuje markerem `plan-path` (viz Task 9), ne jménem adresáře.
  - `playbook-contract.md`: odstavec v „Playbook Contract": soubor kandidátů leží mimo plan workspace a přežívá jeho smazání (maže ho jen harvest); u Native exekuce kandidáty zapisuje exekutor sám, stejný formát a `Find-UmsPlaybookMatch`.
  - `repository-configuration.md`: věta u efektivní báze: každý rozsah proti bázi (review balík, `MERGE_BASE` finálního review, intersekce base syncu) se počítá z efektivní báze — `git merge-base <effective base> HEAD` — nikdy z lokálního `main`.
  - Jádro: „four overlays" → five (Purpose & Roles, výčet cílů včetně `executing-plans`); Phase Map řádky „Playbook Contract", „Session Intent Baton", „The `NOW` Block" doplní „overlay executing-plans"; „Upstream subagent-driven-development (v6.3.0)" → „Upstream subagent-driven-development and executing-plans (v6.3.0+)"; v „Citation & Versioning" věta: každý overlayovaný skill nese kromě bloku i hlavičkový ukazatel, protože Claude Code po kompaktaci vkládá těla skillů oříznutá (doklad `compaction.md`); `Contract-Version: 3.2`. Jádro ≤ 800 řádků — vyvaž zhuštěním prózy, ne nadpisů.
  - `doklad/compaction.md`: nadpis `## The 5,000-token re-injection cap` — citace dokumentace Claude Code, tabulka velikostí (SDD ~12,3k/overlay od ~9,2k, finishing ~10k/~0,8k, brainstorming ~9,7k/~4,4k, writing-plans ~2,9k/~1,9k, executing-plans v6.4.2 ~5,8k), nedoložený směr ořezu, proč ukazatel + blok přežijí oba směry.
  - `CHANGELOG.md`: záznam 3.2 (rozprostření pravidel exekuce, pátý overlay, hlavičkové ukazatele, efektivní báze pro rozsahy; body z Fáze 4 doplní Task 18).

- [ ] **Step 1: Spusť sady `shared/tests` (baseline)** — Run: `for t in ums/.claude/skills/shared/tests/*.tests.ps1; do pwsh -NoProfile -File "$t" || echo "FAILED: $t"; done`; Expected: bez `FAILED:`.
- [ ] **Step 2: Uprav reference a jádro** podle Interfaces (anglicky, citace na jedné řádce).
- [ ] **Step 3: Spusť `contract-shape.tests.ps1`** — Expected: `<N> passed`; jádro ≤ 800 řádků, každá citovaná sekce existuje právě jednou, doklad bez verzní preambule.
- [ ] **Step 4: Grep lock** — Run: `grep -rn "four overlay\|v6\.3\.0)" ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md`; Expected: nic.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: kontrakt 3.2 — pravidla exekuce v referencích, pět overlayů, doklad o ořezu po kompaktaci"

### Task 7: Overlay SDD zúžený a nový overlay `executing-plans`

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md`
- Create: `ums/.claude/skills/shared/overlays/executing-plans.overlay.md`
- Modify: `ums/.claude/skills/shared/tests/contract-shape.tests.ps1`

**Interfaces:**
- Consumes: nadpisy z Task 6
- Produces: oba overlaye mají banner `> Contract core: … · References: …` se STEJNOU množinou referencí (`playbook-contract.md`, `now-block.md`, `session-intent-baton.md`, `repository-configuration.md`); `executing-plans.overlay.md` hlavička `<!-- TARGET: executing-plans/SKILL.md -->`, `<!-- ANCHOR: EOF -->`, ASSERTy `Four things stop you, and only these: an irreversible or destructive` a `The workspace and ledger are shared with superpowers:subagent-driven-development` (ověř přesný text řádku v `git show v6.4.2:skills/executing-plans/SKILL.md` a použij ho doslova)

- [ ] **Step 1: Napiš test (RED)** — v `contract-shape.tests.ps1` nová aserce: množina odkazů `contract/*.md` v bannerovém řádku `subagent-driven-development.overlay.md` je rovna množině v `executing-plans.overlay.md` (porovnej seřazená jména souborů); aserce existence souboru `executing-plans.overlay.md`.
- [ ] **Step 2: Spusť, ověř RED** — Expected: FAIL „executing-plans.overlay.md existuje".
- [ ] **Step 3: Přepiš SDD overlay** — ponech ASSERTy; tělo = banner + odrážky: Model selection (explicitní model, nejlevnější tier pro summarizaci), Rulings and STOPs (citace jádra; merge efektivní báze do vlastní větve není side effect), pátá stop třída (jen citace `session-intent-baton.md`, „The context-rotation stop", a věta, která upstreamovou „and only these" zužuje na eskalační stopy), Authority and Spec field, Batched dispatches, NOW (citace „When the block is rewritten"), Finish (citace playbook-contract), Language (české commit messages implementátorů), Isolation, Playbook (cesta k `Get-UmsPlaybookChain -Out` u každého dispatche), Playbook candidates (sekce reportu implementátora, `Find-UmsPlaybookMatch`, pravidla souboru citací), Base sync, Publication, rozsahy proti efektivní bázi (citace `repository-configuration.md`). Pravidla, která mají domov v referenci, se citují, nepřevyprávějí.
- [ ] **Step 4: Napiš `executing-plans.overlay.md`** — banner se stejnou sadou; odrážky: pátá stop třída (citace, `Instruction:` jmenuje `executing-plans`), Rulings and STOPs, NOW (Native body přepisu), Playbook (exekutor si řetězec sestaví a čte sám, baseline příkazy z něj), Playbook candidates (exekutor je zapisuje sám po `task-done`, formát a `Find-UmsPlaybookMatch`), Final review (explicitní model; balík `review-package PLAN_FILE <merge-base efektivní báze> HEAD`), Language, Isolation (upstream „use superpowers:using-git-worktrees to create one" = větev na místě; „outside this worktree" = mimo tento klon/workspace), Base sync (před Task 1 plánu), Publication (push po každém commitu), Finish (smazání workspace nesmaže kandidáty).
- [ ] **Step 5: Spusť `contract-shape.tests.ps1`** — Expected: `<N> passed`.
- [ ] **Step 6: Commit a push** — „upgrade_superpowers_6_4_2: overlay SDD cituje reference, nový overlay executing-plans pro Native exekuci"

### Task 8: `writing-plans`, `brainstorming`, hlavičkové ukazatele a generovací zkouška

**Files:**
- Modify: `ums/.claude/skills/shared/overlays/writing-plans.overlay.md`, `brainstorming.overlay.md`
- Create: `ums/.claude/skills/shared/overlays/{brainstorming,subagent-driven-development,finishing-a-development-branch,writing-plans,executing-plans}.pointer.overlay.md`

**Interfaces:**
- Consumes: Task 4 (víc fragmentů, kontrola polohy), Task 7
- Produces:
  - `writing-plans.overlay.md`: `ANCHOR-BEFORE: **When an execution method has already been supplied:**`; ASSERTy na řádek 189 v6.4.2 (ten, který končí „Which execution approach would you prefer?**" — zkopíruj ho doslova z výstupu `git show v6.4.2:skills/writing-plans/SKILL.md`, druhý řádek „Plan complete…" na 198 ASSERT nesmí matchovat) a na řádky položek Subagent-driven a Native (doslova z téhož výstupu). Tělo: `## Ověřovací sada` (tvar beze změny), oprava cesty na `<PLAN_MB>/proposals/active/plan_<slug>.md`, Fresh Session jako druhá otázka po volbě metody (jen při precondici zapisovatele a nad plánem, který uživatel prošel; baton `Kind: plan-execution`, `Instruction:` = zvolený skill), „If Fresh Session chosen" (baton, jeden odstavec česky, konec).
  - `brainstorming.overlay.md`: nový ASSERT `Architectural: the human partner reviews and approves the written spec,` nebo jiný jednoznačný řádek HARD-GATE, který nese „written-spec approval only permits invoking writing-plans" (ověř, že matchuje právě jeden řádek v6.4.2); odstavec, že mezi schválením spec a writing-plans stojí v UMS nabídka oponentury a Architect Review Gate; věta, že „Carry intent into the design" = sekce `## Cíl` návrhu.
  - Každý `*.pointer.overlay.md`: `ANCHOR-BEFORE: <řádek H1 cílového skillu v v6.4.2 doslova>`, ASSERT na tentýž řádek, tělo 3–5 řádků anglicky mezi markery `UMS-OVERLAY BEGIN (ums-memory-bank v2, pointer)` / `UMS-OVERLAY END`: skill v tomto repu nese na konci blok UMS-OVERLAY, který váže; je-li tělo po kompaktaci oříznuté, přečti ten blok ze souboru (Read, hledej `UMS-OVERLAY BEGIN`) dřív, než budeš pokračovat.

- [ ] **Step 1: Přepiš fragmenty** podle Interfaces.
- [ ] **Step 2: Generovací zkouška do dočasného cíle v git repu**

Run (PowerShell): vytvoř dočasný git repo `$tmp`, zkopíruj do něj `ums/.claude/skills/shared` jako `$tmp/.claude/skills/shared`, pak `pwsh -NoProfile -File ums/.claude/scripts/revendor-superpowers.ps1 -SpRepo . -UmsRoot $tmp`
Expected: `Verification passed.`; v `$tmp/.claude/skills` je 14 skillů, `diagnosing-superpowers` chybí; každý z pěti cílů nese dva páry markerů.

- [ ] **Step 3: Tabulka uzavření rozporů** — pro každý rozpor z návrhu (sekce „Co v6.4.2 přináší…") zapiš soubor:řádek upstream věty a věty overlaye ve VYGENEROVANÉM souboru v `$tmp`; výsledek ulož do `.superpowers/closure-table-6-4-2.md` (Task 20 ho převezme do návrhu).
- [ ] **Step 4: Grep sweep ve vygenerovaném stromu** — Run: `grep -rn "Inline Execution\|Two execution options\|Which approach?" $tmp/.claude/skills/*/SKILL.md`; Expected: jen upstream řádky mimo overlay bloky (overlay je nesmí oživovat).
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: overlay writing-plans pro menu v6.4.2, Fresh Session jako modifikátor, hlavičkové ukazatele pěti skillů"

### Task 9: `contract-inject` — ledger podle `plan-path` a pokyn po kompaktaci

**Files:**
- Modify: `ums/.claude/hooks/contract-inject.ps1`
- Modify: `ums/.claude/hooks/tests/contract-inject.tests.ps1`, `ums/.claude/hooks/tests/session-intent.tests.ps1`

**Interfaces:**
- Produces:
  - Ledger se hledá v `.superpowers/sdd/*/`: vyhrává adresář, jehož soubor `plan-path` obsahuje (po trim) `<Target MB Pin>proposals/active/plan_<slug>.md` nebo legacy `<Target MB Pin>proposals/active/proposal_<slug>.md`; bez shody se použije `plan_<slug>/` jen tehdy, když NEMÁ soubor `plan-path` (workspace z doby před markerem); jinak žádný blok NOW. Pin i slug projdou dnešním whitelistem znaků.
  - `$Instruction` rozšířen o větu (anglicky): „If a skill body was re-injected after compaction it may be truncated at 5,000 tokens — before continuing, read that skill's UMS-OVERLAY block from its SKILL.md."

- [ ] **Step 1: Napiš testy (RED)** — `contract-inject.tests.ps1`: fixture se dvěma workspace — `plan_x/` s `plan-path` = `memory-bank/proposals/abandoned/plan_x.md` a blokem NOW `Task: 1 — stale`, `plan_x-active/` s `plan-path` = `memory-bank/proposals/active/plan_x.md` a `Task: 7 — live`; pin `memory-bank/`, slug `x` → payload obsahuje `Task: 7 — live` a neobsahuje `stale`. Druhý případ: jen `plan_x/` bez `plan-path` → blok z něj (legacy). Třetí: payload obsahuje `may be truncated at 5,000 tokens`. `session-intent.tests.ps1`: baton s `Instruction: Continue with executing-plans at task 3.` projde validací (emise, ne `.stale.md`).
- [ ] **Step 2: Spusť, ověř RED** — Expected: FAIL na `Task: 7 — live`.
- [ ] **Step 3: Implementuj** podle Interfaces.
- [ ] **Step 4: Spusť obě sady, ověř GREEN** — Expected: `<N> passed` u obou.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: contract-inject hledá ledger podle plan-path a po kompaktaci připomene overlay"

---

## Fáze 3 — Nasazovací skript

### Task 10: Cíle harnessů a markery

**Files:**
- Modify: `ums/sync-with-monorepo.ps1` (`$AgentTargets` → funkce, `Set-AgentMarker`)
- Create: `ums/tests/_assert.ps1` (kopie `ums/.claude/skills/shared/tests/_assert.ps1`)
- Create: `ums/tests/sync-targets.tests.ps1`
- Modify: `ums/.claude/hooks/tests/sync-marker.tests.ps1`

**Interfaces:**
- Produces:
  - `Get-UmsSyncTargets([string[]] $Agent, [string] $Scope, [string] $Root)` → pole `[pscustomobject]@{ Agent; SkillsDir; ConfigDir; Instructions; Marker }` s absolutními cestami (`$null` kde harness nemá); `$Scope` ∈ `Monorepo`, `UserProfile`, `Fork`; neznámý agent (včetně `kilocode`) = výjimka se jménem agenta. Hodnoty podle tabulky návrhu, sekce 3.6: `claude`, `codex`, `gemini`, `qwen`, `opencode`, `pi`, `hermes`, `cursor`, `copilot`, `devin`, `droid`, `kimi`, `muse`, `antigravity`, `grok`. Marker ∈ `settings-env`, `codex-toml`, `dotenv`, `opencode-plugin`, `pi-prefix`, `hermes-passthrough`, `none`. Pro `-Scope Fork` je `Instructions` vždy `$null`.
  - `Set-AgentMarker([string] $ConfigDir, [string] $Agent, [string] $Scope = 'Monorepo')` (dnešní volání se dvěma argumenty dál platí): nově `qwen` (`.qwen/.env` přes `Set-DotEnvMarker`), `opencode` (soubor `<ConfigDir>/plugins/ums-agent-session.js` exportující plugin s hookem `shell.env`, který nastaví `output.env.MB_AGENT_SESSION = "1"`), `pi` (podle kroku 1), `hermes` (jen `UserProfile`: `terminal.env_passthrough` obsahuje `MB_AGENT_SESSION` v `config.yaml` a `MB_AGENT_SESSION=1` v `.env`; `Monorepo` → `NotSupportedException`); ostatní bez mechanismu → `NotSupportedException` s názvem harnessu. Každý zápis idempotentní.

- [ ] **Step 1: Ověř mechanismy proti primární dokumentaci** — pro `qwen` (`.env`), `opencode` (`shell.env` plugin), `pi` (vlastní `AI_AGENT=pi` vs `shellCommandPrefix`), `hermes` (`env_passthrough`) přečti oficiální dokumentaci (WebFetch) a zapiš URL a rozhodující větu do komentáře u `Set-AgentMarker`. U Pi rozhodni: pokud `pre-push` fallback na `AI_AGENT` (ověř v `ums/.claude/hooks/pre-push`) marker v Pi pokryje, `pi` = `none` s poznámkou „covered by AI_AGENT fallback"; jinak `pi-prefix`. Nedoložený mechanismus = `none`, nehádej.
- [ ] **Step 2: Napiš testy (RED)** — `sync-targets.tests.ps1`: `Get-UmsSyncTargets claude Monorepo C:\r` → SkillsDir `C:\r\.claude\skills`, Instructions `C:\r\CLAUDE.md`; `gemini Monorepo` → SkillsDir `…\.agents\skills`; `qwen UserProfile` → `…\.qwen\skills`; `grok Monorepo` → `…\.grok\skills`; `claude Fork` → Instructions `$null`; `kilocode` → výjimka obsahující `kilocode`; `cursor` → Marker `none`. `sync-marker.tests.ps1`: qwen `.env` vznikne a druhý běh ho nezvětší; opencode plugin soubor obsahuje `shell.env` a `MB_AGENT_SESSION`; kilocode case se odstraní a nahradí `cursor` → `NotSupportedException`.
- [ ] **Step 3: Spusť, ověř RED** — Run: `pwsh -NoProfile -File ums/tests/sync-targets.tests.ps1`; Expected: FAIL, `Get-UmsSyncTargets` neexistuje.
- [ ] **Step 4: Implementuj** — tabulka jako data uvnitř `Get-UmsSyncTargets`; `$AgentTargets` zmizí; zbytek skriptu zatím volá novou funkci se starým chováním (Task 15 přepíše tělo).
- [ ] **Step 5: Spusť obě sady, ověř GREEN**.
- [ ] **Step 6: Commit a push** — „upgrade_superpowers_6_4_2: sync zná 15 harnessů superpowers, kilocode zrušen, markery pro Qwen, OpenCode a Hermes"

### Task 11: Manifest a ochrana proti driftu

**Files:**
- Modify: `ums/sync-with-monorepo.ps1`
- Create: `ums/tests/sync-drift.tests.ps1`

**Interfaces:**
- Produces:
  - `Get-UmsTreeHashes([string] $Root, [string[]] $RelItems)` → `[hashtable]` relativní cesta souboru (s `\`) → SHA256 hex obsahu po normalizaci CRLF→LF; neexistující položka se přeskočí.
  - `Get-UmsManifestPath([string] $TargetRoot, [string] $Key)` → `<git -C $TargetRoot rev-parse --absolute-git-dir>\ums-sync-manifest-<Key>.json`; mimo git `<TargetRoot>\.ums-sync-manifest-<Key>.json`. `$Key` = `<Agent>-<Scope>`.
  - `Read-UmsManifest([string] $Path)` → `@{ Files = [hashtable]; ForkSha; Written }` nebo `$null`; `Write-UmsManifest([string] $Path, [hashtable] $Files, [string] $ForkSha)`.
  - `Test-UmsDeployDrift([hashtable] $Target, [hashtable] $Manifest, [hashtable] $Fork)` → `@{ Drifted = [string[]]; NoManifest = [bool] }`: bez manifestu Drifted = soubory existující v cíli, jejichž hash ≠ fork; s manifestem Drifted = soubory, kde cíl ≠ manifest A cíl ≠ fork (soubor chybějící v cíli, ale v manifestu = smazaný v cíli = drift).
  - `Get-UmsTargetOnlySkills([string] $TargetSkills, [string] $ForkSkills)` → jména `mb-*` adresářů jen v cíli.

- [ ] **Step 1: Napiš testy (RED)** — fixtury v temp adresářích: (a) bez manifestu, cíl = fork → Drifted prázdné; (b) bez manifestu, cíl ≠ fork v `skills\shared\x.md` → Drifted = `skills\shared\x.md`, NoManifest `$true`; (c) manifest = cíl, fork změněný → Drifted prázdné (legitimní nasazení změny); (d) manifest ≠ cíl a cíl ≠ fork → Drifted; (e) CRLF vs LF téhož textu → shodný hash; (f) `Get-UmsManifestPath` v linked worktree fixture vrací cestu pod `.git/worktrees/<jméno>/`, ne pod common dir; (g) `Get-UmsTargetOnlySkills` vrátí `mb-extra`.
- [ ] **Step 2: Spusť, ověř RED** — Run: `pwsh -NoProfile -File ums/tests/sync-drift.tests.ps1`.
- [ ] **Step 3: Implementuj**.
- [ ] **Step 4: Spusť, ověř GREEN**.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: sync — manifest per worktree a detekce driftu cíle"

### Task 12: Vendorované skilly v cíli a dvoufázová změna tagu

**Files:**
- Modify: `ums/sync-with-monorepo.ps1`
- Create: `ums/tests/new-sync-fixture.ps1`, `ums/tests/sync-vendor.tests.ps1`

**Interfaces:**
- Consumes: Task 3–4 (revendor `-SkillsRoot`, `-PinSource`, `-NoOverlays`), Task 11
- Produces:
  - `Get-UmsVendorPlan([string] $ForkPin, [string] $TargetPin, [bool] $Tracked)` → `'full'` | `'vanilla-only'` | `'none'`: `'none'` když cíl nemá adresář skillů; `'vanilla-only'` když se tag pinu forku liší od tagu pinu cíle A cíl je trackovaný gitem; jinak `'full'`.
  - `Invoke-UmsVendoredDeploy([string] $ForkUmsDir, [string] $SkillsRoot, [string] $Mode)` volá `revendor-superpowers.ps1` forku jako proces: `-SpRepo <kořen forku> -SkillsRoot $SkillsRoot -PinSource <fork pin>` a pro `vanilla-only` navíc `-NoOverlays`; nenulový exit revendoru = výjimka.
  - `Test-UmsTracked([string] $Root, [string] $RelPath)` → `[bool]` (`git ls-files` neprázdné).
- `new-sync-fixture.ps1` exportuje `New-SyncFixture` → `@{ Fork; ForkUms; Mono; MonoBare }`: fork = git repo s `skills/` (tagy `t1`, `t2`, stejné jako revendor fixtura), `ums/.claude/` (shared s pinem na `t2`, overlay fragment, `mb-demo`, hooky jako prázdné stuby jen tam, kde je sync nekopíruje), `ums/sync-with-monorepo.ps1` a revendor zkopírované z pracovního stromu; monorepo = git repo s bare originem, `.claude/skills/shared` s pinem na `t1`, trackované.

- [ ] **Step 1: Napiš testy (RED)** — `Get-UmsVendorPlan` pro čtyři kombinace (stejný tag trackovaný → `full`; jiný tag trackovaný → `vanilla-only`; jiný tag netrackovaný → `full`; bez skills dir → `none`). End-to-end nad fixturou: `Invoke-UmsVendoredDeploy … 'vanilla-only'` → cíl nese skilly `t2` bez UMS-OVERLAY bloků a `shared/overlays` cíle se nezměnil; `'full'` → bloky přítomné.
- [ ] **Step 2: Spusť, ověř RED**.
- [ ] **Step 3: Implementuj**.
- [ ] **Step 4: Spusť, ověř GREEN**.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: sync vyrábí vendorované skilly v cíli, změna tagu ve dvou bězích"

### Task 13: Blok v `CLAUDE.md` a migrace starého tvaru

**Files:**
- Modify: `ums/sync-with-monorepo.ps1` (`Set-MarkedBlock`, nová `Get-MarkedBlockContent`)
- Modify: `ums/CLAUDE.md.sample` (bez sekce „## WF engine (KicWorkflow) — BPMN a elementy")
- Create: `ums/tests/sync-claudemd.tests.ps1`

**Interfaces:**
- Produces:
  - `$UmsOwnedHeadings = @('## Memory Bank contract', '## Superpowers × Memory Bank (uživatelské preference)', '## Zákaz git worktree')`.
  - `Set-MarkedBlock([string] $File, [string] $Content, [string[]] $OwnedHeadings = @())`: s markery nahradí blok na místě (dnešní chování); bez markerů a s neprázdnými `$OwnedHeadings` najde sekce s těmito nadpisy (sekce = od nadpisu po další `## ` nebo konec souboru), odstraní je a blok vloží na místo první z nich; bez markerů a bez vlastněných sekcí připojí blok na konec (dnešní chování).
  - `Get-MarkedBlockContent([string] $File, [string[]] $OwnedHeadings)` → text uvnitř markerů; bez markerů spojené vlastněné sekce v pořadí souboru; nic → `$null`.
  - Titulek souboru (`# CLAUDE.md`) a projektové sekce zůstávají mimo blok.

- [ ] **Step 1: Napiš testy (RED)** — legacy soubor = dnešní monorepní `CLAUDE.md` (fixtura kopie `ums/CLAUDE.md.sample` z HEAD, tedy i se sekcí WF engine): po `Set-MarkedBlock` s novým sample a `$UmsOwnedHeadings` soubor obsahuje právě jeden pár markerů, sekci `## WF engine` mimo blok beze změny, nadpis `## Memory Bank contract` právě jednou; druhé volání soubor nezmění (idempotence); `Get-MarkedBlockContent` legacy souboru vrátí tři vlastněné sekce bez WF engine.
- [ ] **Step 2: Spusť, ověř RED**.
- [ ] **Step 3: Implementuj a uprav `CLAUDE.md.sample`** (sekce WF engine pryč; odrážka „Exekuce plánu (SDD)" → „Exekuce plánu (SDD i Native)" s totožným obsahem pro obě metody).
- [ ] **Step 4: Spusť, ověř GREEN**.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: sync spravuje v CLAUDE.md jen blok UMS, migrace starého tvaru, sample bez projektových pravidel"

### Task 14: `-Scope Fork` a `.git/info/exclude`

**Files:**
- Modify: `ums/sync-with-monorepo.ps1`
- Create: `ums/tests/sync-fork.tests.ps1`

**Interfaces:**
- Produces:
  - `Add-UmsGitExclude([string] $RepoRoot, [string[]] $Patterns)` — připíše do `git -C $RepoRoot rev-parse --git-path info/exclude` jen chybějící řádky; vrací přidané.
  - `Get-UmsForkExcludes([string] $RepoRoot, [string[]] $RelDirs)` → řádky `/<reldir>/` pro adresáře, které `git check-ignore -q` neignoruje.
  - Scope `Fork`: kořen = `git -C $ForkUmsDir rev-parse --show-toplevel`; `claude` nasazuje stejnou sadu UMS položek jako `claude`+`Monorepo` plus vendorované skilly; ostatní agenti skilly (`shared`, `mb-*`, vendorované) do svého adresáře skillů; instrukční soubory se nepíšou; `pre-push` se instaluje.

- [ ] **Step 1: Napiš testy (RED)** — nad `New-SyncFixture`: `Add-UmsGitExclude` dvakrát → řádek právě jednou; po nasazení `-Scope Fork -Agent claude,codex` (volání skriptu jako proces s `-Force`, protože první běh nemá manifest) je `git status --porcelain` fork fixtury prázdný, `.agents/skills/mb-demo/SKILL.md` existuje, `CLAUDE.md` a `AGENTS.md` fixtury jsou bajtově beze změny.
- [ ] **Step 2: Spusť, ověř RED**.
- [ ] **Step 3: Implementuj**.
- [ ] **Step 4: Spusť, ověř GREEN**.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: sync -Scope Fork nasazuje do kořene forku bez špinění stromu"

### Task 15: Tělo syncu — default `ToMonorepo`, `-WhatIf`, `-Force`, drift STOP

**Files:**
- Modify: `ums/sync-with-monorepo.ps1` (parametry, interaktivní nabídka, hlavní tělo, `.DESCRIPTION`)
- Create: `ums/tests/sync-e2e.tests.ps1`

**Interfaces:**
- Consumes: Task 10–14
- Produces:
  - Parametry: `-Direction` default `ToMonorepo`; `-Agent [string[]]` default `claude`; `-Scope` ∈ `Monorepo`, `UserProfile`, `Fork`; nové `-Force`, `-WhatIf` (vlastní switch, ne `SupportsShouldProcess`); interaktivní nabídka: směr volba 1 = ToMonorepo.
  - Pořadí běhu pro každý cíl: drift (Task 11) → při Drifted a bez `-Force` výpis souborů a exit 3 s nabídkou `-Direction FromMonorepo` nebo `-Force` → `Get-UmsVendorPlan` → při `vanilla-only` jen vendor, výpis pokynu commitnout „vanilla sync" a spustit znovu, exit 4 → jinak zrcadlení UMS položek, vendorované skilly `full`, blok instrukcí (`$UmsOwnedHeadings` pro `CLAUDE.md`), marker, hooky → zápis manifestu. `-WhatIf` vypíše, co by zapsal, a drift, nezapíše nic, exit 0 (drift) i 0 (čisto).
  - `FromMonorepo` (jen `claude`+`Monorepo`): UMS položky bez vendorovaných skillů; `CLAUDE.md.sample` ← `Get-MarkedBlockContent`; zapíše manifest.
  - Varování pro cíle s markerem `none`: „the pre-push guarantee does not bind '<agent>' (no documented environment-injection mechanism)".

- [ ] **Step 1: Napiš testy (RED)** — nad fixturou: (1) bez parametrů v neinteraktivním procesu = `ToMonorepo`; (2) první běh bez manifestu s rozdílem → exit 3 a výpis souboru, cíl nezměněn; (3) totéž s `-Force` → exit 0, manifest vznikl; (4) následná ruční změna souboru v cíli + nový běh → exit 3; (5) `-WhatIf` s driftem nic nezapíše (hash stromu cíle před/po shodný); (6) cíl s pinem `t1`, fork `t2` → exit 4 a v cíli jen vanilla skilly, druhý běh po commitu v cíli → exit 0 a overlay bloky přítomné; (7) `FromMonorepo` nepřenese vendorované skilly do `ums/.claude/skills`; (8) `-Agent cursor` vypíše varování o záruce.
- [ ] **Step 2: Spusť, ověř RED**.
- [ ] **Step 3: Implementuj** a přepiš `.SYNOPSIS`/`.DESCRIPTION` (fork je master, vendorované skilly se nasazují, drift, scopy, harnessy).
- [ ] **Step 4: Spusť všechny sady `ums/tests` a `hooks/tests/sync-marker.tests.ps1`, ověř GREEN**.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: sync s výchozím směrem ToMonorepo, ochranou proti driftu a režimem -WhatIf"

---

## Fáze 4 — Orchestrace epiku

### Task 16: Povinné odpovědi a outbox

**Files:**
- Create: `ums/.claude/skills/mb-epic-run/scripts/outbox.ps1`
- Create: `ums/.claude/skills/mb-epic-run/tests/outbox.tests.ps1`
- Modify: `ums/.claude/skills/shared/contract/message-protocol.md`, `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (Message Protocol, jedna věta)
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` (spawn prompt, status, integrate — odpovědi)

**Interfaces:**
- Produces:
  - Soubor `<MB_ROOT>/.superpowers/epic/<KEY>/outbox.md`: titulek `# Outbox — epic <KEY>`, pak řádky uzavřeného tvaru `- <sentUtc ISO-8601> | to: <TICKET|manager> | due: <ISO-8601> | state: open|resent|closed | <subject>`.
  - `Add-UmsOutboxEntry([string] $RepoRoot, [string] $EpicKey, [string] $To, [datetime] $SentUtc, [datetime] $DueUtc, [string] $Subject)`; `Set-UmsOutboxState([string] $RepoRoot, [string] $EpicKey, [datetime] $SentUtc, [ValidateSet('resent','closed')] [string] $State)`; `Get-UmsOutbox([string] $RepoRoot, [string] $EpicKey, [datetime] $NowUtc)` → pole `@{ To; Sent; Due; State; Subject; Late }` (Late = State ≠ closed a Now > Due). Čtení podle bezpečnostních pravidel čtenáře (`now-block.md`, odstavec „Reader safety is the baton's SAFETY rules"): parse + re-render, strop velikosti, řádek se znakem `<`, `>`, `\p{Cc}` nebo `\p{Cf}` v hodnotě se zahodí a spočítá do `Rejected`.
  - `message-protocol.md`: nová podsekce `### Replies are required` — každá zpráva správce ↔ tiket vyžaduje odpověď (první řádek `Re: <UTC čas původní zprávy>`; přijato + co udělám / odmítnuto + pravidlo nebo měření / věcná odpověď); na odpověď se neodpovídá; třída `Oznámení:` (fakt o vlastním úkonu ověřitelný ve sdíleném artefaktu) odpověď nevyžaduje; kdy odpovědět (hranice tahu, po návratu subagenta); artefakt čekání (tiket: NOW kde existuje, jinak report a `## Předání`; správce: outbox); po `Due` jedno zopakování, pak člověk; stav pravidla v seznamu „Nothing in this section has a mechanical trigger" doplněn poctivě (outbox a NOW ho jen zviditelňují). Věta v seznamu, že odmítnutí domněnky „needs no round trip", se přepíše na „needs no permission, but is answered".
  - Jádro, Message Protocol: jedna věta o povinné odpovědi s citací `(contract/message-protocol.md, "Replies are required")`.

- [ ] **Step 1: Napiš testy (RED)** — `outbox.tests.ps1`: přidání dvou záznamů a `Get-UmsOutbox` s Now za `Due` prvního → první `Late`, druhý ne; `Set-UmsOutboxState … closed` → není `Late`; řádek se `<script>` v subjectu → zahozen, `Rejected` = 1; poškozený titulek → prázdný výsledek bez výjimky.
- [ ] **Step 2: Spusť, ověř RED**.
- [ ] **Step 3: Implementuj `outbox.ps1`**, pak texty kontraktu a `mb-epic-run` (status vykreslí nezodpovězené a opožděné zprávy česky; spawn a integrate zapisují/uzavírají záznamy; `allowed-tools` skillu ověř proti nástrojům, které nový text používá).
- [ ] **Step 4: Spusť `outbox.tests.ps1`, `contract-shape.tests.ps1`, `frontmatter.tests.ps1`, ověř GREEN**.
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: povinné odpovědi mezi správcem a tiketem, outbox správce"

### Task 17: Nechráněná linie epiku — konfigurace, báze, guard, založení

**Files:**
- Modify: `ums/.claude/skills/shared/scripts/Get-UmsRepoConfig.ps1`, `ums/.claude/skills/shared/scripts/Get-UmsBaseCandidates.ps1`
- Create: `ums/.claude/skills/shared/scripts/Test-UmsIntegrationBase.ps1`, `ums/.claude/skills/shared/tests/integration-base.tests.ps1`
- Modify: `ums/.claude/skills/shared/tests/repo-config.tests.ps1`, `base-candidates.tests.ps1`
- Modify: `ums/.claude/hooks/guard-git-push.mjs`, `ums/.claude/hooks/tests/guard-git-push.tests.ps1`
- Create: `ums/.claude/skills/mb-epic-run/scripts/epic-line.ps1`, `ums/.claude/skills/mb-epic-run/tests/epic-line.tests.ps1`

**Interfaces:**
- Produces:
  - `Get-UmsRepoConfig`: `EpicBranchPattern` = `'epic/*'`, když klíč chybí; explicitní prázdný nebo neřetězcový = `''`.
  - `Test-UmsIntegrationBase([string] $Branch, $Config)` → `@{ Allowed = [bool]; Kind = 'protected'|'epic-line'|'none'; BadPatterns = [string[]] }` — chráněná větev vyhrává; jinak `Kind = 'epic-line'`, když `$Config.EpicBranchPattern` je neprázdný a větev mu odpovídá (`-like`, ošetřená výjimka vadného vzoru = neshoda + `BadPatterns`).
  - `Get-UmsBaseCandidates`: kandidáti = větve na `origin`, pro které `Test-UmsIntegrationBase` vrací `Allowed`; nové pole `IsEpicLine`; pořadí výchozí → aktuální → ostatní; hlavička souboru přepsaná.
  - `guard-git-push.mjs`: `isEpicFastForward`, čtení `epicBranchPattern` a související větve výjimky zmizí; chráněná větev = zamítnutí bez výjimky; nechráněná linie epiku = povoleno jako každá nechráněná větev.
  - `New-UmsEpicLine([string] $RepoRoot, [string] $EpicKey, [string] $DeliveryRef)` → `@{ Branch; Existed = [bool]; Created = [bool]; Sha }`: `git fetch origin`; existuje-li `origin/epic/<EpicKey>`, `Existed`; jinak `git push origin <sha $DeliveryRef>:refs/heads/epic/<EpicKey>` a `Created`; chyba pushe = výjimka.

- [ ] **Step 1: Napiš testy (RED)** — repo-config: chybějící klíč → `epic/*`, `""` → `''`, `5` → `''`; integration-base: `develop` s chráněnými `develop` → protected; `epic/UMS-1` bez ochrany → epic-line; `epic/UMS-1` s prázdným vzorem → none; `feature/x` → none; vadný vzor `epic/[` → none + BadPatterns; base-candidates: bare origin s `develop` a `epic/UMS-1` → oba kandidáti, epic s `IsEpicLine`; guard: push `HEAD:epic/UMS-1` (nechráněná) → allow, push na `epic/UMS-1` uvedenou v `protectedBranches` → deny, raw-SHA refspec na chráněnou větev → deny (výjimka zrušena); dosavadní případy epikové výjimky v `guard-git-push.tests.ps1` přepiš na tato očekávání, žádný nezůstane mrtvý; epic-line: v fixturním repu s bare originem první volání `Created`, druhé `Existed`, `git ls-remote origin epic/UMS-1` vrací SHA `develop`.
- [ ] **Step 2: Spusť dotčené sady, ověř RED**.
- [ ] **Step 3: Implementuj**.
- [ ] **Step 4: Spusť dotčené sady a `pre-push.tests.ps1`, ověř GREEN** (`pre-push` se nemění; sada potvrdí, že zákaz force a mazání platí i na nechráněné linii).
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: linie epiku jako nechráněná integrační báze, výchozí vzor epic/*, zrušení výjimky guardu"

### Task 18: Texty kontraktu a skillů pro nechráněnou linii a integraci „go"

**Files:**
- Modify: `ums/.claude/skills/shared/contract/epic-line.md`, `contract/doklad/epic-line.md`, `contract/integration.md`, `contract/workspace-discipline.md`, `contract/escalation.md`, `contract/repository-configuration.md`
- Modify: `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` (dno eskalace, „Rulings and these STOPs", Publication Contract zmínky o chráněných patternech)
- Modify: overlaye `brainstorming.overlay.md` (Choose the base), `subagent-driven-development.overlay.md` (věta o sdílených větvích), `finishing-a-development-branch.overlay.md` (Handoff a Confirmation)
- Modify: `ums/.claude/skills/mb-epic-run/SKILL.md` (spawn: `New-UmsEpicLine`, báze v promptu; integrate: bez pushe, odpověď go/STOP s tipem linie; iron rules)
- Modify: `ums/.claude/skills/shared/CHANGELOG.md` (3.2 doplněk)

**Interfaces:**
- Consumes: Task 16–17 (funkce a jejich jména)
- Produces: konzistentní kontrakt — linie epiku je nechráněná báze identifikovaná `epicBranchPattern` (default `epic/*`); integrace do ní: tiket → artefakt → `mb-epic-run integrate` (kontroly epiku, úsudek, handoff brána, žádný push) → odpověď `go` s tipem linie nebo `STOP` → tiket `git fetch`, ověří tip, `git push origin HEAD:epic/<KLÍČ>`, potvrzení z báze, `Oznámení:` správci → poznámka v ledgeru. `epic-line.md` a doklad zapíší jako přijaté zbytkové riziko, že „go" není mechanicky vynucené. Výstup do dodávkové linie a smazání linie zůstávají lidské.

- [ ] **Step 1: Grep sweep (seznam míst)** — Run: `grep -rln "actor-rule exception\|manager performs\|Offers only protected\|unprotected base\|Shared branches are never pushed\|isEpicFastForward\|epicBranchPattern" ums/`; výsledek je pracovní seznam; každý soubor z něj po tasku buď prošel úpravou, nebo má v commitu zdůvodnění, proč zůstává.
- [ ] **Step 2: Přepiš texty** podle Produces (anglicky; citace na jedné řádce; jádro ≤ 800).
- [ ] **Step 3: Spusť `contract-shape.tests.ps1`, `frontmatter.tests.ps1`, `epic-gate.tests.ps1`, ověř GREEN**.
- [ ] **Step 4: Opakuj grep ze Step 1** — Expected: jen zdůvodněné zásahy (např. historie v dokladu).
- [ ] **Step 5: Commit a push** — „upgrade_superpowers_6_4_2: kontrakt a skilly pro nechráněnou linii epiku a integraci po go správce"

---

## Fáze 5 — Dokumenty, nasazení do forku, verifikace

### Task 19: Dokumenty vrstvy a sekce forku v `CLAUDE.md`

**Files:**
- Modify: `ums/README.md`, `ums/.claude/skills/shared/SKILLS_MANIFEST.md`, `ums/.claude/skills/shared/contract/brainstorming-paths.md` (zmínka v6.3.0), `CLAUDE.md` (blok forku)

**Interfaces:**
- Produces: README — v6.4.2, 14 skillů a vyloučený `diagnosing-superpowers` s důvodem, 5 overlayů, matice 15 harnessů (skilly, instrukce, marker, záruka), pokyn neinstalovat superpowers jako plugin do cílů UMS, fork jako master a nové parametry syncu; manifest — verze, počty; `CLAUDE.md` forku — fork je master (`ToMonorepo` default), `-Scope Fork` místo ruční obnovy, pět overlayů, věta o rolích větví („`CLAUDE.md` forku" místo „tato sekce CLAUDE.md na konci souboru").

- [ ] **Step 1: Uprav dokumenty**.
- [ ] **Step 2: Grep sweep** — Run: `grep -rn "v6\.3\.0\|14 vendored\|přesně 4\|four overlay\|kilocode\|FromMonorepo (default)\|Two execution options" ums/ CLAUDE.md`; Expected: jen historické zmínky (CHANGELOG, doklad) nebo prázdno.
- [ ] **Step 3: Commit a push** — „upgrade_superpowers_6_4_2: dokumenty vrstvy pro v6.4.2, nový sync a epik"

### Task 20: Nasazení do forku a verifikační baterie

**Files:**
- Modify: `memory-bank/proposals/active/design_upgrade_superpowers_6_4_2.md` (sekce „Verifikační evidence")
- Nasazení (netrackované): `.claude/`, `.agents/skills/`

**Interfaces:**
- Consumes: vše předchozí

- [ ] **Step 1: Nasazení nanečisto** — Run: `pwsh -NoProfile -File ums/sync-with-monorepo.ps1 -Scope Fork -Agent claude,codex -WhatIf`; Expected: výpis položek; drift vůči dnešnímu ručnímu nasazení je očekávaný (první běh bez manifestu).
- [ ] **Step 2: Nasazení** — Run: tentýž příkaz bez `-WhatIf`, s `-Force` (první běh, ruční nasazení bez manifestu); Expected: exit 0, `Verification passed.` z revendoru, `git status --porcelain` prázdný.
- [ ] **Step 3: Ověřovací sada** — spusť doslova tři příkazy ze sekce „Ověřovací sada"; Expected: bez `FAILED:` kromě dvou známých asercí `pool-launch.tests.ps1` z baseline, `Verification passed.`, `-WhatIf` bez driftu.
- [ ] **Step 4: Cold-reader průchod** — vygenerované skilly v `.claude/skills`: tabulka cesta (spike / bounded / architectural) × metoda (SDD / Native) × pokračování (čerstvé sezení s batonem / kompaktace) → vede text ke správným krokům UMS? Ulož do návrhu.
- [ ] **Step 5: Tabulka uzavření rozporů** — převezmi `.superpowers/closure-table-6-4-2.md` (Task 8), přepočítej řádky proti nasazenému `.claude/skills`, ulož do návrhu.
- [ ] **Step 6: Připrav kroky pro uživatele** (nespouštěj): fast-forward zrcadla `main` (`! git push origin vanila/main:main`); první nasazení do monorepa — `pwsh ums/sync-with-monorepo.ps1 -Agent claude -Scope Monorepo -WhatIf`, pak bez `-WhatIf` (očekávaný exit 4 = vanilla fáze, commit „vanilla sync" v monorepu, druhý běh, commit „overlay"); upozornění, že monorepo stojí na tiketové větvi a volba cílové větve je na uživateli. Ulož jako sekci „Kroky pro uživatele" do návrhu.
- [ ] **Step 7: Commit a push** — „upgrade_superpowers_6_4_2: verifikační evidence — nasazení do forku, sada, cold-reader a tabulka rozporů"
