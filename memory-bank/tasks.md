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
2. **Úryvek v kontraktu u kroku 8 vynechává `-BaseRef`**, takže by v tomto forku
   použil výchozí `origin/develop` místo `origin/ums-memory-bank`.
3. **Úniková proměnná `UMS_ALLOW_SHARED_PUSH` v `guard-git-push.mjs` zkratuje celý
   příkaz**, tedy zvedá i kontrolu wildcard refspecu u `fetch`. Na fail-open
   vrstvě to není díra v záruce, ale je to širší povolení, než pravidlo popisuje.
4. **Věta „each artifact is wholly one language"** v jazykové sekci kontraktu je
   doslova nepravdivá pro soubory, které míchají anglické komentáře s českým
   výstupem. Pravidlo míří na výstup, ne na soubory.
5. **JIRA-less cestě deklarovaný záměr nepomůže** — bez tiketu a bez slugu nemá
   kolizní kontrola co porovnávat, takže dvě sezení bez tiketu se o sobě
   nedozvědí.

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
5. **Claim a park** — `mb-claim` a `mb-park` (design review nedrží pin).
6. **Strukturální oprava** — `context.md` mimo kolizní cestu, cestující SDD
   kontext, epická vrstva v kontraktu, mergovatelný dirty-set.
