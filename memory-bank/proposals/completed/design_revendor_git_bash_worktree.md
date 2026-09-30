# Návrh: Revendor spouští funkční test `sdd-workspace` pod Git Bash

- **Jira:** (žádný tiket)
- **Target MB:** memory-bank/
- **Vytvořeno:** 2026-09-30
- **Cesta:** bounded

## Cíl

Nasazení vrstvy do pool slotu (linked worktree monorepa) musí projít
verifikací revendoru. Dnes spadne: funkční test `sdd-workspace` v `Invoke-Verify`
spouští `bash` z PATH, na Windows je to spouštěč WSL, a ten v linked worktree
nepřečte Windows cestu v souboru `.git` (`gitdir: D:/…/.git/worktrees/<slot>`)
→ `fatal: not a git repository`, exit 128.

Podnět (2026-09-30): první běh `sync-with-monorepo.ps1 -MonorepoRoot …\ums07`
skončil exit 1 na tomto testu; stejný `git rev-parse` pod Git Bash
(`C:\Program Files\Git\bin\bash.exe`) v tomtéž worktree prošel.

Kritérium úspěchu: verifikace revendoru projde v cíli, který je linked worktree;
na Windows bez Git Bash test ohlášeně přeskočí, nikdy tiše neprojde ani nespadne
na špatném interpretu.

## Scope

- V rozsahu: výběr interpretu pro funkční test `sdd-workspace`, testy.
- Mimo rozsah: jiná volání bashe ve vrstvě, dokumentace mimo Memory Bank.

## Technický návrh

- Nová funkce `Resolve-UmsGitBash` v `ums/.claude/scripts/revendor-superpowers.ps1`:
  na Windows najde Git Bash podle instalace gitu (`git.exe` → `<Git>\bin\bash.exe`,
  existující soubor), jinak vrátí `$null`; mimo Windows vrátí `bash` z PATH.
- Funkční test `sdd-workspace` v `Invoke-Verify` poběží pod ní; bez Git Bash na
  Windows se přeskočí s řádkem
  `SKIP: sdd-workspace functional test (Git Bash not found)`.
- Testy (TDD, `ums/.claude/scripts/tests/revendor.tests.ps1`): nasazení do cíle,
  který je linked worktree fixturního repa (RED na stroji s WSL bash na PATH);
  jednotkový test, že `Resolve-UmsGitBash` na Windows vrátí existující `bash.exe`.

## Ověřovací sada

```
pwsh -NoProfile -File ums/.claude/scripts/tests/revendor.tests.ps1
pwsh -NoProfile -File ums/tests/sync-vendor.tests.ps1
pwsh -NoProfile -File ums/tests/sync-fork.tests.ps1
```
