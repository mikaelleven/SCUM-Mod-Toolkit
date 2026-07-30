# Developing SCUM Mod Toolkit

This document is the technical handoff for SKit. `README.md` describes usage,
and `AGENTS.md` contains permanent Codex rules.

## Goals and scope

SKit must remain a small, dependency-free PowerShell tool for Windows 11 and
Windows PowerShell 5.1. It must:

- install itself and register the `skit` command;
- install verified releases of FModel, repak, and UAssetGUI;
- provide simple wrappers for PAK and UAsset commands;
- provide a predictable project workflow with strict, human-readable YAML.

SKit is not a general package manager, YAML implementation, or version
manager.

## File structure

```text
SCUM-Mod-Toolkit.ps1       Complete runtime implementation
skit.cmd                   Local launcher for the PowerShell script
README.md                  User guide
AGENTS.md                  Permanent Codex rules
DEVELOPMENT.md             Technical architecture and contracts
CODEX-HANDOFF.md           Reusable Codex handoff instructions
CHANGELOG.md               Version history
tests/
  Run-Tests.ps1
  SCUM-Mod-Toolkit.Tests.ps1
```

The installed structure is:

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

## Execution flow

The script can be used in two ways:

1. Normal execution: parameters are read and `Invoke-SKitCommand` dispatches
   the command.
2. Dot-sourcing: functions are loaded for Pester without performing
   installation, changing `PATH`, or dispatching a command.

During normal execution, `Ensure-SelfInstalled` runs before the command:

- If `skit.ps1` or `skit.cmd` is missing, SKit installs itself automatically.
- If both files exist, the installed copy is left unchanged.
- `self-install` explicitly runs `Install-Self` and updates the installed
  copy.

All CLI-level errors are caught, written as `[SKit] ERROR: <message>`, and
return exit code `1`.

## External tools

| Tool | Repository | Executable |
| --- | --- | --- |
| FModel | `4sval/FModel` | `FModel.exe` |
| repak | `trumank/repak` | `repak.exe` |
| UAssetGUI | `atenfyr/UAssetGUI` | `UAssetGUI.exe` |

Installation uses `releases/latest` through the versioned GitHub API
`2026-03-10`. `Select-ReleaseAsset` scores Windows assets and ignores
checksums, signatures, symbol packages, and source packages.

The security contract is:

1. The selected asset must have a `digest` metadata field.
2. The value must match `sha256:<64 hexadecimal characters>`.
3. The downloaded size is checked when GitHub provides a size.
4. The local SHA-256 must match the metadata.
5. Only then is the file extracted and swapped with the previous tool.

There is intentionally no fallback to a checksum obtained from release body
text, HTML, or a separate unverified file.

### Command contracts

SKit uses the following external arguments:

```text
repak unpack --output <destination> <source.pak>
repak pack --version V11 <source-directory> <destination.pak>

UAssetGUI tojson <source.uasset> <destination.full.json> VER_UE4_27 [mappings]
UAssetGUI fromjson <source.json> <destination.uasset> [mappings]
```

`Invoke-ExternalTool` treats every exit code other than `0` as an error.

Do not change these arguments without checking the current upstream code or
official documentation and updating the tests.

## Project file

The filename is always `skit.yml`. SKit searches the current directory and
then each parent directory.

Allowed top-level keys:

| Key | Requirement | Type |
| --- | --- | --- |
| `name` | Required | String and valid Windows filename |
| `version` | Required | `major.minor.patch.build` |
| `exclude` | Optional | `[]` or an indented string list |

The parser supports comments on separate lines, blank lines, single quotes,
double quotes, and restricted plain scalars. It rejects:

- tabs;
- unknown and duplicate keys;
- invalid indentation;
- list items outside `exclude`;
- inline lists other than `[]`;
- reserved YAML characters in unquoted scalars.

Backward compatibility for this format must be preserved. When adding a new
key, update the parser, serializer, documentation, and tests together.

Global configuration is written to `SKit.yaml`. An existing
`skit.config.yml` is read as a backward-compatible fallback when the new file
does not exist. Allowed keys:

```yaml
scumPath: 'C:\path\to\SCUM'
scumExecutable: 'C:\path\to\SCUM\SCUM\Binaries\Win64\SCUM.exe'
```

`scumExecutable` is optional for older or manually created configurations.
When it is missing, the path is derived from `scumPath`.

`config detect-scum` locates Steam through the registry or default
installation, reads both older and newer
`steamapps\libraryfolders.vdf` formats, and searches each library for
`steamapps\common\SCUM\SCUM\Binaries\Win64\SCUM.exe`. The detected
installation root and executable path are written to `SKit.yaml`.

`config find-key` downloads the documented Games Translator page, removes
HTML markup, and matches the `SCUM` entry followed by exactly `0x` and 64
hexadecimal characters. The key is stored by itself in `SCUM-AES-Key.txt`.
A network failure or a missing or invalid key is a hard error.

## Exclusion patterns

All paths are normalized to `/` and compared relative to the project root.

| Pattern | Meaning |
| --- | --- |
| `*` | Zero or more characters within one path segment |
| `?` | Exactly one character within one path segment |
| `**` | Zero or more characters, including `/` |
| `**/` | Zero or more directory segments |
| trailing `/` | Treated as `/**` |

Matching is case-insensitive under normal PowerShell behavior on Windows.
The following patterns are added before project-specific patterns:

```text
skit.yml
.git/**
build/**
```

## Version rules

The version consists of four non-negative integers:

```text
major.minor.patch.build
```

| Command from `1.2.3.4` | New project version |
| --- | --- |
| `bump major` | `2.0.0.0` |
| `bump minor` | `1.3.0.0` |
| `bump patch` | `1.2.4.0` |
| `bump build` | `1.2.3.5` |
| `bump` | `1.3.0.0` |

`build`:

1. Reads the current version.
2. Calculates the next build version.
3. Copies non-excluded files to a temporary staging directory.
4. Runs repak against a temporary PAK.
5. Moves the successful PAK to `build\<name>-<version>.pak`.
6. Updates the project version and `build\latest.txt`.

The project version changes only after repak succeeds and the PAK file has
been moved to its final path.

`release` intentionally builds first:

```text
Before:             1.2.3.4
Created PAK:        1.2.3.5
After release:      1.3.0.0
```

In the same example, `release major` changes the project version to
`2.0.0.0`. Only `minor` and `major` are valid release arguments.

`test` runs `build` and then `install`. If installation fails after a
successful build, the new build and incremented build version are retained.

## Installing a project build

`Get-LatestProjectBuild` first uses `build\latest.txt`. If it points to a
missing file, the most recently modified `.pak` file in the build directory
is used.

`install`:

- locates the SCUM `Content\Paks` directory;
- creates `~mods` when necessary;
- removes the previous SKit-installed build for the same project when the
  filename has changed;
- copies the latest build;
- stores the filename in `build\installed.txt`.

Deletion is restricted to a validated `.pak` filename inside the configured
`~mods` directory.

## Test strategy

The tests use Pester 5 and must run in Windows PowerShell 5.1:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
.\tests\Run-Tests.ps1
```

The test suite covers:

- PowerShell parser errors;
- version parsing and all bump rules;
- release order;
- strict YAML, required keys, and invalid constructs;
- updating the version without rewriting the rest of the project file;
- glob conversion and built-in protections;
- SHA-256 metadata;
- release asset selection;
- repak and UAssetGUI arguments;
- staging with excluded files;
- Steam library detection and stored SCUM configuration;
- content-based AES key matching and storage;
- arguments for modded and default launch modes.

A release must also be smoke-tested on Windows:

```powershell
.\SCUM-Mod-Toolkit.ps1 version
.\SCUM-Mod-Toolkit.ps1 help
.\SCUM-Mod-Toolkit.ps1 self-install
skit tools repak
skit tools uassetgui
```

Before a production release, also perform the following with real test
files:

1. Pack and unpack a small PAK.
2. Export a UE 4.27 `.uasset` to JSON.
3. Import the JSON and open the result.
4. Run `init`, `build`, `install`, `test`, `config detect-scum`,
   `config find-key`, and both `play` modes against a test installation.

## Known limitations

- Only Windows is supported.
- Tool selection relies on release asset naming and may need updates when
  upstream naming conventions change.
- Installation stops when a GitHub release does not provide a `digest`.
- SKit does not install .NET Desktop Runtime.
- There is no uninstall command.
- Automated tests mock external programs and do not replace a real SCUM
  test.

## SKit release checklist

1. Implement the change and tests.
2. Run Pester in Windows PowerShell 5.1.
3. Run relevant smoke and end-to-end tests.
4. Update `README.md`, `DEVELOPMENT.md`, and `CHANGELOG.md`.
5. Increment `$script:SKitVersion` according to SemVer for the tool itself.
6. Confirm that `skit version` displays the same version.
7. Create a ZIP with root directory `SCUM-Mod-Toolkit-<version>`.
8. Document what was verified and what still requires real-world testing.
