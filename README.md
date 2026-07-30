# SCUM Mod Toolkit (SKit)

SKit är ett PowerShell-verktyg för Windows som installerar och samlar FModel,
repak och UAssetGUI bakom kommandot `skit`. Det innehåller även ett enkelt
projektflöde för att bygga, installera och testa SCUM-moddar.

## Krav

- Windows 11
- Windows PowerShell 5.1 eller senare
- Internetanslutning när verktyg installeras
- Aktuella .NET Desktop Runtime-versioner som krävs av FModel och UAssetGUI

SKit hämtar externa verktyg men installerar inte deras runtime-beroenden.

## Installation

Packa upp filerna och kör:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.ps1
.\SCUM-Mod-Toolkit.ps1 self-install
```

Använd endast `Unblock-File` efter att du har granskat och litar på scriptet.
Öppna en ny terminal och installera verktygen:

```powershell
skit tools
```

Om PowerShell blockerar scriptet eller inte hittar kommandot `skit`, se
[FAQ och felsökning](#faq-och-felsökning).

SKit installeras i:

```text
%LOCALAPPDATA%\Programs\SKit
```

Katalogen läggs i användarens `PATH`. Om SKit inte redan är installerat gör
även en direkt körning av `SCUM-Mod-Toolkit.ps1` en första självinstallation.
`self-install` kan köras igen för att uppdatera den installerade kopian.

Varje nedladdad releasefil verifieras mot SHA-256-värdet i GitHubs
release-metadata. Installationen avbryts om ett giltigt SHA-256-värde saknas
eller inte stämmer.

Låt SKit hitta SCUM automatiskt i Steams bibliotek:

```powershell
skit config detect-scum
```

Det går även att konfigurera installationskatalogen manuellt:

```powershell
skit config "D:\SteamLibrary\steamapps\common\SCUM"
```

Inställningen sparas i:

```text
%LOCALAPPDATA%\Programs\SKit\SKit.yaml
```

Äldre `skit.config.yml` läses fortfarande om `SKit.yaml` saknas.

Hämta den aktuella AES-nyckeln för SCUM:

```powershell
skit config find-key
```

SKit letar efter posten med namnet `SCUM` på källsidan, oberoende av dess
radnummer, validerar att värdet är en 256-bitars hexadecimal nyckel och sparar
det i `%LOCALAPPDATA%\Programs\SKit\SCUM-AES-Key.txt`.

## Filkommandon

```powershell
skit unpack ".\MyMod.pak"
skit unpack ".\MyMod.pak" ".\unpacked"

skit pack ".\MyMod" ".\MyMod.pak"

skit tojson ".\Asset.uasset"
skit fromjson ".\Asset.full.json"
```

`tojson` använder `VER_UE4_27` och skapar `Asset.full.json`. En annan
motorversion eller mappings-fil kan anges:

```powershell
skit tojson ".\Asset.uasset" VER_UE4_27 ".\Mappings.usmap"
skit fromjson ".\Asset.full.json" ".\Asset.uasset" ".\Mappings.usmap"
```

PAK-filer skapas med repaks PAK-version `V11`.

## Projekt

Skapa ett projekt i aktuell katalog:

```powershell
skit init
```

Det skapar `skit.yml`:

```yaml
name: 'MyMod'
version: 0.1.0.0
exclude: []
```

`name` och `version` är obligatoriska. `exclude` är valfri och kan vara `[]`
eller en indenterad lista:

```yaml
name: 'MyMod'
version: 0.1.0.0
exclude:
  - 'README.md'
  - 'docs/**'
  - '**/*.bak'
```

Mönstren är relativa projektroten. `*` matchar inom en sökvägsdel, `?`
matchar ett tecken och `**` matchar över kataloggränser.

Följande exkluderas alltid:

- `skit.yml`
- `.git/**`
- `build/**`

YAML-tolkningen är avsiktligt strikt. Endast `name`, `version` och `exclude`
accepteras. Tabbar, okända eller dubblerade nycklar och andra inline-listor än
`[]` avvisas.

## Projektkommandon

```powershell
skit build
skit bump
skit bump major
skit bump minor
skit bump patch
skit bump build
skit release
skit release major
skit install
skit test
skit play
skit play modded
skit play default
```

- `build` ökar build-numret och skapar `build\<name>-<version>.pak`.
- `bump` ökar minor som standard. `major`, `minor`, `patch` och `build` stöds.
- `release` gör först en build och därefter en minor-bump. `major` kan anges.
- `install` kopierar senaste bygget till `SCUM\Content\Paks\~mods`.
- `test` kör build och därefter install.
- `play` och `play modded` startar `SCUM.exe` med
  `-fileopenlog -nobattleye`.
- `play default` startar `SCUM.exe` utan dessa parametrar.

Exempel på det avsiktliga releaseflödet:

```text
Version före release:  0.1.0.3
PAK som skapas:        MyMod-0.1.0.4.pak
Version efter release: 0.2.0.0
```

`-nobattleye` ska endast användas för moddat spel där anti-cheat inte krävs.
Starta om spelet normalt innan du ansluter till servrar som använder BattlEye.

## Enskilda verktyg

```powershell
skit tools fmodel
skit tools repak
skit tools uassetgui
```

Efter installation kan `FModel`, `repak` och `UAssetGUI` startas direkt från
en ny terminal.

## Vidareutveckling

Läs dokumenten i denna ordning:

1. `AGENTS.md` – permanenta regler för Codex.
2. `DEVELOPMENT.md` – arkitektur, kontrakt och testmatris.
3. `CODEX-HANDOFF.md` – färdig instruktion för en ny Codex-session.
4. `CHANGELOG.md` – versionshistorik.

Tester körs med Pester 5:

```powershell
.\tests\Run-Tests.ps1
```

## FAQ och felsökning

### Scriptet är inte digitalt signerat

PowerShell kan visa följande fel:

```text
SCUM-Mod-Toolkit.ps1 cannot be loaded. The file is not digitally signed.
You cannot run this script on the current system.
```

Det händer vanligtvis när PowerShell använder `RemoteSigned` och Windows har
markerat filen som nedladdad från internet. Kontrollera aktuell policy med:

```powershell
Get-ExecutionPolicy -List
```

Efter att du har granskat och litar på scriptet är den rekommenderade
lösningen att ta bort internetmarkeringen från just den filen:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.ps1
.\SCUM-Mod-Toolkit.ps1 self-install
```

Om distributionen levereras som en ZIP-fil kan du i stället avblockera
ZIP-filen innan den packas upp:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.zip
```

Som tillfällig lösning kan policyn ändras endast för den aktuella
PowerShell-processen:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\SCUM-Mod-Toolkit.ps1 self-install
```

Det går även att starta en separat Windows PowerShell 5.1-process med en
engångspolicy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SCUM-Mod-Toolkit.ps1 self-install
```

Ändra inte `LocalMachine` eller `CurrentUser` till `Bypass` enbart för SKit.
En permanent lösning för bred distribution är att signera releases med ett
betrott kodsigneringscertifikat. Scriptet måste signeras på nytt efter varje
ändring.

### Kommandot `skit` hittas inte

Efter installation kan PowerShell visa:

```text
skit: The term 'skit' is not recognized as a name of a cmdlet, function,
script file, or executable program.
```

`self-install` lägger till `%LOCALAPPDATA%\Programs\SKit` i användarens
`PATH`, men en terminal som redan är öppen läser normalt inte in den nya
inställningen automatiskt. Rekommenderad lösning:

1. Stäng den aktuella terminalen.
2. Öppna en ny PowerShell-terminal.
3. Kontrollera installationen:

```powershell
skit version
```

För att uppdatera endast den aktuella terminalen utan omstart:

```powershell
$skitRoot = Join-Path $env:LOCALAPPDATA 'Programs\SKit'
if (($env:Path -split ';') -notcontains $skitRoot) {
    $env:Path += ";$skitRoot"
}
skit version
```

Kontrollera att installationen verkligen finns:

```powershell
Test-Path -LiteralPath "$env:LOCALAPPDATA\Programs\SKit\skit.cmd"
```

Om resultatet är `False`, kör installationen igen:

```powershell
.\SCUM-Mod-Toolkit.ps1 self-install
```

Meddelandet att kommandot finns i aktuell katalog betyder något annat:
PowerShell söker av säkerhetsskäl inte automatiskt efter kommandon i den
aktuella katalogen. Kör den lokala startfilen med en explicit relativ sökväg:

```powershell
.\skit.cmd version
```

Detta kör den lokala `skit.cmd`. Kommandot `skit version` utan `.\` använder
i stället den globalt installerade kopian som hittas via `PATH`.
