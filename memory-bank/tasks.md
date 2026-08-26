# Tasks

Otevřené položky vývoje vrstvy. Dokončená práce sem nepatří — ta žije v
[proposals/completed/](proposals/completed/) a v gitu.

## Zaparkované nálezy z review (publikace a viditelnost)

Ověřené nálezy, které finální review našlo po vyčerpání opravné vlny. Každý je
reprodukovaný, žádný neblokuje provoz.

1. **Deklarovaný záměr hlásí vlastní větev jako kolizi.** `doc-index.ps1` odvozuje
   „mě" z aktuálního checkoutu, takže s `-Jira` nahlásí `KOLIZE AKTIVNÍ PRÁCE`
   i na vlastní už pushnutou tiketovou větev, pokud stojíš jinde. Samo zastavení
   je obhajitelné, ale [design_publikace_a_viditelnost.md](proposals/completed/design_publikace_a_viditelnost.md)
   i komentář ve skriptu tvrdí opak („vlastní už pushnutá větev nekoliduje sama
   se sebou"). Sjednotit chování s textem, nebo text s chováním.
2. **Věta „each artifact is wholly one language"** v jazykové sekci kontraktu je
   doslova nepravdivá pro soubory, které míchají anglické komentáře s českým
   výstupem. Pravidlo míří na výstup, ne na soubory.
3. **JIRA-less cestě deklarovaný záměr nepomůže** — bez tiketu a bez slugu nemá
   kolizní kontrola co porovnávat, takže dvě sezení bez tiketu se o sobě
   nedozvědí.
4. **`doc-index.ps1` v měřítku monorepa nesplňuje návrhový rozpočet.** Na
   `d:\_datasys\ums` (219 remote refs, `.git` 4,1 GB) trvá běžný běh 32–35 s a
   běh s deklarovaným záměrem (`-Jira`/`-Slug`) 57 s, proti 2,0 s v tomto
   forku — rozpočet 15 s tedy nesplněn. Hotspot zůstává touto pracovní
   položkou nedotčen: `git branch -r --contains` jednou na commit plus
   `cat-file -e` a `show` jednou na dvojici (větev, cesta); samotné čtení
   refů stojí jen 0,1 s. Dvoufázový filtr stáří tipu, který tato větev
   přidala, dělá výběr refů levným — zbylá cena je probírání obsahu po
   dvojicích. Neřešeno.
5. **Sdílený blok detekce fáze v pěti skillech se rozchází s kontraktem.**
   `mb-git-commit`, `mb-git-message`, `mb-jira-update`, `mb-sync` a `mb-scan`
   nesou stejný zkopírovaný odstavec: čte blok `## Active Work` jako
   `ACTIVE_WORK`, pokud není prázdný nebo nenese značku IDLE, a výslovně
   vylučuje slug `Work item` z testu fáze. Test v kontraktu je ale pin v tom
   bloku, slug je jen jeho polovina — takže blok s prózou, ale bez pinu, čte
   v těchto pěti skillech ACTIVE_WORK, zatímco všude jinde IDLE. `mb-state`
   a `mb-park` kontrakt implementují správně. Předchází tuto pracovní
   položku, je mimo její soupis souborů a je to jedna sdílená formulace
   použitá pětkrát v pěti neotestovaných tělech skillů. Neřešeno.
6. **Monorepo `d:\_datasys\ums` čeká na redeploy vrstvy.** Nasazená kopie
   tohoto forku (kořenové `.claude/`, `.agents/skills/`, vendorované skilly
   s overlay bloky) je s `ums/.claude/` v souladu — obnovuje ji poslední
   úloha každého plánu. Monorepo je samostatná živá kopie a za `ums/.claude/`
   zaostává o celou publikační vrstvu (marker gate, pravidlo obsahu,
   `MB_HUMAN_PUSH`, chaining cizího hooku, kontrakt v2.11): nástroj je
   `pwsh ums/sync-with-monorepo.ps1` a poté revendor v monorepu
   (`-NoOverlays` → `-OverlaysOnly`, postup v [playbook.md](playbook.md),
   sekce „Upgrade upstreamu"). Po nasazení znovu spustit
   `install-git-hooks.ps1`, protože hook je nyní `v2`. Neřešeno.
7. **Sebekontrola hooku čte průchod syntetické chráněné řádky jako chybějící
   značku, ale od pravidla obsahu má průchod dva důvody.** Kontrakt (Workspace
   Discipline, fáze 0) i finishing overlay (Step 4.5) říkají „řádka chráněné
   větve, která PROJDE, znamená, že značka agentní session chybí". Po zavedení
   `is_integration_push` ale projde i řádka, jejíž vrchol je už dosažitelný
   z `refs/remotes/<remote>/*` — hook to ohlásí jako „fast-forward na commity
   už publikované, push povolen" s exit 0, se značkou přítomnou. Naměřeno při
   dokončování `push_guard_jen_pro_agenty`: HEAD tiketové větve byl publikován,
   takže reject půlka sebekontroly „prošla" z pravidla obsahu, ne z chybějící
   značky; pravou negativu dal až syntetický nepublikovaný commit
   (`git commit-tree`). Oprava: sebekontrola má zamítací půlku stavět na
   NEPUBLIKOVANÉM vrcholu (nebo číst hlášku, ne jen exit kód), a věta
   „PROJDE = chybí značka" se má zúžit. Dvě místa: overlay řádek ~22, kontrakt
   řádek ~589. Neřešeno.

## Otevřená otázka na člověka

- **Je `develop` v monorepu chráněný proti přímému pushi na Bitbucketu?**
  Z tohoto repa to nelze zjistit. Pokud ano, stává se fallback v `mb-jira-update`
  §10 (krátká větev + výjimečné PR) normální cestou místo výjimky.

## Navazující pracovní položky

Pořadí podle přínosu; rozpad i odůvodnění jsou v sekci „Navazující položky"
archivovaného návrhu [design_publikace_a_viditelnost.md](proposals/completed/design_publikace_a_viditelnost.md).

1. **Průběžný záznam výsledku** — `handoff_<slug>.md` psaný orchestrátorem SDD po
   projití task review, čtený task briefem, konzumovaný harvestem (kříží ho
   s `git diff`) a `mb-jira-update`.
2. **Předání pro člověka** — testovací předpoklady z vln grafu a epický
   deployment přehled.
3. **Vrácení z testu** — reopen semantika v kontraktu a protokol návratu.
4. **Origin jako sdílené médium, dokončení** — normativní název tiketové větve
   a `Base:` pro stacked větve.
5. **Claim** — `mb-claim` (Jira jako registr vlastnictví). `mb-park` (design
   review nedrží pin) je dodán —
   [ums/.claude/skills/mb-park/SKILL.md](../ums/.claude/skills/mb-park/SKILL.md),
   zapsán v [SKILLS_MANIFEST.md](../ums/.claude/skills/shared/SKILLS_MANIFEST.md).
6. **Strukturální oprava** — `context.md` mimo kolizní cestu, cestující SDD
   kontext, epická vrstva v kontraktu, mergovatelný dirty-set.
