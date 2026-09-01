# Návrh: Session baton pro rotaci kontextu

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-01

## Cíl

Dnes existují dvě situace, ve kterých se sezení musí restartovat ručně a přitom
se ztrácí záměr operátora:

1. **Hranice fáze, brainstorming → implementace.** Ve chvíli, kdy je uložený
   `plan_<slug>.md`, je celý stav na disku — návrh, plán, `context.md`, větev.
   Z brainstormingového dialogu není pro exekuci potřeba nic, přesto ho
   orchestrátor nese celý do implementace. Operátor dnes zakládá čisté sezení
   ručně a záměr přepisuje z hlavy.
2. **Uprostřed plánu, orchestrátor u stropu kontextu.** Stav je opět celý na
   disku (checkboxy plánu, ledger `.superpowers/sdd/<plan-basename>/progress.md`,
   git), ale `subagent-driven-development` zakazuje zastavit pro cokoli jiného
   než čtyři jmenované třídy — neexistuje tedy sankcionovaný bod, ve kterém se
   sezení smí rotovat.

Mezera je v obou případech tatáž: **přes `/clear` nepřenese záměr operátora
nic.** `SessionStart` už znovu ustaví skilly, kontrakt a `context.md`, ale nemá
jak vědět, co předchozí sezení právě chystalo udělat.

## Scope

**Uvnitř:** formát batonu a jeho zápis do kontraktu; konzumující `SessionStart`
hook s branch a slug guardy a jeho testovací sada; zapojení do
[`ums/.claude/settings.json`](../../../ums/.claude/settings.json) včetně uzavření
asymetrie vůči `PostCompact`; invalidace batonu ve čtyřech místech životního
cyklu; pátá stop třída v SDD overlay; nový overlay fragment pro `writing-plans`
se třetí volbou exekuce. Režim doručení je právě jeden — operátor napíše
`/clear`.

**Mimo rozsah, vědomě** (viz sekce „Navazující položky"): druhý režim doručení
(spawn nového tabu přes `wt.exe` a opuštění vlastního sezení) a zaparkování SDD
ledgeru jako evidence.

**Nedělá se vůbec, ani později:**

- **`/clear` vyvolané agentem.** Žádný hook nedokáže vydat slash příkaz ani ho
  přepsat. `/clear` píše operátor; zredukovat to na jedno slovo je celá výhra.
- **Čtení transkriptu.** `transcript_path` se nečte, poslední zprávy se
  neextrahují, stav se z JSONL nerekonstruuje. Autoritativní stav je na disku;
  každý návrh, který rýpe v transkriptu, je regres.
- **Měření rozpočtu kontextu.** Hook input žádné spolehlivé pole o rozpočtu
  tokenů nenese. Rozhodnutí o rotaci je **úsudek** modelu a měřič operátora —
  detektor prahu se nestaví a netvrdí se, že existuje.
- **Verzování batonu** v jakékoli podobě: žádný commit, žádné `git add -f`,
  žádná jmenovaná výjimka, žádná položka v soupisu zbytků `mb-park`.
- **Zabíjení předchozího sezení.** Nedohledává se rodičovský PID, nechodí se po
  `Win32_Process`, nespouští se `Stop-Process`. Nečinné sezení nestojí nic — ani
  kontext, ani tokeny — takže se staré prostě opustí. `Stop-Process` mířící na
  předka procesu patří do deny listu, ne do skillu.
- **Víc batonů současně.** Jeden workspace, jeden baton. Workspace Discipline je
  výslovná v tom, že práce na několika tiketech je proložená, ne paralelní.
  Problém k řešení není souběh, ale **přežití přepnutí větve** — to řeší guardy
  a invalidace.

## Technický návrh

### 1. Baton: formát, umístění, životní cyklus

**Cesta:** `<MB_ROOT>/.superpowers/session-intent.md`. Zůstává git-ignorovaný
(`.gitignore` pokrývá `.superpowers/`), **bez výjimky**.

**Jazyk anglicky** — `.superpowers/` scratch je AI-facing (proto je i
`playbook-candidates/<slug>.md` anglicky) a obsah batonu jde doslova do
`additionalContext`, tedy do textu pro model. Česky je až to, co o rotaci uslyší
operátor.

**Tvar.** První řádek je identitní: `# Session intent — <ISO-8601 UTC>`. Pak blok
ukazatelů `Klíč: hodnota` po řádcích — stejná konvence jako `context.md`, ne JSON:
hook obsah emituje doslova, takže čitelnost pro člověka i model je přesně to, co
je potřeba, a nic se nerenderuje. Povinné jsou `Kind`
(`plan-execution` | `plan-resume`), `Plan`, `Branch`, `Slug`; volitelné `Spec`,
`Ticket`, `Ledger`, `Next task`. **Volitelný klíč bez hodnoty se vynechává, nikdy
se nepíše prázdný.** Poslední je jedna řádka `Instruction:` jmenující skill.
Cesty jsou relativní k `MB_ROOT`.

```
# Session intent — 2026-09-01T14:32:07Z

Kind: plan-execution
Plan: memory-bank/proposals/active/plan_baton_rotace_kontextu.md
Spec: memory-bank/proposals/active/design_baton_rotace_kontextu.md
Branch: baton-rotace-kontextu
Slug: baton_rotace_kontextu

Instruction: Invoke the subagent-driven-development skill and execute the plan above.
```

`plan-resume` je týž tvar s `Ledger:` a `Next task:`. Obojí je formálně
volitelné, ale rotační stop je píše vždy — bez nich by se čerstvé sezení muselo
dopočítávat z checkboxů.

**`Branch` a `Slug` jsou origin binding, ne dekorace.** Jsou to hodnoty, proti
kterým hook validuje. Baton, kterému kterákoli z nich chybí, je neplatný a
zachází se s ním jako se zvětralým.

**Consume-on-read.** Čtenář soubor hned po emisi přejmenuje na
`session-intent.consumed.md` (přepíše případný předchozí). Baton zamítnutý
guardem jde na `session-intent.stale.md` a neemituje se nic. **Nikdy se nemaže**
— zmatený operátor si má mít co přečíst.

**Invalidace** je totéž přejmenování na `session-intent.stale.md`, provedené tím,
kdo pracovní položku ukončuje nebo odkládá. Není to číslovaný krok žádné sekvence
— baton je git-ignorovaný, takže s commitem ani pushem nemá vztah pořadí — je to
bookkeeping, který proběhne, než skill ohlásí výsledek.

**Proč se baton neverzuje.** `.superpowers/` je dvouvrstvý a kritérium je hranice
obnovitelnosti z Workspace Discipline — existuje ta informace ještě někde jinde?

- `playbook-candidates/<slug>.md` — **neexistuje.** Proto jmenovaná výjimka
  v Playbook Contractu, `git add -f` ve `mb-park`, pravidlo „tracked znamená
  živé" a odstranění až harvestem.
- `sdd/<plan-basename>/` — **existuje**, v checkboxech plánu a v git logu. Proto
  `rm -rf <workspace>` po čistém finálním review a nikdy commit.

Baton nepatří ani do jedné vrstvy. Jeho životnost jsou desítky sekund až minuty a
jeho ztráta nestojí nic — fallback je, že operátor napíše záměr sám, což je
dnešní chování. Commit by naopak **aktivně škodil**: soubor by se vracel na každém
checkoutu té větve, v každém workspace i ve svěžím klonu, a `startup` za pár dní
by přehrál zvětralou instrukci — přesně to selhání, kvůli kterému consume-on-read
existuje, jen zavlečené přes git. Navíc by to nutilo `mb-park` rozhodovat, jestli
baton commitnout, a commitnutá instrukce „vykonej tenhle plán" publikovaná na
`origin` je živé nebezpečí pro každé obnovující sezení.

**Zápis do kontraktu:** nová podsekce `### Session Intent Baton` pod sekcí
`## Scope Lock (Memory Bank documents only)`, vložená mezi blok „Other rules:" a
podsekci o konvencích odkazů. Stojí tam **vedle** věty o kandidátech playbooku,
ne v ní, a ten kontrast je celý smysl umístění: existující věta *„One named
exception to the git-ignored rule"* zůstává po zavedení batonu **pravdivá**,
protože baton žádnou výjimkou není. To se do podsekce napíše výslovně, aby to
příští kolo „nesrovnalo". Podsekce jmenuje cestu, identitní řádek, povinné klíče,
roli `Branch`/`Slug` jako origin bindingu, consume-on-read, dispozici zvětralého
batonu, invalidaci a pravidlo o nekomitování **spolu s jeho důvodem**.

Dva doprovodné zásahy ve stejném commitu: výčet obsahu scratch tree v Scope Locku
(dnes „task briefs, implementer reports, review packages, progress ledger,
`playbook-candidates/<slug>.md`") dostane `session-intent.md`, jinak je to
uzavřený výčet, který nový soubor míjí; a hlavička kontraktu jde na **v2.12**
včetně přeformulování řádku, který byl current předtím (`Supersedes v2.11` →
`v2.11 superseded v2.10`), jak žádá [playbook.md](../../playbook.md), sekce
„Kontrakt a skilly: soudržnost pravidel a dokumentů".

### 2. Konzumující hook

**Soubor:** `ums/.claude/hooks/session-intent.ps1`, nasazuje se do
`.claude/hooks/`. Kód i komentáře anglicky, jako
[`guard-git-push.mjs`](../../../ums/.claude/hooks/guard-git-push.mjs) — celý jeho
výstup je AI-facing.

Celé tělo je v `try/catch`, jehož `catch` mlčí a končí `exit 0`: `SessionStart` je
informační, exit 2 nic neblokuje, takže hook nesmí být schopen zabránit startu
sezení. Chování v tomto pořadí:

1. `MB_ROOT` z `git rev-parse --show-toplevel` — jediný discovery krok dle
   kontraktu. Není to repozitář, nebo příkaz spadne → `exit 0` mlčky.
2. `session-intent.md` neexistuje, nebo je prázdný či jen whitespace → `exit 0`
   a **žádný výstup**. Ne prázdný `additionalContext`.
3. **Branch guard — nosný.** `Branch:` z batonu proti
   `git rev-parse --abbrev-ref HEAD`. Neshoda → přejmenovat na `.stale.md`,
   neemitovat nic, `exit 0`. Chybějící `Branch:` je rovněž zvětralost. Detached
   HEAD vrací `HEAD`, což se neshodne s žádným jménem větve, tedy zvětralé —
   správná odpověď.

   Tohle je guard, na kterém záleží. Bez něj: operátor dokončí plán na tiketu A,
   baton se napíše, a místo `/clear` operátor zaparkuje A a přepne na B.
   `.superpowers/` je git-ignorovaný, takže baton s checkoutem nepocestuje —
   prostě zůstane. Příští sezení na větvi B ho spolkne a začne vykonávat plán A
   na špatné větvi.
4. **Slug guard — druhotný.** `Slug:` proti slugu z `<CTX_DIR>/context.md`
   (`- **Work item:**`, plus legacy alias `- **Proposal:**`, který kontrakt
   readerům nakazuje přijímat). Neshoda → zvětralé. **Nečitelný nebo pin-less
   `context.md` je „žádný názor", tedy průchod** — branch guard nese zátěž sám.

   Důvod je formulovaný jinak než v zadání: slug guard má chytat jen případ, kdy
   se pin posunul na jinou práci. „Nemám co porovnat" není nález a fail-closed
   tady nemá co chránit, protože větev už je ověřená. Zdůvodnění „IDLE
   `context.md` je legitimní stav v okamžiku konzumace `plan-execution` batonu"
   po zavedení invalidace (sekce 4) skoro neplatí — invalidace ruší baton právě
   na těch cestách, které `context.md` na IDLE resetují — a chybný důvod
   v kontraktu je budoucí rozchod.
5. **Věk** z identitního řádku, vyrenderovaný do emitovaného textu. **Bez tvrdé
   expirace** — napsat baton a jít na oběd je legitimní, takže pevné okno by
   překáželo. Nad ~12 h hook do instrukce napíše, že sezení má před jakýmkoli
   dispatchem potvrdit s operátorem. Aritmetiku dělá hook, ne model.

   Dva okrajové tvary prvního řádku se rozlišují: řádek, který **vůbec
   neodpovídá** identitnímu tvaru → zvětralé (to není baton); řádek, který tvaru
   odpovídá, ale **timestamp se nenaparsuje** → emituje se s `age unknown` a
   s toutéž potvrzovací instrukcí jako přestárlý baton.
6. Emise `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`,
   skládaná `ConvertTo-Json -Compress` nad objektem, ne konkatenací řetězců —
   escapování uvozovek a nových řádků nemá být na autorovi. Obsah batonu doslova,
   obalený `<session-intent age="…">…</session-intent>`, a za ním věta, že baton
   je tímto zkonzumovaný a už se nedoručí, plus věková instrukce.
7. **Přejmenování až po emisi**, `Move-Item -Force` (přepíše případný předchozí
   `.consumed.md`). Pád mezi emisí a přejmenováním ztratí baton, což degraduje na
   dnešní chování — přijatelný směr selhání; obrácené pořadí by baton ztratilo
   bez emise.

**Testy** — `ums/.claude/hooks/tests/session-intent.tests.ps1`, konvence
sousedních sad dle [playbook.md](../../playbook.md), sekce „Testy vrstvy": bez
Pesteru, `. (Join-Path $PSScriptRoot '_assert.ps1')`, aserční hlášky česky,
fixtura je lokální throwaway git repo, offline. Osmnáct případů:

| # | Případ | Očekávání |
|---|---|---|
| 1 | chybějící soubor | žádný výstup, exit 0 |
| 2 | prázdný / whitespace soubor | žádný výstup, exit 0 |
| 3 | platný odpovídající baton | validní JSON na stdout **i** přejmenování na `.consumed.md` |
| 4 | neshoda větve | žádný výstup, přejmenování na `.stale.md` |
| 5 | neshoda slugu | totéž |
| 6 | chybějící `Branch:` | zvětralé |
| 7 | chybějící `Slug:` | zvětralé |
| 8 | chybějící `context.md` | slug guard propustí |
| 9 | IDLE `context.md` (bez pinu) | slug guard propustí |
| 10 | přestárlý baton | emituje se, věk vyrenderovaný, potvrzovací instrukce |
| 11 | druhé zavolání po konzumaci | žádný výstup |
| 12 | zamčený / nečitelný soubor | exit 0, žádný pád |
| 13 | není to git repozitář | exit 0, žádný výstup |
| 14 | první řádek není identitní tvar | zvětralé |
| 15 | identitní tvar s neparsovatelným časem | emituje se s `age unknown` |
| 16 | detached HEAD | zvětralé |
| 17 | emitované JSON zpětně naparsované | `additionalContext` obsahuje tělo batonu doslova |
| 18 | už existující `.consumed.md` | přejmenování ho přepíše |

Případy 13–18 jsou nad zadání. Případ 17 existuje proto, že regex nad stdout by
nerozeznal validní JSON od poskládaného řetězce. Zamčený soubor (12) se dělá
exkluzivním `FileStream` (`FileShare.None`) drženým po dobu běhu — na Windows to
`Get-Content` spolehlivě shodí, takže ten případ je reálně implementovatelný, ne
dekorativní.

**Negativita je součást úlohy, ne bonus.** Každý guard se mutuje zvlášť a
výsledek se třídí do **tří** kategorií dle playbooku — zčervenalo / zelené
v obou bězích (regresní zámek) / neprovedeno za bodem přerušení. U branch guardu
zvlášť platí, že mutace nesmí zezelenat tím, že vyprázdní kolekci: „neemitovalo
se nic" je i legitimní stav, takže pozitivní kontrola (platný baton se emituje)
musí být ve stejné mutaci červená.

### 3. Zapojení do `settings.json` a harness matice

**3a. Druhý `SessionStart` záznam**, stávající zůstává nedotčený — víc hooků se
spustí a každý přispěje vlastním `additionalContext`:

```json
{ "matcher": "clear|startup|resume",
  "hooks": [ { "type": "command",
    "command": "pwsh -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/session-intent.ps1\"" } ] }
```

Stávající záznam matcher **nemá**, takže střílí na každý zdroj startu. Nový ho má
proto, aby baton nezkonzumoval start vyvolaný kompaktací: kdyby operátor po
rotačním stopu napsal `/compact` místo `/clear`, sezení, které plán právě
vykonává, by dostalo zpátky vlastní instrukci „vykonej tenhle plán". Přesný výčet
zdrojů `SessionStart` v tomto harnessu se při implementaci ověří proti
dokumentaci a citace se zapíše vedle záznamu — playbook to u konfiguračního
klíče cizího nástroje bez citace v zadání žádá výslovně.

**3b. Uzavření asymetrie `SessionStart` × `PostCompact`.** `PostCompact` už
nakazuje po kompaktaci znovu přečíst ledger na
`.superpowers/sdd/<plan-basename>/progress.md`; `SessionStart` ne. Tato věta se
tam dopíše. Stojí na vlastních nohou i bez batonu: bez ní `/clear` uprostřed
plánu zahodí `Ruling:` řádky, odložené minory a zaparkované nálezy — informaci,
kterou by `/compact` zachoval, což je přesně obráceně.

**3c. Precondice u zapisovatelů.** `settings.json` se na ne-Claude cíle záměrně
nenasazuje, ale `mb-*` skilly a overlay fragmenty ano. Na Codexu, Gemini nebo
Kilo Code by tedy `writing-plans` baton **napsal a nikdo by ho nepřečetl** —
ležel by tam, dokud by ho v tomtéž workspace nezkonzumovalo pozdější sezení
v Claude Code, se zvětralou instrukcí. Branch guard většinu toho zneškodní a
věková instrukce zbytek, ale instrukci, kterou nic nekonzumuje, není důvod psát.

Obě zapisující místa (třetí volba exekuce, rotační stop) proto ověří, že
konzument existuje: hook je registrovaný v `settings.json` **a** soubor existuje
na rozřešené cestě. Chybí-li, třetí volba se nenabídne vůbec a rotační stop se
ohlásí s tím, že se záměr automaticky nedoručí. Je to tatáž figura, kterou vrstva
už má u `pre-push`: hooky s klonem necestují, takže workspace, který vypadá jako
funkční, může celý mechanismus postrádat — a odliší to jen kontrola v tomto
prostředí.

**3d. Matice harnessů.** Nový řádek do [`ums/README.md`](../../../ums/README.md),
sekce „Harness compatibility", vedle stávajících mechanismů — „Session intent
baton delivery": Claude Code = `SessionStart` hook `session-intent.ps1`
s matcherem; ostatní harnessy = žádný ekvivalent, zapisovatel proto handoff
nenabídne a degraduje na to, že operátor záměr napíše sám.

### 4. Invalidace v životním cyklu

**Rámování:** baton **není** pátá položka soupisu zbytků ve `mb-park`. Soupis
vypisuje práci, která se musí zachovat; baton je instrukce, která se musí
zneplatnit. Je to krok workflow, ne řádek reportu — v českém reportu se nikdy
neobjeví jako něco, co zůstává, protože nezůstává nic.

Operace i rámování mají **jeden domov v kontraktu** (podsekce
`### Session Intent Baton`, sekce 1). Každé místo nese jen jednu řádku
„a zneplatni baton (kontrakt, Session Intent Baton)" plus to, co je čistě
lokální. Čtyři místa:

| Místo | Kdy | Proč právě tady |
|---|---|---|
| `mb-harvest`, krok reset `context.md`, **podmíněno úspěchem** | dokončení pracovní položky | Harvest provádí `mb-harvest`, a ten se volá i **samostatně**, mimo finishing — overlay by tu cestu minul. Harvest navíc smí částečně selhat („on partial failure, leave `context.md` unchanged and report"); pak pracovní položka neskončila a baton má přežít. Vazba na úspěšný reset je jediné umístění, které to drží. |
| [`mb-abort`](../../../ums/.claude/skills/mb-abort/SKILL.md), krok reset `context.md` | opuštění | Pracovní položka končí, `context.md` jde na IDLE; nevyřízený `plan-execution` baton je jednoznačně neplatný. |
| `finishing-a-development-branch.overlay.md`, discard cesta | opuštění přes finishing | Ta cesta abandon sekvenci **provádí sama**, nevolá `mb-abort`, takže ji předchozí řádek nepokrývá. Jediné ze čtyř míst, které vyžaduje revendor. |
| [`mb-park`](../../../ums/.claude/skills/mb-park/SKILL.md) — **dvě invokace** | odložení | Viz níže. |

**`mb-park`: invaliduje se tam, kde park jedná — ne tam, kde odmítl jednat.**
Krok 0 má pět výstupů a dva z nich jsou STOP:

- **„Není co parkovat" (IDLE)** → invalidovat. Tohle je ta děra, kterou
  invalidace zavírá: slug guard pin-less `context.md` **propustí** (žádný názor),
  takže baton by na téhle větvi skutečně vystřelil, i když pracovní položka už
  skončila.
- **„Práce je už zaparkovaná"** → invalidovat. Důvod parkování je nezměněný.
- **Park proběhl** → invalidovat.
- **STOP „chráněná větev"** a **STOP „detached HEAD"** → **neinvalidovat.** Dva
  důvody. Věcný: park nejednal, plán na téhle větvi dál běží, takže baton je
  pořád platný a jeho zneplatnění by operátorovi vzalo funkční handoff. A
  mechanický, silnější: report té cesty doslova tvrdí *„Nic jsem necommitnul,
  nic nepushnul a nic nezahodil."* Přejmenování je akce — invalidace tam by tu
  větu učinila nepravdivou, což je přesně třída nálezu, na kterou playbook má
  pravidlo „hláška musí ten stav v TOMTO běhu přečíst, ne dovodit".

IDLE výstup v kroku 0 předchází oba STOPy, takže jedno umístění tuto podmínku
vyjádřit nedokáže. Budou to dvě invokace v jednom skillu — jedna na IDLE
výstupu, druhá až za STOPy. Není to zdvojené pravidlo (to má domov v kontraktu),
jsou to dva volací body, což playbook výslovně dovoluje.

**Verifikace** u všech čtyř: s batonem na místě spustit skill a potvrdit
přejmenování na `.stale.md` a že ho ani report, ani žádná early-exit hláška
nejmenuje jako zbytek; bez batonu potvrdit chování beze změny; u chráněné větve
potvrdit, že `session-intent.md` **zůstal**.

### 5. Pátá stop třída: rotace kontextu

Nový bullet do existujícího fragmentu
`subagent-driven-development.overlay.md` (kotva `ANCHOR: EOF`), hned za stávající
bullet „Rulings and STOPs" — aby čtenář narazil na „čtyři třídy a fail-closed
STOPy téhle vrstvy do nich padají" a **teprve pak** na pátou. Do ASSERT sady se
nic nepřidává: `Four things stop you, and only these: an irreversible or
destructive` tam už je a je to sémantická kotva této změny.

Obsah:

- Povoleno **jen na hranici tasku** — po zapsání dokončovací řádky do ledgeru a
  odškrtnutí toda, před dalším dispatchem. Nikde jinde. Hranice je celý smysl:
  uprostřed tasku je stav na disku nekompletní a rotace zahodí živý review cyklus.
- Na té hranici, jeví-li se zbývající kontext jako nedostatečný na další task:
  napsat baton (`Kind: plan-resume`, cesta plánu, cesta ledgeru, větev, slug,
  číslo dalšího nedokončeného tasku), ohlásit česky a zastavit s jedinou
  instrukcí — napsat `/clear`.
- Je to **úsudek, ne měření**; měřič operátora rozhoduje v **obou** směrech.
  Detektor prahu se nestaví ani nepředstírá.
- Precondice ze sekce 3c: chybí-li registrovaný konzument, baton se nepíše.
- Aditivní: čtyř existujících tříd se nedotýká a neoslabuje je.

Tři doplnění nad zadání:

1. **Je to handoff stop, ne eskalační.** Upstream čtyři třídy znamenají „zastav a
   **zeptej se**", tedy pokračování v tomtéž sezení po odpovědi. Rotace znamená
   „tohle sezení končí". Vrstva už jeden takový stop má — Architect Review Gate.
   Bez této věty si to příští čtenář přečte jako pátou věc, na kterou se má ptát.
2. **Obnovené sezení nesmí znovu spustit base sync ani baseline.** Bullet
   „Base sync" říká „before dispatching the first task — a phase boundary".
   Čerstvé sezení, které si skill čte odshora, si „first task" snadno přečte jako
   první task **svého** sezení — a mergne bázi uprostřed fáze, což ten samý
   bullet zakazuje. `Next task: N` v batonu je rozlišující informace: povinná
   baseline a merge báze patří k tasku 1 **plánu**, ne k tasku 1 sezení.
3. **Ledger dostane řádek o rotaci** — ne `Ruling:` (není to rozhodnutí
   konfliktu), ale poznámku, že sezení bylo v tomto bodě rotováno. Ledger je
   resumpční záznam; bez ní se čerstvé sezení dívá na ledger, který prostě končí,
   a nemá jak odlišit rotaci od pádu.

**Sweep počítacích vět.** Zavedení páté třídy láme věty, které počítají do čtyř:

| Soubor | Text | Zásah |
|---|---|---|
| kontrakt, sekce „Fail-Closed Behavior", odstavec „Rulings and these STOPs" | *„stops only for four named classes. The fail-closed STOPs of this layer are not a fifth class — they FALL WITHIN those four"* | Zůstává pravdivé **o fail-closed STOPech**, ale vedle nich teď jedna pátá třída existuje. Přeformulovat, jinak kontrakt popírá overlay. |
| [`ums/CLAUDE.md.sample`](../../../ums/CLAUDE.md.sample) | *„STOP jen pro čtyři jmenované třídy"* | **Nepravdivé.** Přepsat. |
| [`CLAUDE.md`](../../../CLAUDE.md) | tentýž text | **Nepravdivé.** Přepsat rovněž — viz poznámka o dvou paralelních kopiích níže. |
| SDD overlay, bullety „Rulings and STOPs" | *„fall within the four stop classes"*, *„the four classes mean"* | Zůstávají pravdivé (mluví o fail-closed STOPech a o slově „merge"). Neměnit — a právě proto musí nový bullet stát za nimi. |

**Dvě paralelní kopie týchž preferencí, ani jedna generovaná z druhé.**
[`ums/CLAUDE.md.sample`](../../../ums/CLAUDE.md.sample) je zdroj bloku, který
`sync-with-monorepo.ps1` vkládá do instrukčního souboru **cílů nasazení** (mezi
markery `UMS-MEMORY-BANK BEGIN/END`). Kořenový [`CLAUDE.md`](../../../CLAUDE.md)
tohoto forku nese blok se **stejným markerovým tokenem, ale jiným popisem**
(„fork-only section, exists on branch ums-memory-bank") a sync na kořen forku
nikdy nemíří. Je to tedy ručně udržovaná paralelní kopie: **oba soubory se musí
editovat, ve stejném commitu, a ani jeden se z druhého neregeneruje.** Kdo opraví
jen jeden, nechá druhý lhát.

### 6. Třetí volba exekuce ve `writing-plans`

Nový fragment `ums/.claude/skills/shared/overlays/writing-plans.overlay.md` — pro
tento skill dosud žádný neexistuje.

**Kotva:** `ANCHOR-BEFORE: **Which approach?"**`, ne
`**If Subagent-Driven chosen:**` ze zadání. Obě jsou v
[`skills/writing-plans/SKILL.md`](../../../skills/writing-plans/SKILL.md)
unikátní (ověřeno), ale druhá by vložila třetí volbu **za** otázku „Which
approach?", takže menu by znělo „dvě možnosti… 1… 2… Kterou?" a teprve pak by
přišla trojka.

**ASSERT sada** — tři direktivy, každá matchne právě jeden řádek (ověřeno
strojově proti dnešnímu souboru):

```
<!-- ASSERT: **"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:** -->
<!-- ASSERT: **1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration -->
<!-- ASSERT: **2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints -->
```

Přepis menu upstreamem tak shodí revendor hlasitě, místo aby nechal třetí volbu
viset u změněné dvojice. První direktiva je zároveň ta věta, kterou tělo
fragmentu neguje (níže).

**Ten intro řádek je nepravdivý dvakrát** — „Two" (budou tři) i cesta
`docs/superpowers/plans/<filename>.md` (UMS ukládá do
`<PLAN_MB>/proposals/active/plan_<slug>.md` a `docs/superpowers/plans/` je
blokovaná hookem). Playbook je tu jednoznačný: negovaný upstream text zůstává
viditelný vedle přebíjejícího, takže fragment musí obě poloviny **jmenovitě
negovat v jednom odstavci**. Cesta není rozšíření rozsahu — je to tatáž věta,
kterou je kvůli počtu nutné negovat tak jako tak.

**Tělo:** menu se rozšiřuje ze dvou na tři, **žádná druhá otázka, žádný práh
počtu tasků**. Ruling Discipline říká rozhodnout, ne stát, a přilepit druhý
prompt na menu, které se už ptá na správnou věc, je právě to stání. Volba nese
*doporučení* („vhodné u větších plánů, nebo když se návrhový dialog protáhl"),
rozhoduje operátor.

Při volbě 3: napsat baton (`Kind: plan-execution`, cesta plánu, cesta specu,
větev, slug, tiket), předat režimem doručení daného workspace (dnes jediný:
`/clear`), ohlásit česky **jedním krátkým odstavcem a skončit**. Nic
nedispatchovat, nenabízet pokračování v tomto sezení. Fragment výslovně řekne,
proč je to u velkých plánů lepší než volba 1: příští sezení dostane
**zkonstruovaný** brief místo toho, co si operátor vzpomene napsat, a startuje
bez jediného řádku brainstormingového transkriptu.

Záměrně **není** součástí: číslo „kolik tasků na sezení". Rotační stop to
rozhoduje znovu na každé hranici tasku ze skutečného zbývajícího kontextu, což je
lepší informace než cokoli dostupného v době plánování, kdy velikosti tasků ještě
nikdo nezná. Případný strop patří do souboru plánu, ne do batonu — baton se
konzumuje jednou, strop platí pro celou exekuci.

**Sweep počítacích vět o počtu overlay bloků.** Tohle je čtvrtý fragment, takže
každá věta, která tvrdí „přesně 3", se láme. Grep přes `ums/`, `memory-bank/` a
`CLAUDE.md` našel **sedm** míst; zadání nejmenuje ani jedno. Dělí se podle
vlastníka — část patří implementaci, část harvestu:

| Soubor | Text | Kdo opraví |
|---|---|---|
| `ums/.claude/skills/shared/SKILLS_MANIFEST.md` | *„UMS overlay bloky mají přesně 3: …"* | implementace (je to soubor vrstvy) |
| [`CLAUDE.md`](../../../CLAUDE.md) | *„Přesně 3 overlay bloky (brainstorming, SDD, finishing)"* a *„tři overlay body zásahu UMS"* | implementace (AI-facing instrukce musí být pravdivá v okamžiku, kdy fragment vznikne) |
| [architecture.md](../../architecture.md) | *„UMS do něj vstupuje přesně třemi overlay bloky"* | **harvest** |
| [architecture.md](../../architecture.md), sekce „Dvouvrstvá mechanika vynucení" | *„a všechny tři overlay fragmenty"* — věta o konzumentech sdílených skriptů; nový fragment je nekonzumuje, takže „všechny tři" je po jeho vzniku dvojznačné | **harvest** (přeformulovat na jmenný výčet) |
| [tech.md](../../tech.md) | *„Overlay bloky \| přesně 3 (…)"* | **harvest** |
| [playbook.md](../../playbook.md), sekce „Obnova nasazené kopie v tomto repu" | *„tři vendorované skilly s overlay bloky se musí srovnávat proti monorepo kopii"* a *„Tři upstream skilly s overlay bloky (…) se kopií nevyrobí"* | **harvest, přes konzultační bránu** — `playbook.md` se nikdy nemění bez schválení |

Rozdělení není formalita: MB dokumenty popisují aktuální stav a jejich
aktualizace je práce harvestu (Harvest Contract, current-state průchod plus
staleness sweep). Kdyby je opravovala implementace, harvest by pak neměl co
najít. Zároveň se na štěstí staleness sweepu nespoléhá — tato tabulka je jmenuje
adresně, takže harvest má seznam, ne jen greppovací heuristiku.

## Odchylky od zadání a jejich důvody

| Odchylka | Důvod |
|---|---|
| Kotva `**Which approach?"**` místo `**If Subagent-Driven chosen:**` | Třetí volba patří k volbám 1 a 2, před otázku. |
| ASSERT i na intro řádek menu; fragment neguje „Two" **i** cestu | Ta věta se stane nepravdivou; obě nepravdy jsou v jedné větě. |
| `mb-harvest` místo finishing overlay jako místo invalidace při dokončení | Harvest se volá i samostatně; a částečné selhání harvestu nesmí baton zneplatnit. |
| Čtvrté místo invalidace: discard cesta ve finishing overlay | Ta cesta abandon provádí sama, nevolá `mb-abort`. |
| `mb-park`: neinvalidovat na STOPech, dvě invokace | Report STOPu tvrdí „nic jsem nezahodil"; a park tam nejednal, takže baton je platný. |
| Invalidace není číslovaný krok | Vyhýbá se přidávání položky do dvou číslovaných seznamů a celé třídě rizika, na kterou playbook má vlastní pravidlo. |
| Slug guard zdůvodněný jinak než „IDLE je legitimní stav" | Původní důvod po zavedení invalidace skoro neplatí; chování zůstává. |
| Šest testovacích případů nad zadání (13–18) | Git-less prostředí, dva okrajové tvary identitního řádku, detached HEAD, zpětné parsování JSON, přepis `.consumed.md`. |
| Precondice „konzument existuje" u obou zapisovatelů | `settings.json` se na ne-Claude harnessy nenasazuje, skilly ano. |
| Dva sweepy počítacích vět: čtyři stop třídy (4 místa) a počet overlay bloků (7 míst) | Zadání nejmenuje ani jedno místo. Obojí se láme právě tím, co tato práce přidává. |
| `ums/CLAUDE.md.sample` a `CLAUDE.md` se editují oba ručně | Sync na kořen forku nemíří; jsou to dvě paralelní kopie se stejným markerovým tokenem, ale jiným popisem. |
| Revendor plným průchodem s pinovaným tagem, ne `-OverlaysOnly` | `-OverlaysOnly` funguje jen na pristine soubory; naměřeno v playbooku. |
| Obnovené sezení nesmí znovu spustit base sync / baseline | Jinak je rotace přímý spouštěč operace, kterou SDD overlay zakazuje. |
| Řádek o rotaci do ledgeru | Bez něj nelze odlišit rotaci od pádu sezení. |

## Dopady

Soupis dotčených souborů. Zdroj je vždy `ums/`; kořenové `.claude/` a
`.agents/skills/` jsou netrackovaná **nasazení**, která se obnovují poslední
úlohou plánu (viz [playbook.md](../../playbook.md), sekce „Obnova nasazené kopie
v tomto repu").

**Nové soubory**

- `ums/.claude/hooks/session-intent.ps1`
- `ums/.claude/hooks/tests/session-intent.tests.ps1`
- `ums/.claude/skills/shared/overlays/writing-plans.overlay.md`

**Změněné soubory**

- `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — podsekce
  `### Session Intent Baton`, výčet scratch tree ve Scope Locku, odstavec
  „Rulings and these STOPs", verze na 2.12 se přeformulovaným „Supersedes"
- `ums/.claude/settings.json` — druhý `SessionStart` záznam, ledgerová věta ve
  stávajícím `additionalContext`
- `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md` —
  bullet páté stop třídy
- `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` —
  invalidace na discard cestě
- `ums/.claude/skills/mb-harvest/SKILL.md`, `mb-abort/SKILL.md`,
  `mb-park/SKILL.md` — invalidace
- `ums/CLAUDE.md.sample` a `CLAUDE.md` — počet stop tříd (oba, ručně; ani jeden
  se z druhého neregeneruje) a v `CLAUDE.md` navíc počet overlay bloků
- `ums/README.md` — řádek v matici harnessů
- `ums/.claude/skills/shared/SKILLS_MANIFEST.md` — nový fragment v tabulce a
  oprava věty „přesně 3"
- `memory-bank/tasks.md` — dvě navazující položky

**Patří harvestu, ne plánu:** [architecture.md](../../architecture.md),
[tech.md](../../tech.md) a [playbook.md](../../playbook.md) — počty overlay bloků
a nová mechanika batonu. Adresný seznam vět je v sekci 6.

**Nasazení a regenerace** (poslední úloha plánu): obnovit `.claude/` a
`.agents/skills/` z `ums/.claude/`, pak plný revendor s `-Tag v6.3.0`, pak
dorovnat vendorované skilly do `.agents/skills`. `install-git-hooks.ps1` se
nespouští — git `pre-push` hook se tato práce nedotýká.

## Rizika

- **Baton vystřelí na správné větvi se zvětralým záměrem.** Branch guard hlídá
  větev, slug guard posun pinu, invalidace pokrývá tři konce životního cyklu.
  Zbývající scénář: operátor napíše baton, nic neudělá, a za tři dny na téže
  větvi otevře sezení. Chytá to věková instrukce (nad ~12 h potvrdit
  s operátorem), ne tvrdá expirace — vědomě, protože pevné okno by překáželo.
- **Kotva `**Which approach?"**` je jediné místo citlivé na drift upstreamu**
  v novém fragmentu. Anchor-miss je detektor, ne chyba k obejití; tři ASSERT
  direktivy navíc shodí i přepis menu, který kotvu nechá na místě.
- **Precondice „konzument existuje" je jen tak silná jako její kontrola.**
  Ověřuje registraci v `settings.json` a existenci souboru; nedokáže ověřit, že
  harness hook skutečně spouští. Fail direction je bezpečný — baton se nenapíše,
  operátor napíše záměr sám.
- **Pátá stop třída se dá zneužít jako výmluva.** Model, který nechce
  pokračovat, může „nedostatek kontextu" prohlásit kdykoli. Omezení na hranici
  tasku, povinný zápis batonu s číslem dalšího tasku a řádek v ledgeru dělají
  z rotace auditovatelnou událost, ne tiché ukončení.
- **Rotace uprostřed fáze a base sync.** Popsáno v sekci 5, bod 2; bez té věty je
  to reálný spouštěč zakázaného mergu.

## Verifikace

- Sada `session-intent.tests.ps1` zelená; počty asercí získané spuštěním **celé**
  smyčky vrstvy po dávkách 1–4 souborů ve stejném sezení, delty rekonciliované
  proti předchozímu součtu, počet sad z `find ums -name "*.tests.ps1" | wc -l`.
- Negativita každého guardu se třemi kategoriemi výsledků.
- Revendor: plný průchod s `-Tag v6.3.0` po obnovení nasazení, pak
  `-VerifyOnly` čistě; grep na charakteristickou frázi obou fragmentů ve
  vygenerovaných souborech, včetně case-insensitive dokontroly.
- End-to-end obou případů užití: brainstorm → plán → volba 3 → `/clear` →
  čerstvé sezení dispatchne první task bez dalšího vstupu; a rotační stop na
  hranici tasku → `/clear` → pokračování od dalšího nedokončeného tasku.
- Negativní případ: volba 3, **ne**clear, přepnutí na jinou tiketovou větev,
  start sezení → nic se neinjektuje a baton skončil jako `.stale.md`.
- `git log --all -- '**/session-intent*.md'` **prázdný** — žádný baton,
  zkonzumovaný ani zvětralý, neexistuje nikde v historii větve.
- Žádný skill, skript ani záznam v `settings.json` nejmenuje rodičovský PID ani
  `Stop-Process`.

## Pořadí úloh

**3b → 1 → 2 → 4 (invalidace) → 5 (stop třída) → 6 (třetí volba).**

Task 3b jde první, protože je na batonu úplně nezávislý a stojí na vlastních
nohou. Invalidace musí ležet **před** třetí volbou — ta začne batony produkovat
právě ve fázi, kdy je přepnutí větve nejpravděpodobnější (plán napsaný, exekuce
ještě nezačala). Stop třída a třetí volba jsou na sobě nezávislé a dají se dělat
v jedné dávce, jakmile je invalidace na místě.

## Navazující položky

Vyčleněno z tohoto návrhu, dopíše se do [tasks.md](../../tasks.md):

1. **Režim doručení 2 — spawn a opuštění.** Agent založí čerstvé sezení v novém
   tabu (`wt.exe new-tab --startingDirectory <MB_ROOT> pwsh -NoProfile -Command
   claude`) a své vlastní opustí; nula vstupu operátora při handoffu. Nic se
   nezabíjí. Pořadí je povinné: napsat baton, pak spawnout, pak ukončit tah.
   Startovní adresář je nosný, protože hook řeší `MB_ROOT` přes
   `git rev-parse --show-toplevel`. Na příkazovou řádku se **nepředává žádný
   prompt** — jeden doručovací mechanismus, dva spouštěče. Chybějící `wt.exe`
   není chyba (běžný stav ve VS Code terminálu nebo přes SSH), vrací se odlišný
   status „unavailable" a volající degraduje na režim 1. Režim je per-workspace
   konfigurace, ne rozhodnutí modelu, s `clear` jako defaultem. Odloženo proto,
   že režim 1 musí být prokazatelně funkční dřív, než přibude druhá cesta —
   jinak má selhání handoffu dva kandidáty na příčinu.
2. **Zaparkovat SDD ledger jako evidenci.** `sdd/<plan-basename>/` je dnes
   klasifikovaný jako rekonstruovatelný (checkboxy plánu plus git log). Ledger je
   většinou to, ale ne úplně: jeho `Ruling:` řádky nesou rozhodnutí, jeho důvod a
   cenu chyby, plus odložené minory a zaparkované nálezy — **nic z toho v git
   logu není.** `mb-park` přitom slibuje obnovitelnost z `origin`, a ten slib pro
   rulingy neplatí. Konzistentní tvar je tatáž výjimka, jakou už mají kandidáti
   playbooku: `mb-park` ledger commitne (`git add -f`), obnovená práce do něj
   přidává, odstranění patří harvestu. Vyžaduje změny v Playbook Contractu a
   Workspace Discipline a úpravu bulletu „Finish" v SDD overlay. Odloženo proto,
   že mění plochu kontraktu a zaslouží si vlastní review — s batonem nesouvisí.
