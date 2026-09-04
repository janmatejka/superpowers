# Rozjetí tiketu do slotu poolu — průvodce operátora

Tento průvodce je pro operátora, který ještě s poolem nepracoval. Popisuje, co
pool je, jak označit existující sloty, jak založit nový, jak do slotu rozjet
tiket a co po spuštění zkontrolovat na obrazovce.

**Tento průvodce je psaný pro monorepo**, kde pool skutečně žije; cesty v
příkladech níž jsou z jedné konkrétní stanice a **je nutné je upravit** —
adresáře worktreí nemusí ležet vedle repozitáře a měřeně tam neleží. **Tento fork (`superpowers`) žádné linkované worktree nemá** —
spouštění příkazů z kapitoly 2 zde nezaloží žádný slot a nic se nestane, což
je očekávané chování, ne chyba. Vývojářský popis skriptů, které pool obsluhují,
je v [README skillu mb-epic-run](../.claude/skills/mb-epic-run/README.md);
rozhodovací logika a pravidla, kterými se `mb-epic-run` řídí, jsou v
[SKILL.md téhož skillu](../.claude/skills/mb-epic-run/SKILL.md).

## 1. Co pool je

Pool je sada linkovaných worktrees (linked worktrees) hlavního klonu
monorepa, které si operátor sám založil a označil markerem. Každý slot je
samostatný pracovní adresář se sdíleným `.git` s hlavním klonem — může mít
vlastní rozjetou/checkoutnutou větev, vlastní špinavý strom, vlastní
nepushnuté commity. Platí jedno sezení Claude Code na jeden slot: dva
souběžné agenty ve stejném slotu si šlapou na špinavý strom i na `HEAD`.

Členství v poolu je odvozené, nikdy nakonfigurované: slotem je každá
linkovaná worktree hlavního klonu, která nese soubor
`.superpowers/pool-slot`. Bez tohoto markeru by worktree držená třeba pro
údržbu release větve — čistý strom, žádný rozpracovaný pin, žádné nepushnuté
commity — splňovala všechny podmínky volnosti a rozjetí tiketu by ji tiše
přepnulo na tiketovou větev.

## 2. Jak označit existující sloty

Máš-li v monorepu už založené worktrees a chceš je zpětně prohlásit za sloty
poolu, označ každou jedním příkazem:

**Cesty si nevypisuj z hlavy — nech si je odvodit.** Adresář worktree se nemusí
nacházet vedle repozitáře a často se tam nenachází: měřeno 4. 9. 2026 na
monorepu leží worktrees registrované jako `ums01`–`ums04` v úplně jiném
stromě, než ve kterém je `.git`. Zdrojem pravdy je `.git/worktrees/*/gitdir`:

```powershell
$repo = 'D:\_datasys\ums'   # kořen monorepa, uprav na svůj
Get-ChildItem (Join-Path $repo '.git\worktrees') -Directory | ForEach-Object {
  $slot = (Get-Content (Join-Path $_.FullName 'gitdir') -Raw).Trim() -replace '[\\/]\.git$',''
  New-Item -ItemType Directory -Force -Path (Join-Path $slot '.superpowers') | Out-Null
  Set-Content -LiteralPath (Join-Path $slot '.superpowers\pool-slot') -Value '# UMS pool slot marker.' -Encoding utf8
  "označeno: $slot"
}
```

Příkaz je idempotentní — spustíš-li ho znovu na už označeném slotu, marker jen
přepíše stejným obsahem. Označí **všechny** registrované worktrees; když některý
slotem být nemá, jeho marker po spuštění smaž (nebo si seznam vyfiltruj).

Že to zabralo, ověříš tím, že se sloty objeví v tabulce:
`pwsh <cesta k monorepu>/.claude/skills/mb-epic-run/scripts/pool-status.ps1`.
Dokud žádný worktree marker nenese, skript vrací **exit 3** a hlásí, že
repozitář pool nemá — to není chyba, to je ta fail-closed odpověď.

## 3. Jak založit nový slot

Nový slot založíš skriptem `pool-provision.ps1`:

```powershell
pwsh <cesta k monorepu>/.claude/skills/mb-epic-run/scripts/pool-provision.ps1 -Path <cesta pro nový slot> -Operator
```

Skript vytvoří novou linkovanou worktree (detached, z konfigurované báze
repozitáře nebo z `origin/develop`), zapíše do ní marker
`.superpowers/pool-slot` a zevnitř slotu ověří, že sdílený `pre-push` guard
(kontrakt, Publication Contract) je nainstalovaný a aktuální — případně ho
tam nainstaluje.

**Proč se ptá `-Operator`:** založení slotu je výhradně operátorská akce.
Skript odmítne běžet, pokud v prostředí najde marker agentského sezení
(`MB_AGENT_SESSION`, `AI_AGENT` nebo `CLAUDECODE`), a bez `-Operator` skončí
s exit kódem `4` — „Refused: an agent-session marker is present in the
environment." `-Operator` je tvoje explicitní potvrzení, že akci provádíš ty,
ne agent.

Skript skončí:
- `0` — slot je založený a publikační garance (publication guarantee) je
  potvrzená,
- `1` — chyba vstupu nebo skriptu,
- `4` — odmítnuto hlídkou agentského sezení (viz výše),
- `5` — slot BYL založen (worktree i marker existují a nikdy se nestrhávají
  zpět), ale publikační garanci se nepodařilo potvrdit — cestu k hooku se
  nepodařilo zevnitř slotu vyřešit, instalační skript se nenašel, nebo sám
  skončil chybou (na obrazovce uvidíš anglické `WARNING: ... publication
  guarantee is NOT confirmed`). **Exit `5` nikdy nečti jako úspěch** —
  worktree a marker sice existují, ale garance publikačního kontraktu pro
  tenhle slot ověřená není, a bez dalšího zásahu do ní nespoléhej.

## 4. Jak rozjet tiket

Rozjetí tiketu do volného slotu obstarává operace `spawn` skillu
`mb-epic-run`:

```
mb-epic-run spawn <TIKET>
```

Skill si sám odvodí epik, znovu si vytáhne čerstvý stav poolu, ověří
způsobilost (volný slot, tiketová větev nikde nedrží, žádná kolize
aktivní práce) a teprve pak spustí sezení. **Adaptér (`terminal` nebo
`direct`) je tvoje volba jako operátora** — skill si ho sám nevybírá a
nepadá z jednoho na druhý; když ho nezadáš, skill se zeptá.

Po spuštění na obrazovce zkontroluj:

- **Není tam `⚠ Transcript saving is off`.** Přítomnost té hlášky znamená, že
  nové sezení zdědilo identitu rodičovského sezení místo aby bylo čerstvé — v
  tom případě sezení nepovažuj za rozjeté a nahlas to.
- **V prvním vstupu je CELÝ prompt**, ne jen jeho první slovo nebo fragment.
  Rozdělený prompt je znak, že se text cestou rozpadl (typicky kvůli
  uvozovce nebo středníku v zadání), a sezení dostalo jen zlomek instrukce.

Sama existence procesu nic nedokazuje — teprve potvrzené `live` sezení pro
daný slot z čerstvého běhu `pool-status.ps1` a to, co vidíš na obrazovce, jsou
důkaz.

## 5. Pohodlí stanice

Adaptér `terminal` spouští sezení přes `wt.exe` (Windows Terminal). **`wt.exe`
musí být v `PATH`.** Když v `PATH` není, skript to nahlásí jako
`unavailable` a **nepadá na jiný adaptér** — rozjetí přes `direct` adaptér
musíš zvolit sám jako operátor, skript to za tebe nerozhodne.

## 6. Co dělat, když se sezení neobjeví

Skill po spuštění znovu ověří stav poolu a čeká na záznam s běžícím sezením
pro daný slot. Když se ani po opakovaném pokusu neobjeví, nahlásí přesně:
„žádné nové sezení se neobjevilo — ověř na obrazovce". To je pokyn, ne
diagnóza: podívej se na obrazovku slotu sám. Existence procesu (`Get-Process
claude` a podobně) sama o sobě nic neprokazuje — ve všech dosud naměřených
selháních proces existoval, přesto sezení nebylo v pořádku rozjeté.

## 7. Kolik slot stojí

Naměřeno 2026-09-02, na tehdejším stavu monorepa (čísla se s dalším růstem
repozitáře posunou, nejsou to trvalá fakta):

- jeden slot: 7,7 GB / 80 022 souborů,
- sdílený `.git` (společný pro hlavní klon i všechny sloty): 4,4 GB,
- hlavní klon: 27,2 GB / 140 365 souborů,
- čerstvě založený slot: přibližně 8 GB.
