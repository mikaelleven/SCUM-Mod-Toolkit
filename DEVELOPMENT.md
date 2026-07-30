# Utveckling av SCUM Mod Toolkit

Detta dokument är den tekniska överlämningen för SKit. `README.md` beskriver
användningen och `AGENTS.md` innehåller permanenta regler för Codex.

## Mål och avgränsning

SKit ska vara ett litet, beroendefritt PowerShell-verktyg för Windows 11 och
Windows PowerShell 5.1. Det ska:

- installera sig självt och registrera kommandot `skit`;
- installera verifierade releaser av FModel, repak och UAssetGUI;
- ge enkla wrappers för PAK- och UAsset-kommandon;
- ge ett förutsägbart projektflöde med strikt, människoläsbar YAML.

SKit är inte en generell pakethanterare, YAML-implementation eller
versionshanterare.

## Filstruktur

```text
SCUM-Mod-Toolkit.ps1       Hela runtime-implementationen
skit.cmd                   Lokal startbrygga till PowerShell-scriptet
README.md                  Användarguide
AGENTS.md                  Permanenta Codex-regler
DEVELOPMENT.md             Teknisk arkitektur och kontrakt
CODEX-HANDOFF.md           Återanvändbar startinstruktion till Codex
CHANGELOG.md               Versionshistorik
tests/
  Run-Tests.ps1
  SCUM-Mod-Toolkit.Tests.ps1
```

Den installerade strukturen är:

```text
%LOCALAPPDATA%\Programs\SKit\
  skit.cmd
  skit.ps1
  SKit.yaml
  SCUM-AES-Key.txt
  FModel.cmd
  repak.cmd
  UAssetGUI.cmd
  tools\
    fmodel\
    repak\
    uassetgui\
```

## Körflöde

Scriptet kan användas på två sätt:

1. Normal exekvering: parametrar läses och `Invoke-SKitCommand` dispatchar
   kommandot.
2. Dot-sourcing: funktionerna laddas för Pester utan att installation,
   PATH-ändring eller kommandodispatch körs.

Vid normal exekvering körs `Ensure-SelfInstalled` före kommandot:

- Om `skit.ps1` eller `skit.cmd` saknas installeras SKit automatiskt.
- Om båda finns lämnas den installerade kopian orörd.
- `self-install` kör `Install-Self` explicit och uppdaterar kopian.

Alla fel på CLI-nivå fångas, skrivs som `[SKit] ERROR: <message>` och ger
exitkod `1`.

## Externa verktyg

| Verktyg | Repository | Exekverbar fil |
| --- | --- | --- |
| FModel | `4sval/FModel` | `FModel.exe` |
| repak | `trumank/repak` | `repak.exe` |
| UAssetGUI | `atenfyr/UAssetGUI` | `UAssetGUI.exe` |

Installation använder `releases/latest` via den versionssatta GitHub API:n
`2026-03-10`. `Select-ReleaseAsset` poängsätter Windows-tillgångar och
ignorerar checksummor, signaturer, symbolpaket och källkodspaket.

Säkerhetskontraktet är:

1. Den valda tillgången måste ha metadatafältet `digest`.
2. Värdet måste matcha `sha256:<64 hextecken>`.
3. Nedladdad storlek kontrolleras när GitHub anger en storlek.
4. Lokal SHA-256 måste matcha metadata.
5. Först därefter packas filen upp och byter plats med tidigare verktyg.

Det finns avsiktligt ingen fallback till en checksumma hämtad från brödtext,
HTML eller en separat, overifierad fil.

### Kommandokontrakt

SKit använder följande externa argument:

```text
repak unpack --output <destination> <source.pak>
repak pack --version V11 <source-directory> <destination.pak>

UAssetGUI tojson <source.uasset> <destination.full.json> VER_UE4_27 [mappings]
UAssetGUI fromjson <source.json> <destination.uasset> [mappings]
```

`Invoke-ExternalTool` betraktar alla exitkoder utom `0` som fel.

Ändra inte dessa argument utan att kontrollera aktuell upstream-kod eller
officiell dokumentation och uppdatera testerna.

## Projektfilen

Filnamnet är alltid `skit.yml`. SKit letar i aktuell katalog och därefter
uppåt genom föräldrakatalogerna.

Tillåtna toppnivånycklar:

| Nyckel | Krav | Typ |
| --- | --- | --- |
| `name` | Obligatorisk | Sträng och giltigt Windows-filnamn |
| `version` | Obligatorisk | `major.minor.patch.build` |
| `exclude` | Valfri | `[]` eller indenterad lista med strängar |

Parsern stöder kommentarer på egna rader, tomma rader, enkla citattecken,
dubbla citattecken och begränsade vanliga skalärer. Den avvisar:

- tabbar;
- okända och dubblerade nycklar;
- felaktig indentering;
- listposter utanför `exclude`;
- inline-listor andra än `[]`;
- reserverade YAML-tecken i ociterade skalärer.

Bakåtkompatibilitet för detta format ska bevaras. Om en ny nyckel läggs till
ska parser, serializer, dokumentation och tester uppdateras tillsammans.

Global konfiguration skrivs till `SKit.yaml`. En befintlig
`skit.config.yml` läses som bakåtkompatibel reserv om den nya filen saknas.
Tillåtna nycklar är:

```yaml
scumPath: 'C:\path\to\SCUM'
scumExecutable: 'C:\path\to\SCUM\SCUM\Binaries\Win64\SCUM.exe'
```

`scumExecutable` är valfri för äldre eller manuellt skapade konfigurationer.
När den saknas härleds den från `scumPath`.

`config detect-scum` hittar Steam via registret eller standardinstallationen,
läser både äldre och nyare format av `steamapps\libraryfolders.vdf` och söker
efter `steamapps\common\SCUM\SCUM\Binaries\Win64\SCUM.exe` i varje bibliotek.
Den upptäckta installationsroten och EXE-sökvägen skrivs till `SKit.yaml`.

`config find-key` hämtar den dokumenterade Games Translator-sidan, tar bort
HTML-markup och matchar posten `SCUM` följd av exakt `0x` och 64 hextecken.
Nyckeln sparas ensam i `SCUM-AES-Key.txt`. Ett nätverksfel eller en saknad
eller ogiltig nyckel är ett hårt fel.

## Exkluderingsmönster

Alla sökvägar normaliseras till `/` och jämförs relativt projektroten.

| Mönster | Betydelse |
| --- | --- |
| `*` | Noll eller flera tecken inom en sökvägsdel |
| `?` | Exakt ett tecken inom en sökvägsdel |
| `**` | Noll eller flera tecken, inklusive `/` |
| `**/` | Noll eller flera katalogsegment |
| avslutande `/` | Behandlas som `/**` |

Matchningen är skiftlägesokänslig i normal PowerShell-matchning på Windows.
Följande mönster läggs alltid till före projektspecifika mönster:

```text
skit.yml
.git/**
build/**
```

## Versionsregler

Versionen består av fyra icke-negativa heltal:

```text
major.minor.patch.build
```

| Kommando från `1.2.3.4` | Ny projektversion |
| --- | --- |
| `bump major` | `2.0.0.0` |
| `bump minor` | `1.3.0.0` |
| `bump patch` | `1.2.4.0` |
| `bump build` | `1.2.3.5` |
| `bump` | `1.3.0.0` |

`build`:

1. Läser aktuell version.
2. Beräknar nästa build-version.
3. Kopierar icke-exkluderade filer till en temporär stagingkatalog.
4. Kör repak mot en temporär PAK.
5. Flyttar lyckad PAK till `build\<name>-<version>.pak`.
6. Uppdaterar projektversionen och `build\latest.txt`.

Projektversionen ändras alltså först när repak har lyckats och PAK-filen har
flyttats till sin slutliga plats.

`release` är avsiktligt build-först:

```text
Före:              1.2.3.4
Skapad PAK:        1.2.3.5
Efter release:     1.3.0.0
```

`release major` ger i samma exempel projektversion `2.0.0.0`. Endast `minor`
och `major` är giltiga release-argument.

`test` kör `build` och sedan `install`. Om installationen misslyckas efter
ett lyckat bygge behålls det nya bygget och den ökade build-versionen.

## Installation av ett projektbygge

`Get-LatestProjectBuild` använder först `build\latest.txt`. Om den pekar på
en saknad fil används den senast modifierade `.pak`-filen i buildkatalogen.

`install`:

- hittar SCUMs `Content\Paks`;
- skapar `~mods` vid behov;
- tar bort det tidigare SKit-installerade bygget för samma projekt när
  filnamnet har ändrats;
- kopierar senaste bygge;
- sparar filnamnet i `build\installed.txt`.

Raderingen begränsas till ett validerat `.pak`-filnamn i den konfigurerade
`~mods`-katalogen.

## Teststrategi

Testerna använder Pester 5 och ska köras i Windows PowerShell 5.1:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
.\tests\Run-Tests.ps1
```

Testsviten täcker:

- PowerShell-parserfel;
- versionsparsning och samtliga bump-regler;
- releaseordning;
- strikt YAML, obligatoriska nycklar och ogiltiga konstruktioner;
- uppdatering av version utan att skriva om övrig projektfil;
- glob-konvertering och standardskydd;
- SHA-256-metadata;
- val av release-tillgång;
- argument till repak och UAssetGUI;
- staging med exkluderade filer;
- Steam-biblioteksdetektering och sparad SCUM-konfiguration;
- innehållsbaserad AES-nyckelmatchning och lagring;
- argumenten för moddat respektive vanligt spelläge.

En release ska dessutom smoke-testas på Windows:

```powershell
.\SCUM-Mod-Toolkit.ps1 version
.\SCUM-Mod-Toolkit.ps1 help
.\SCUM-Mod-Toolkit.ps1 self-install
skit tools repak
skit tools uassetgui
```

Före en skarp release bör även följande göras med riktiga testfiler:

1. Packa och packa upp en liten PAK.
2. Exportera en UE 4.27 `.uasset` till JSON.
3. Importera JSON tillbaka och öppna resultatet.
4. Köra `init`, `build`, `install`, `test`, `config detect-scum`,
   `config find-key` och båda `play`-lägena mot en testinstallation.

## Kända begränsningar

- Endast Windows stöds.
- Verktygsval bygger på releasefilernas namn och kan behöva uppdateras om
  upstream byter namnkonvention.
- Installation stoppas om GitHub-releasen saknar `digest`.
- SKit installerar inte .NET Desktop Runtime.
- Det finns inget uninstall-kommando.
- Automatiska tester mockar externa program och ersätter inte ett riktigt
  SCUM-test.

## Checklista för en SKit-release

1. Implementera ändringen och testerna.
2. Kör Pester i Windows PowerShell 5.1.
3. Kör relevanta smoke- och end-to-end-tester.
4. Uppdatera `README.md`, `DEVELOPMENT.md` och `CHANGELOG.md`.
5. Öka `$script:SKitVersion` enligt SemVer för själva verktyget.
6. Kontrollera att `skit version` visar samma version.
7. Skapa ZIP med rotkatalogen `SCUM-Mod-Toolkit-<version>`.
8. Dokumentera verifierade och ej verifierade delar i leveransen.
