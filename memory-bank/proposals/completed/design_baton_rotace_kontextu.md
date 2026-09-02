# Návrh: Session baton pro rotaci kontextu

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-01
- **Oponentura:** agentická, 2026-09-02 — 19 nálezů, závěry zapracovány níže

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
se třetí volbou exekuce; sweepy vět, které tato práce činí nepravdivými. Režim
doručení je právě jeden — operátor napíše `/clear`.

**Mimo rozsah, vědomě** (viz „Navazující položky"): druhý režim doručení (spawn
nového tabu přes `wt.exe` a opuštění vlastního sezení) a zaparkování SDD ledgeru
jako evidence.

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
  Problém k řešení není souběh, ale **přežití přepnutí větve**.

## Technický návrh

### 1. Baton: formát, umístění, životní cyklus

**Cesta:** `<MB_ROOT>/.superpowers/session-intent.md`. Zůstává git-ignorovaný
(`.gitignore` pokrývá `.superpowers/`), **bez výjimky**.

**Jazyk anglicky.** Kritérium je Language Contract sám, ne analogie: baton je
AI-facing text, jehož celý obsah jde do `additionalContext`, tedy do kontextu
modelu. Není to uživatelská hláška, na kterou by dopadalo pravidlo o češtině
u toho, „co agent nebo uživatel potká během práce s Memory Bank". Tuhle
distinkci ale contract dnes neumí vyjádřit — jeho výčet anglických artefaktů je
seznam tří vývojářských skriptů a hooky jmenuje na české straně (zamítací hlášky
`pre-push` a `guard-git-push.mjs`). **Language Contract proto dostane jednu
větu:** hook, jehož celý výstup je kontext pro model, je anglicky. Bez ní by byl
`session-intent.ps1` čtvrtým PowerShellovým artefaktem, který do žádné z obou
stran výčtu nepadá.

**Tvar.** První řádek je identitní: `# Session intent — <ISO-8601 UTC>`. Pak blok
ukazatelů `Klíč: hodnota` po řádcích — stejná konvence jako `context.md`, ne JSON:
je to čitelné pro člověka i pro model a nic se nerenderuje. Povinné jsou `Kind`
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

**Formát je uzavřený, a to je bezpečnostní vlastnost, ne úklid.** Baton je
git-ignorovaný soubor v pracovním stromu, takže ho může zapsat cokoli, co do
stromu píše — včetně implementátorských subagentů SDD, které do `.superpowers/`
píší běžně. Jeho obsah přitom míří **doslova do kontextu modelu**. Kdyby hook
emitoval tělo tak, jak leží, stačilo by do něj vložit ukončovací značku
`</session-intent>` a zbytek souboru by se stal instrukcí na nejvyšší úrovni.
Proto:

- hook **neemituje tělo doslova** — naparsuje známé klíče a **znovu je vyrenderuje**
  v kanonickém pořadí; nic jiného se do výstupu nedostane,
- **neznámý klíč nebo řádek mimo tvar `Klíč: hodnota` činí baton zvětralým**
  (fail-closed), ne jen tiše zahozeným,
- platí **strop velikosti** (řádově jednotky kilobajtů); jeho překročení je rovněž
  zvětralost.

Návrh si přitom tuhle úvahu už jednou udělal u gitu (commitnutá instrukce
publikovaná na `origin` je živé nebezpečí) a jen ji nedotáhl na lokální
zapisovatele. Zbytkové riziko je pojmenované v „Rizika".

**Validují se všechny čtyři povinné klíče, ne dva.** `Branch` a `Slug` jsou
navíc **origin binding** — hodnoty, proti kterým hook porovnává skutečný stav.
`Kind` musí být jedna ze dvou přípustných hodnot a `Plan` musí ukazovat na
**existující soubor**; plán smazaný harvestem nebo přejmenovaný je tím pádem
zvětralost, ne emitovaná instrukce mířící do prázdna.

**Consume-on-read.** Čtenář soubor hned po emisi přejmenuje na
`session-intent.consumed.md` (přepíše případný předchozí). Baton zamítnutý
guardem jde na `session-intent.stale.md` a neemituje se nic. **Nikdy se nemaže**
— zmatený operátor si má mít co přečíst.

**Invalidace** je totéž přejmenování na `session-intent.stale.md`, provedené tím,
kdo pracovní položku ukončuje nebo odkládá. Není to číslovaný krok žádné sekvence
— baton je git-ignorovaný, takže s commitem ani pushem nemá vztah pořadí — je to
bookkeeping, který proběhne, než skill ohlásí výsledek.

**Precedence mezi injekcemi na začátku sezení.** Na `SessionStart` běží dva hooky
a každý přispěje vlastním `additionalContext`; jejich pořadí není nikde
garantované. Jeden z nich říká „ověř publikační záruku a nepokračuj v práci,
která končí pushem", druhý „vykonej tenhle plán" — a exekuce plánu pushuje po
každém commitu. **Kontrakt proto stanoví přednost:** kontrola způsobilosti
z bootstrap bloku je **precondice** jednání podle batonu, nikdy naopak. Baton
nikdy nepřebíjí fail-closed bránu; neprojde-li, sezení hlásí a nedispatchuje.
Tutéž větu nese i patička, kterou hook připojuje za baton, aby to model viděl i
bez čtení kontraktu.

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
příští kolo „nesrovnalo".

Podsekce jmenuje: cestu; identitní řádek; **všechny čtyři** povinné klíče a
uzavřenost formátu; roli `Branch`/`Slug` jako origin bindingu; consume-on-read;
dispozici zvětralého batonu; invalidaci; **precondici zapisovatele** (sekce 3c —
implementují ji dva konzumenti, takže pravidlo patří sem, ne do obou fragmentů);
**precedenci** vůči bootstrap bloku; **výjimku pro mlčenlivý pád hooku** (viz
sekce 2); a pravidlo o nekomitování **spolu s jeho důvodem**.

Dva doprovodné zásahy ve stejném commitu: výčet obsahu scratch tree v Scope Locku
(dnes „task briefs, implementer reports, review packages, progress ledger,
`playbook-candidates/<slug>.md`") dostane `session-intent.md`, jinak je to
uzavřený výčet, který nový soubor míjí; a hlavička kontraktu jde na **v2.12**
včetně přeformulování řádku, který byl current předtím (`Supersedes v2.11` →
`v2.11 superseded v2.10`), jak žádá [playbook.md](../../playbook.md), sekce
„Kontrakt a skilly: soudržnost pravidel a dokumentů". Bump verze má vlastní
sweep — viz sekce 7.

### 2. Konzumující hook

**Soubor:** `ums/.claude/hooks/session-intent.ps1`, nasazuje se do
`.claude/hooks/`. Kód i komentáře anglicky (viz jazykové kritérium v sekci 1).

Celé tělo je v `try/catch`, jehož `catch` mlčí a končí `exit 0`: `SessionStart` je
informační, exit 2 nic neblokuje, takže hook nesmí být schopen zabránit startu
sezení. Chování v tomto pořadí:

1. `MB_ROOT` z `git rev-parse --show-toplevel` — jediný discovery krok dle
   kontraktu. Není to repozitář, nebo příkaz spadne → `exit 0` **mlčky**.

   To je **vědomá odchylka od kontraktu**, který u chybějícího gitu předepisuje
   tvrdé zastavení s hláškou `Git repository not found. Memory Bank requires
   git.` a jmenuje ho mezi hard failures. Pro hook to platit nemůže — hláška by
   šla do `SessionStart` výstupu a mlčenlivost je celá pointa. Výjimka proto
   **dostane domov v kontraktu** (podsekce `### Session Intent Baton`): hook,
   který smí jen přispět kontextem, nikdy nezastaví sezení a na každé chybové
   cestě končí nulou. Bez zapsané výjimky by příští čtenář hook „opravil" podle
   kontraktu.
2. `session-intent.md` neexistuje, nebo je prázdný či jen whitespace → `exit 0`
   a **žádný výstup**. Ne prázdný `additionalContext`.
3. **Tvarová validace.** První řádek musí odpovídat identitnímu tvaru; všechny
   čtyři povinné klíče musí být přítomné; `Kind` musí být jedna ze dvou hodnot;
   žádný neznámý klíč ani řádek mimo tvar; velikost pod stropem. Cokoli z toho
   selže → zvětralé.
4. **Branch guard — nosný.** `Branch:` z batonu proti
   `git rev-parse --abbrev-ref HEAD`, **case-sensitive** (`-ceq`, nikoli `-eq`:
   PowerShellovo `-eq` je na řetězcích case-insensitive, kdežto git refy
   case-sensitive jsou, takže baton pro `Feature-X` by prošel na větvi
   `feature-x`). Neshoda → přejmenovat na `.stale.md`, neemitovat nic, `exit 0`.
   Detached HEAD vrací `HEAD`, což se neshodne s žádným jménem větve, tedy
   zvětralé — správná odpověď.

   Tohle je guard, na kterém záleží. Bez něj: operátor dokončí plán na tiketu A,
   baton se napíše, a místo `/clear` operátor zaparkuje A a přepne na B.
   `.superpowers/` je git-ignorovaný, takže baton s checkoutem nepocestuje —
   prostě zůstane. Příští sezení na větvi B ho spolkne a začne vykonávat plán A
   na špatné větvi.
5. **Slug guard — druhotný.** `Slug:` proti slugu z `<CTX_DIR>/context.md`
   (`- **Work item:**`, plus legacy alias `- **Proposal:**`, který kontrakt
   readerům nakazuje přijímat), rovněž case-sensitive. Neshoda → zvětralé.
   **Nečitelný nebo pin-less `context.md` je „žádný názor", tedy průchod** —
   branch guard nese zátěž sám.

   Důvod je formulovaný jinak než v zadání: slug guard má chytat jen případ, kdy
   se pin posunul na jinou práci. „Nemám co porovnat" není nález a fail-closed
   tady nemá co chránit, protože větev už je ověřená. Zdůvodnění „IDLE
   `context.md` je legitimní stav v okamžiku konzumace `plan-execution` batonu"
   po zavedení invalidace (sekce 4) skoro neplatí — invalidace ruší baton právě
   na těch cestách, které `context.md` na IDLE resetují — a chybný důvod
   v kontraktu je budoucí rozchod.
6. `Plan:` musí ukazovat na existující soubor; neexistuje-li → zvětralé.
7. **Věk** z identitního řádku, vyrenderovaný do emitovaného textu. **Bez tvrdé
   expirace** — napsat baton a jít na oběd je legitimní, takže pevné okno by
   překáželo. Nad ~12 h hook do instrukce napíše, že sezení má před jakýmkoli
   dispatchem potvrdit s operátorem. Aritmetiku dělá hook, ne model. Identitní
   tvar s neparsovatelným časem se emituje s `age unknown` a s toutéž
   potvrzovací instrukcí.
8. Emise `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`,
   skládaná `ConvertTo-Json -Compress` nad objektem, ne konkatenací řetězců.
   Obsah je **znovu vyrenderovaný** blok známých klíčů (sekce 1), obalený
   `<session-intent age="…">…</session-intent>`, a za ním patička: baton je tímto
   zkonzumovaný a už se nedoručí; věková instrukce; a precedence — kontrola
   publikační záruky z bootstrap bloku platí přednostně.
9. **Přejmenování až po emisi**, `Move-Item -Force` (přepíše případný předchozí
   `.consumed.md`).

**Směr selhání v okně mezi emisí a přejmenováním je REPLAY, ne ztráta.** Nic
soubor před přejmenováním nemaže ani neznačkuje, a celé tělo je v mlčenlivém
`catch`, takže výjimka po zápisu na stdout nechá `session-intent.md` ležet — a
příští start ho emituje znovu. Je to tedy přesně ta zvětralá replay cesta, které
má consume-on-read bránit, jen zúžená na jedno okno. Ohraničují ji branch guard,
slug guard a věková instrukce; obrácené pořadí (přejmenovat, pak emitovat) by
naopak baton ztratilo bez emise, což je horší. Pořadí zůstává, ale analýza je
tímto opravená a **sada má na tuhle cestu vlastní případ** — samotný případ
„druhé zavolání po konzumaci" ji nepokryje, protože testuje jen větev, kde
přejmenování uspělo.

**Testy** — `ums/.claude/hooks/tests/session-intent.tests.ps1`, konvence
sousedních sad dle [playbook.md](../../playbook.md), sekce „Testy vrstvy": bez
Pesteru, `. (Join-Path $PSScriptRoot '_assert.ps1')`, aserční hlášky česky,
fixtura je lokální throwaway git repo, offline.

| # | Případ | Očekávání |
|---|---|---|
| 1 | chybějící soubor | žádný výstup, exit 0 *(zámek)* |
| 2 | prázdný / whitespace soubor | žádný výstup, exit 0 *(zámek)* |
| 3 | platný odpovídající baton | validní JSON na stdout **i** přejmenování na `.consumed.md` |
| 4 | neshoda větve | žádný výstup, přejmenování na `.stale.md` |
| 5 | neshoda větve **jen velikostí písmen** | zvětralé (chytá `-eq` místo `-ceq`) |
| 6 | neshoda slugu | zvětralé |
| 7 | chybějící `Branch:` | zvětralé |
| 8 | chybějící `Slug:` | zvětralé |
| 9 | chybějící `Kind:` | zvětralé |
| 10 | chybějící `Plan:` | zvětralé |
| 11 | `Plan:` míří na neexistující soubor | zvětralé |
| 12 | neznámý klíč v těle | zvětralé |
| 13 | tělo obsahuje `</session-intent>` | zvětralé; emitovaný výstup značku nikdy nenese |
| 14 | baton nad stropem velikosti | zvětralé |
| 15 | chybějící `context.md` | slug guard propustí |
| 16 | IDLE `context.md` (bez pinu) | slug guard propustí |
| 17 | přestárlý baton | emituje se, věk vyrenderovaný, potvrzovací instrukce |
| 18 | identitní tvar s neparsovatelným časem | emituje se s `age unknown` |
| 19 | první řádek není identitní tvar | zvětralé |
| 20 | detached HEAD | zvětralé |
| 21 | emitované JSON zpětně naparsované | obsahuje kanonicky vyrenderované klíče, ne tělo doslova |
| 22 | druhé zavolání po konzumaci | žádný výstup |
| 23 | přejmenování selže (soubor zamčený) po emisi | emise proběhla, soubor zůstal, další běh emituje **znovu** — doložení přijatého replaye |
| 24 | zamčený / nečitelný soubor při čtení | exit 0, žádný pád *(zámek)* |
| 25 | není to git repozitář | exit 0, žádný výstup *(zámek)* |
| 26 | už existující `.consumed.md` | přejmenování ho přepíše |

**Čtyři případy označené *(zámek)* nejsou důkaz.** Všechny čtyři mají orákulum
„žádný výstup, exit 0", které splní i hook, který nedělá vůbec nic — jsou to
regresní zámky, ne důkazy opravy, a v reportu se tak oddělí. Aby ta čtveřice
něco hlídala, musí ve stejném běhu existovat **pozitivní kontrola**, kterou
prázdný hook shodí: případ 3.

**Negativita podle playbooku je součást úlohy.** Každý guard se mutuje zvlášť a
výsledek se třídí do **tří** kategorií — zčervenalo / zelené v obou bězích
(regresní zámek) / neprovedeno za bodem přerušení. U branch guardu zvlášť platí,
že mutace nesmí zezelenat tím, že vyprázdní kolekci: „neemitovalo se nic" je i
legitimní stav, takže pozitivní kontrola musí být ve stejné mutaci červená. Pro
case-sensitivitu (případ 5) je mutací záměna `-ceq` za `-eq`, ne odstranění
guardu — mutace přítomnosti tuhle vlastnost nechá zelenou.

**Poznámka ke sdílené ploše:** `ums/.claude/hooks/tests/_assert.ps1` je jediný
soubor, který už dot-sourcují tři sady, a nese `Invoke-Hook` napevno namířený na
`guard-git-push.mjs`. Nový invoker se tedy přidává do sdílené plochy — přidat, ne
přepsat, a po změně spustit i tři stávající sady.

### 3. Zapojení do `settings.json` a harness matice

**3a. Druhý `SessionStart` záznam**, stávající zůstává nedotčený:

```json
{ "matcher": "clear|startup",
  "hooks": [ { "type": "command",
    "command": "pwsh -NoProfile -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/session-intent.ps1\"" } ] }
```

Zadání předepisuje `clear|startup|resume`. **Zúženo na `clear|startup`**, protože
jinak matcher nesleduje žádné souvislé kritérium: `resume` má tutéž vlastnost,
kvůli které je vyloučený `compact` — obnovené sezení si nese vlastní transkript,
tedy i baton, který si samo napsalo, a dostalo by zpátky vlastní instrukci
„vykonej tenhle plán".

Kritérium tedy zní **„start, který začíná s prázdným kontextem"**. `clear` a
`startup` ho splňují, `resume` a `compact` ne. Cena zúžení je nulová: kdo obnoví
sezení s čekajícím batonem, napíše `/clear` — dnešní chování. Stávající záznam
matcher nemá a střílí na každý zdroj startu; to je v pořádku, protože jen
připomíná kontrakt.

Přesný výčet zdrojů `SessionStart` v tomto harnessu se při implementaci ověří
proti dokumentaci a citace se zapíše vedle záznamu — playbook to u konfiguračního
klíče cizího nástroje bez citace v zadání žádá výslovně. **Sada dostane případ,
který matcher skutečně vykoná**; dnes ho žádný netestuje.

**3b. Uzavření asymetrie `SessionStart` × `PostCompact`.** `PostCompact` už
nakazuje po kompaktaci znovu přečíst ledger na
`.superpowers/sdd/<plan-basename>/progress.md`; `SessionStart` ne. Tato věta se
tam dopíše. Stojí na vlastních nohou i bez batonu: bez ní `/clear` uprostřed
plánu zahodí `Ruling:` řádky, odložené minory a zaparkované nálezy — informaci,
kterou by `/compact` zachoval, což je přesně obráceně.

**3c. Precondice u zapisovatelů — detekcí harnessu, ne existencí souboru.**
`settings.json` se na ne-Claude cíle nenasazuje, ale `mb-*` skilly a overlay
fragmenty ano, takže na Codexu, Gemini nebo Kilo Code by baton vznikl a nikdo by
ho nepřečetl.

Původní podoba precondice — „hook je registrovaný v `settings.json` a soubor
existuje" — **v tomto repozitáři neprojde**: kořenové `.claude/settings.json`
i `.claude/hooks/` leží v témže klonu bez ohledu na harness (Codex čte
`.agents/skills/`, ale nasazení `.claude/` je vedle něj), takže by se kontrola na
Codexu vyhodnotila kladně a baton by se napsal. Chybná byla i analogie
s `pre-push`: ta figura je **behaviorální sonda** spuštěná v prostředí tohoto
sezení, ne test existence souboru, a test existence nemá žádnou z jejích
rozlišovacích schopností.

Precondice tedy je: **neprázdný `CLAUDECODE`** (dokumentovaný marker Claude Code,
který `pre-push` hook už používá jako fallbackovou bránu) **a** existující
a registrovaný hook. Chybí-li kterákoli část, baton se **nepíše** a zapisovatel
ohlásí, že se záměr automaticky nedoručí a operátor ho napíše sám. Pravidlo má
domov v kontraktu (sekce 1), ne v obou fragmentech — implementují ho dva
konzumenti.

**3d. Matice harnessů.** Nový řádek do [`ums/README.md`](../../../ums/README.md),
sekce „Harness compatibility" — „Session intent baton delivery": Claude Code =
`SessionStart` hook `session-intent.ps1` s matcherem; ostatní harnessy = žádný
ekvivalent, zapisovatel proto handoff nenabídne a degraduje na to, že operátor
záměr napíše sám.

### 4. Invalidace v životním cyklu

**Rámování:** baton **není** pátá položka soupisu zbytků ve `mb-park`. Soupis
vypisuje práci, která se musí zachovat; baton je instrukce, která se musí
zneplatnit. Je to krok workflow, ne řádek reportu — v českém reportu se nikdy
neobjeví jako něco, co zůstává, protože nezůstává nic.

Operace i rámování mají **jeden domov v kontraktu** (podsekce
`### Session Intent Baton`). Každé místo nese jen jednu řádku — anglicky, protože
těla `mb-*` skillů jsou AI-facing instrukční text — odkazující na tu sekci, plus
to, co je čistě lokální. Čtyři místa:

| Místo | Kdy | Proč právě tady |
|---|---|---|
| `mb-harvest`, krok reset `context.md`, **podmíněno úspěchem** | dokončení pracovní položky | Harvest provádí `mb-harvest`, a ten se volá i **samostatně**, mimo finishing — overlay by tu cestu minul. Harvest navíc smí částečně selhat („on partial failure, leave `context.md` unchanged and report"); pak pracovní položka neskončila a baton má přežít. |
| [`mb-abort`](../../../ums/.claude/skills/mb-abort/SKILL.md), krok reset `context.md` | opuštění | Pracovní položka končí, `context.md` jde na IDLE; nevyřízený `plan-execution` baton je jednoznačně neplatný. |
| `finishing-a-development-branch.overlay.md`, discard cesta | opuštění přes finishing | Ta cesta abandon sekvenci **provádí sama**, nevolá `mb-abort`. Jediné ze čtyř míst, které vyžaduje revendor. |
| [`mb-park`](../../../ums/.claude/skills/mb-park/SKILL.md) — **dvě invokace** | odložení | Viz níže. |

**`mb-park`: invaliduje se tam, kde park dokončil, co dělá — ne tam, kde odmítl
jednat, a ne dřív, než je hotovo.** Výstupy skillu, ověřené čtením souboru:

- **„Není co parkovat" (IDLE, krok 0)** → invalidovat. Tohle je ta díra, kterou
  invalidace zavírá: slug guard pin-less `context.md` **propustí** (žádný názor),
  takže baton by na téhle větvi skutečně vystřelil, i když pracovní položka už
  skončila.
- **„Práce je už zaparkovaná"** (rozhodnuto v kroku 1, soupisu zbytků, ne
  v kroku 0) → invalidovat. Důvod parkování je nezměněný.
- **Park proběhl** → invalidovat, ale **až po úspěšné publikaci v kroku 4**, ne
  hned za STOPy kroku 0. Krok 4 nese vlastní fail-closed STOP na dosažitelnost
  („prázdný výsledek znamená, že park není publikovaný, takže tvrzení
  «obnovitelné z `origin`» je nepravdivé"). Kdyby invalidace ležela před ním,
  park, který na něm zemře, by už zničil platný baton — a playbook má na přesně
  tenhle tvar pravidlo: „v multi-step skillu vypiš všechny kroky, které mutují, a
  VYTÁHNI každý STOP PŘED první z nich."
- **STOP „chráněná větev"** a **STOP „detached HEAD"** (krok 0) →
  **neinvalidovat.** Věcně: park nejednal, plán na téhle větvi dál běží, takže
  baton je pořád platný a jeho zneplatnění by operátorovi vzalo funkční handoff.
  Mechanicky, silněji: report té cesty doslova tvrdí *„Nic jsem necommitnul, nic
  nepushnul a nic nezahodil."* Přejmenování je akce — invalidace tam by tu větu
  učinila nepravdivou.

IDLE výstup v kroku 0 předchází oba STOPy (ověřeno čtením), takže jedno umístění
tuhle podmínku vyjádřit nedokáže. Budou to dvě invokace v jednom skillu — jedna
na early-exit cestách, druhá za úspěšnou publikací. Není to zdvojené pravidlo (to
má domov v kontraktu), jsou to dva volací body; playbook takové uspořádání
**toleruje** — skill smí nést „per «jméno sekce»" plus pořadí vůči vlastním
krokům — byť ho nikde nedovoluje výslovně.

**Verifikace** u všech čtyř: s batonem na místě spustit skill a potvrdit
přejmenování na `.stale.md` a že ho ani report, ani žádná early-exit hláška
nejmenuje jako zbytek; bez batonu potvrdit chování beze změny; u chráněné větve a
u selhání kroku 4 potvrdit, že `session-intent.md` **zůstal**.

### 5. Pátá stop třída: rotace kontextu

Nový bullet do existujícího fragmentu
`subagent-driven-development.overlay.md` (kotva `ANCHOR: EOF`), hned za stávající
bullet „Rulings and STOPs". Do ASSERT sady se nic nepřidává: `Four things stop
you, and only these: an irreversible or destructive` tam už je a je to sémantická
kotva této změny.

**Fragment tu upstream větu jmenovitě neguje.** Vendorovaný soubor bude o pár set
řádků výš doslova říkat *„Four things stop you, **and only these**"* a dole ponese
bullet zavádějící pátou. Playbook to řeší pro tenhle přesný tvar: negovaný
upstream text zůstává viditelný vedle přebíjejícího, takže se musí jmenovitě
popřít — jinak vypadají obě verze platně. Návrh tohle pravidlo aplikoval na
`writing-plans` a tady ho původně vynechal; pořadí bulletů samo o sobě nestačí.

Obsah bulletu:

- Povoleno **jen na hranici tasku** — po zapsání dokončovací řádky do ledgeru a
  odškrtnutí toda, před dalším dispatchem. Nikde jinde. Uprostřed tasku je stav
  na disku nekompletní a rotace zahodí živý review cyklus.
- Na té hranici, jeví-li se zbývající kontext jako nedostatečný na další task:
  napsat baton (`Kind: plan-resume`, cesta plánu, cesta ledgeru, větev, slug,
  číslo dalšího nedokončeného tasku), ohlásit česky a zastavit s jedinou
  instrukcí — napsat `/clear`.
- Je to **úsudek, ne měření**; měřič operátora rozhoduje v **obou** směrech.
  Detektor prahu se nestaví ani nepředstírá.
- Precondice ze sekce 3c: bez detekovaného konzumenta se baton nepíše.
- Aditivní: čtyř existujících tříd se nedotýká a neoslabuje je.

Tři doplnění nad zadání:

1. **Je to handoff stop, ne eskalační.** Upstream čtyři třídy znamenají „zastav a
   **zeptej se**", tedy pokračování v tomtéž sezení po odpovědi. Rotace znamená
   „tohle sezení končí". Vrstva už jeden takový stop má — Architect Review Gate.
2. **Obnovené sezení nesmí znovu spustit base sync ani baseline.** Bullet
   „Base sync" říká „before dispatching the first task — a phase boundary".
   Čerstvé sezení, které si skill čte odshora, si „first task" snadno přečte jako
   první task **svého** sezení — a mergne bázi uprostřed fáze, což ten samý
   bullet zakazuje. `Next task: N` v batonu je rozlišující informace: povinná
   baseline a merge báze patří k tasku 1 **plánu**, ne k tasku 1 sezení.
3. **Ledger dostane řádek o rotaci** — ne `Ruling:` (není to rozhodnutí
   konfliktu), ale poznámku, že sezení bylo v tomto bodě rotováno. Bez ní se
   čerstvé sezení dívá na ledger, který prostě končí, a nemá jak odlišit rotaci
   od pádu.

### 6. Třetí volba exekuce ve `writing-plans`

Nový fragment `ums/.claude/skills/shared/overlays/writing-plans.overlay.md` — pro
tento skill dosud žádný neexistuje. (`writing-plans` je v seznamu skillů, který
revendor zpracovává, a jeho kontrola počtu aplikovaných bloků škáluje na čtyři
fragmenty — ověřeno.)

**Kotva:** `ANCHOR-BEFORE: **Which approach?"**`, ne
`**If Subagent-Driven chosen:**` ze zadání. Obě jsou v
[`skills/writing-plans/SKILL.md`](../../../skills/writing-plans/SKILL.md)
unikátní (ověřeno), ale druhá by vložila třetí volbu **za** otázku „Which
approach?".

**Přiznaný kompromis:** fragment má jedinou kotvu, takže obsahuje i obsluhu
volby 3, která tím pádem stojí **před** otázkou, kdežto obsluhy voleb 1 a 2 jsou
za ní. Ta asymetrie je vědomá a fragment ji pojmenuje: přednost má **menu
vyrenderované operátorovi** — to musí být v okamžiku otázky úplné. Druhá kotva by
prohodila obě vady, ne odstranila.

**ASSERT sada** — tři direktivy, každá matchne právě jeden řádek (ověřeno
strojově proti dnešnímu souboru; revendor porovnává přes `TrimEnd()` a vyžaduje
právě jeden zásah):

```
<!-- ASSERT: **"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:** -->
<!-- ASSERT: **1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration -->
<!-- ASSERT: **2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints -->
```

Přepis menu upstreamem tak shodí revendor hlasitě, místo aby nechal třetí volbu
viset u změněné dvojice. **První direktiva je zároveň věta, kterou tělo fragmentu
neguje** — je nepravdivá dvakrát: „Two" (budou tři) i cesta
`docs/superpowers/plans/<filename>.md` (UMS ukládá do
`<PLAN_MB>/proposals/active/plan_<slug>.md` a `docs/superpowers/plans/` je
blokovaná hookem). Obě poloviny se negují jmenovitě, v jednom odstavci. Cesta
není rozšíření rozsahu — je to tatáž věta, kterou je kvůli počtu nutné negovat
tak jako tak.

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
lepší informace než cokoli dostupného v době plánování. Případný strop patří do
souboru plánu, ne do batonu — baton se konzumuje jednou, strop platí pro celou
exekuci.

### 7. Sweepy: co tato práce činí nepravdivým

Čtyři nezávislé sweepy. Zadání nejmenuje ani jedno místo; první dva našla vlastní
kontrola, druhé dva agentická oponentura. Všechny výskyty jsou ověřené vlastním
během, ne převzaté.

**A. Počet stop tříd** (přidáním páté):

| Soubor | Text | Kdo opraví |
|---|---|---|
| kontrakt, „Fail-Closed Behavior", odstavec „Rulings and these STOPs" | *„stops only for four named classes … not a fifth class — they FALL WITHIN those four"* | implementace — zůstává pravdivé o fail-closed STOPech, ale vedle nich teď jedna pátá třída existuje |
| [`ums/CLAUDE.md.sample`](../../../ums/CLAUDE.md.sample) | *„STOP jen pro čtyři jmenované třídy"* | implementace |
| [`CLAUDE.md`](../../../CLAUDE.md) | tentýž text | implementace |
| SDD overlay, bullety „Rulings and STOPs" | *„fall within the four stop classes"* | neměnit — mluví o fail-closed STOPech a zůstává pravdivé |

**B. Počet overlay bloků** (přidáním čtvrtého fragmentu):

| Soubor | Text | Kdo opraví |
|---|---|---|
| `ums/.claude/skills/shared/SKILLS_MANIFEST.md` | *„UMS overlay bloky mají přesně 3: …"* | implementace |
| [`CLAUDE.md`](../../../CLAUDE.md) | *„Přesně 3 overlay bloky"* a *„tři overlay body zásahu UMS"* | implementace |
| [architecture.md](../../architecture.md) | *„vstupuje přesně třemi overlay bloky"* **i navazující Mermaid diagram bodů zásahu** | harvest |
| [architecture.md](../../architecture.md), „Dvouvrstvá mechanika vynucení" | *„a všechny tři overlay fragmenty"* — nový fragment sdílené skripty nekonzumuje, takže „všechny tři" je dvojznačné | harvest, přeformulovat na jmenný výčet |
| [tech.md](../../tech.md) | *„Overlay bloky \| přesně 3 (…)"* | harvest |
| [playbook.md](../../playbook.md) | *„tři vendorované skilly s overlay bloky"* a *„Tři upstream skilly s overlay bloky (…) se kopií nevyrobí"* | **implementace, přes konzultační bránu** — viz níže |

**C. Verze kontraktu** (bump 2.11 → 2.12) — sedm výskytů tokenu `2.11`:

| Soubor | Kdo opraví |
|---|---|
| [`ums/README.md`](../../../ums/README.md) (strom adresářů) | implementace |
| [brief.md](../../brief.md), dvakrát | harvest |
| [architecture.md](../../architecture.md), třikrát | harvest |
| [tech.md](../../tech.md), jednou | harvest |

**D. Inventury**, které nový hook, druhá registrace a nová sada činí neúplnými:

| Soubor | Text | Kdo opraví |
|---|---|---|
| [`ums/README.md`](../../../ums/README.md) | strom `hooks/` vyjmenovává soubory jménem; `session-intent.ps1` chybí | implementace |
| [tech.md](../../tech.md) | *„17 sad, dohromady 954 asercí"* → 18 sad, nový součet | harvest |
| [tech.md](../../tech.md) | řádek `hooks.SessionStart` popisuje jedinou registraci a její obsah | harvest |
| [tech.md](../../tech.md) | inventář PowerShellového nářadí; `session-intent.ps1` chybí | harvest |
| kontrakt, Language Contract | výčet tří anglických vývojářských skriptů; přibývá čtvrtý PowerShellový artefakt jiné třídy (sekce 1) | implementace |

**Rozdělení implementace × harvest** není formalita: MB dokumenty popisují
aktuální stav a jejich aktualizace je práce harvestu (current-state průchod plus
staleness sweep). Soubory **vrstvy** (`ums/`, `CLAUDE.md`, kontrakt) musí být
pravdivé v okamžiku, kdy změna vznikne — jsou to AI-facing instrukce.

**Výjimka: [playbook.md](../../playbook.md) opravuje implementace, ne harvest.**
Původní zdůvodnění „MB dokumenty patří harvestu" pro něj neplatí — kontrakt
`playbook.md` z automatického current-state průchodu výslovně **vyjímá**. A věcně
je to nutné: `playbook.md` je preskriptivní a jeho věta *„Tři upstream skilly
s overlay bloky (…) se kopií nevyrobí — po změně overlay fragmentu je musí
vygenerovat revendor"* **řídí poslední úlohu tohoto plánu**. Agent, který ji
vykoná podle neopravené věty, má jmenný seznam tří, který `writing-plans`
neobsahuje. Změna projde konzultační bránou (schválení uživatelem) — `mb-sync`
styl „navrhni v okamžiku nálezu" je legální stejně jako harvestová dávka.

## Odchylky od zadání a jejich důvody

| Odchylka | Důvod |
|---|---|
| Kotva `**Which approach?"**` místo `**If Subagent-Driven chosen:**` | Menu vyrenderované operátorovi musí být v okamžiku otázky úplné; obsluha volby 3 tím stojí před otázkou, což fragment přiznává. |
| ASSERT i na intro řádek menu; fragment neguje „Two" **i** cestu | Ta věta se stane nepravdivou; obě nepravdy jsou v jedné větě. |
| Matcher `clear\|startup` místo `clear\|startup\|resume` | `resume` má tutéž vlastnost jako vyloučený `compact`. Kritérium „start s prázdným kontextem" je souvislé; původní nebylo. |
| Precondice zapisovatele detekuje harness (`CLAUDECODE`), ne existenci souboru | Kořenové `.claude/` leží v témže klonu bez ohledu na harness, takže test existence projde i na Codexu. |
| `mb-harvest` místo finishing overlay jako místo invalidace při dokončení | Harvest se volá i samostatně; částečné selhání nesmí baton zneplatnit. |
| Čtvrté místo invalidace: discard cesta ve finishing overlay | Ta cesta abandon provádí sama, nevolá `mb-abort`. |
| `mb-park`: neinvalidovat na STOPech, a na úspěšné cestě až za publikací | Report STOPu tvrdí „nic jsem nezahodil"; a krok 4 má vlastní fail-closed STOP, za kterým park není hotov. |
| Invalidace není číslovaný krok | Vyhýbá se přidávání položky do dvou číslovaných seznamů a celé třídě rizika, na kterou playbook má vlastní pravidlo. |
| Uzavřený formát: neznámý klíč / nadměrná velikost = zvětralost, emise se re-renderuje | Obsah jde doslova do kontextu modelu; verbatim emise dovoluje únik z obalovací značky. |
| Validují se všechny čtyři povinné klíče a existence `Plan` | Zadání i původní návrh validovaly dva ze čtyř. |
| Case-sensitive porovnání větve a slugu | PowerShellové `-eq` je case-insensitive, git refy nejsou. |
| Slug guard zdůvodněný jinak než „IDLE je legitimní stav" | Původní důvod po zavedení invalidace skoro neplatí; chování zůstává. |
| Výjimka pro mlčenlivý pád hooku zapsaná do kontraktu | Kontrakt u chybějícího gitu předepisuje tvrdé zastavení; hook to porušuje z dobrého důvodu, který musí mít domov. |
| Precedence bootstrap kontroly nad batonem zapsaná do kontraktu | Dva `SessionStart` bloky si protiřečí a jejich pořadí není garantované. |
| Precondice zapisovatele má domov v kontraktu | Implementují ji dva konzumenti. |
| Čtyři sweepy (stop třídy, počet overlay bloků, verze kontraktu, inventury) | Zadání nejmenuje ani jedno místo. |
| `ums/CLAUDE.md.sample` a `CLAUDE.md` se editují oba ručně | Sync na kořen forku nemíří; jsou to dvě paralelní kopie se stejným markerovým tokenem, ale jiným popisem. |
| `playbook.md` opraví implementace, ne harvest | Kontrakt ho z current-state průchodu vyjímá a jeho věta řídí poslední úlohu tohoto plánu. |
| Revendor plným průchodem s pinovaným tagem, ne `-OverlaysOnly` | `-OverlaysOnly` funguje jen na pristine soubory; naměřeno v playbooku. |
| Obnovené sezení nesmí znovu spustit base sync / baseline | Jinak je rotace přímý spouštěč operace, kterou SDD overlay zakazuje. |
| Řádek o rotaci do ledgeru | Bez něj nelze odlišit rotaci od pádu sezení. |

## Dopady

Zdroj je vždy `ums/`; kořenové `.claude/` a `.agents/skills/` jsou netrackovaná
**nasazení**, která se obnovují poslední úlohou plánu.

**Nové soubory**

- `ums/.claude/hooks/session-intent.ps1`
- `ums/.claude/hooks/tests/session-intent.tests.ps1`
- `ums/.claude/skills/shared/overlays/writing-plans.overlay.md`

**Změněné soubory vrstvy** (implementace)

- `ums/.claude/skills/shared/UMS_MEMORY_BANK_CONTRACT.md` — podsekce
  `### Session Intent Baton`, výčet scratch tree ve Scope Locku, odstavec
  „Rulings and these STOPs", věta v Language Contractu, verze na 2.12
  s přeformulovaným „Supersedes"
- `ums/.claude/settings.json` — druhý `SessionStart` záznam, ledgerová věta ve
  stávajícím `additionalContext`
- `ums/.claude/skills/shared/overlays/subagent-driven-development.overlay.md` —
  bullet páté stop třídy včetně jmenovité negace „and only these"
- `ums/.claude/skills/shared/overlays/finishing-a-development-branch.overlay.md` —
  invalidace na discard cestě
- `ums/.claude/skills/mb-harvest/SKILL.md`, `mb-abort/SKILL.md`,
  `mb-park/SKILL.md` — invalidace
- `ums/.claude/skills/shared/SKILLS_MANIFEST.md` — **jen** oprava věty „přesně 3";
  per-fragmentová tabulka v tom souboru neexistuje, overlaye v něm nese jediný
  řádek odkazující na adresář
- `ums/CLAUDE.md.sample` a `CLAUDE.md` — počet stop tříd; v `CLAUDE.md` navíc
  počet overlay bloků
- `ums/README.md` — řádek v matici harnessů, `session-intent.ps1` ve stromu
  `hooks/`, verze kontraktu
- `memory-bank/playbook.md` — dvě věty o třech vendorovaných skillech, přes
  konzultační bránu
- `memory-bank/tasks.md` — dvě navazující položky

**Patří harvestu:** [brief.md](../../brief.md),
[architecture.md](../../architecture.md) a [tech.md](../../tech.md) — verze
kontraktu, počty overlay bloků, Mermaid diagram bodů zásahu, inventury sad, hooků
a PowerShellového nářadí, plus nová mechanika batonu. Adresný seznam je v sekci 7.

**Nasazení a regenerace** (poslední úloha plánu): obnovit `.claude/` a
`.agents/skills/` z `ums/.claude/`, pak plný revendor s `-Tag v6.3.0`, pak
dorovnat vendorované skilly do `.agents/skills`. `install-git-hooks.ps1` se
nespouští — git `pre-push` hook se tato práce nedotýká.

## Rizika

- **Zbytkové riziko injektáže.** Uzavřený formát a re-render zavírají únik
  z obalovací značky i neznámý obsah, ale hodnoty známých klíčů jdou do kontextu
  pořád — a zapsat je může cokoli s přístupem do pracovního stromu. Hranice je
  přiznaná, ne popřená: kdo umí zapsat baton, umí zapsat i plán, na který baton
  ukazuje. Ochrana je proto ve formátu a v guardech, ne v důvěře v obsah.
- **Dva konzumenti jednoho batonu.** Emise předchází přejmenování, takže dvě
  sezení nastartovaná v jednom workspace těsně po sobě dostanou týž baton obě.
  Mitigace je normou, ne mechanismem — kontrakt má „one session per workspace" a
  návrh se o ni opírá vědomě; zámkový soubor by to zavřel, ale za cenu dalšího
  stavu v adresáři, který má být jednorázový.
- **Replay v okně mezi emisí a přejmenováním** (sekce 2) — ohraničený guardy a
  věkovou instrukcí, doložený vlastním testovacím případem.
- **Baton vystřelí na správné větvi se zvětralým záměrem.** Branch guard, slug
  guard, existence plánu a invalidace ve čtyřech místech to zužují na scénář
  „napsat baton, nic neudělat, za tři dny otevřít sezení na téže větvi". Chytá to
  věková instrukce, ne tvrdá expirace — vědomě.
- **Kotva `**Which approach?"**` je jediné místo citlivé na drift upstreamu**
  v novém fragmentu; tři ASSERT direktivy shodí i přepis menu, který kotvu nechá
  na místě.
- **Precondice `CLAUDECODE` váže vrstvu na proměnnou jednoho harnessu.**
  Precedens existuje (`pre-push` ji už používá jako fallbackovou bránu), ale je to
  vazba, kterou je potřeba udržovat spolu s ním. Směr selhání je bezpečný — baton
  se nenapíše a operátor napíše záměr sám.
- **Pátá stop třída se dá zneužít jako výmluva.** Omezení na hranici tasku,
  povinný zápis batonu s číslem dalšího tasku a řádek v ledgeru dělají z rotace
  auditovatelnou událost, ne tiché ukončení.

## Verifikace

- Sada `session-intent.tests.ps1` zelená, se čtyřmi případy **označenými jako
  regresní zámky**, ne důkazy. Počty asercí získané spuštěním **celé** smyčky
  vrstvy po dávkách 1–4 souborů ve stejném sezení, delty rekonciliované proti
  předchozímu součtu, počet sad z `find ums -name "*.tests.ps1" | wc -l`.
  Po zásahu do sdíleného `_assert.ps1` se spustí i tři stávající sady v tom
  adresáři.
- Negativita každého guardu se třemi kategoriemi výsledků; u case-sensitivity je
  mutací záměna operátoru, ne odstranění guardu.
- Revendor: plný průchod s `-Tag v6.3.0` po obnovení nasazení, pak `-VerifyOnly`
  čistě; grep na charakteristickou frázi obou fragmentů ve vygenerovaných
  souborech, včetně case-insensitive dokontroly.
- End-to-end obou případů užití: brainstorm → plán → volba 3 → `/clear` →
  čerstvé sezení dispatchne první task bez dalšího vstupu; a rotační stop na
  hranici tasku → `/clear` → pokračování od dalšího nedokončeného tasku.
- Negativní případ: volba 3, **ne**clear, přepnutí na jinou tiketovou větev,
  start sezení → nic se neinjektuje a baton skončil jako `.stale.md`.
- Čtyři sweepy ze sekce 7 doložené greppem s nulovým zbytkem.

**Dvě kontroly Definition of Done jsou zelené už dnes** a jsou tedy regresní
zámky, ne důkaz — v reportu se tak oddělí: `git log --all -- '**/session-intent*.md'`
prázdný, a nulový výskyt rodičovského PID či `Stop-Process` ve skillech,
skriptech a `settings.json`.

## Pořadí úloh

**3b → 1 → 2 → 4 (invalidace) → 5 (stop třída) → 6 (třetí volba) → 7 (sweepy) →
nasazení.**

Task 3b jde první, protože je na batonu úplně nezávislý a stojí na vlastních
nohou. Invalidace musí ležet **před** třetí volbou — ta začne batony produkovat
právě ve fázi, kdy je přepnutí větve nejpravděpodobnější. Sweepy jdou až za
změnami, které je způsobují, ale **před** nasazením, aby poslední úloha četla
opravený `playbook.md`.

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
