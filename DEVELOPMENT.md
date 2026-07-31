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
Install-SKit.ps1           Verified GitHub release bootstrap installer
Publish-SKitRelease.ps1    Builds and optionally publishes GitHub releases
skit.cmd                   Local launcher for the PowerShell script
README.md                  User guide
AGENTS.md                  Permanent Codex rules
DEVELOPMENT.md             Technical architecture and contracts
CHANGELOG.md               Version history
LICENSE                    MIT license for SKit
THIRD-PARTY-NOTICES.md     External tool licenses and distribution notices
tests/
  Run-Tests.ps1
  SCUM-Mod-Toolkit.Tests.ps1
```

The installed structure is:

```text
%LOCALAPPDATA%\Programs\SKit\
  skit.cmd
  SCUM-Mod-Toolkit.ps1
  SCUM-Mod-Toolkit.yaml
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

- If `SCUM-Mod-Toolkit.ps1` or `skit.cmd` is missing, SKit installs itself
  automatically.
- If both files exist, the installed copy is left unchanged.
- `setup self` explicitly runs `Install-Self` and updates the installed
  copy.
- `setup register-path` retries registration of the installation directory in
  the user `PATH` without requiring elevation. A registration failure is a
  warning and must not invalidate an otherwise successful installation.
- `setup uninstall` removes installed SKit scripts, command files, tool
  directories, and other SKit files while retaining YAML configuration files.
  `setup uninstall all` asks for Y/N confirmation before removing YAML files.
  It never removes external application configuration, including FModel
  settings outside the SKit installation directory.
- A successful setup self operation removes the obsolete installed
  `skit.ps1`.

All CLI-level errors are caught, written as `[SKit] ERROR: <message>`, and
return exit code `1`.

## Bootstrap installation

`Install-SKit.ps1` is the public bootstrap entry point for:

```powershell
irm https://raw.githubusercontent.com/mikaelleven/SCUM-Mod-Toolkit/master/Install-SKit.ps1 | iex
```

The repository is configured in `$script:SKitInstallerRepository`. Update
that value and the README URL together if the published GitHub owner,
repository name, or default branch changes.

The bootstrap installer retrieves `releases/latest` through the versioned
GitHub API `2026-03-10`. It accepts only a release asset named
`SCUM-Mod-Toolkit-<version>.zip`, matching the release tag without a leading
`v`, or the fallback name `SCUM-Mod-Toolkit.zip`. The asset must provide a
valid `sha256:<64 hexadecimal characters>` digest in GitHub release metadata.
The downloaded size is checked when present, and the local SHA-256 must match
before extraction.

The verified archive must contain exactly one `SCUM-Mod-Toolkit.ps1` plus
`LICENSE` and `THIRD-PARTY-NOTICES.md` beside it. The installer runs
`setup self` in Windows PowerShell with a one-time process-level execution
policy bypass, verifies the installed launcher with `skit version`, adds the
installation directory to the current process `PATH`, and removes its
validated temporary directory. It never changes the `CurrentUser` or
`LocalMachine` execution policy.
The child process output must not be treated as its exit code.

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
The local hash is calculated with
`System.Security.Cryptography.SHA256`; SKit does not depend on the optional
`Get-FileHash` cmdlet.

### Command contracts

SKit uses the following external arguments:

```text
repak [--aes-key <configured-key>] unpack --output <destination> <source.pak>
repak [--aes-key <configured-key>] pack --version V11 <source-directory> <destination.pak>

UAssetGUI tojson <source.uasset> <destination.full.json> VER_UE4_27 [mappings]
UAssetGUI fromjson <source.json> <destination.uasset> [mappings]
```

`Invoke-ExternalTool` pipes standard output to the host so Windows PowerShell
waits for GUI-subsystem executables such as UAssetGUI. It initializes and
captures `LASTEXITCODE`, and treats every exit code other than `0` as an error.
The repak AES option is global and must appear before the subcommand. SKit
adds it when `scumAesKey` is configured unless the SKit-only `-o` or
`-omit-key` flag is present. repak can read encrypted PAK files but does not
encrypt newly packed files.

Do not change these arguments without checking the current upstream code or
official documentation and updating the tests.

## Licensing and distribution

SKit source code is licensed under the MIT License. FModel, repak, and
UAssetGUI are separate programs downloaded from their upstream release
pages at the user's request. Their licenses do not replace the SKit license,
and SKit does not redistribute their binaries.

Every source or release archive must include `LICENSE` and
`THIRD-PARTY-NOTICES.md`. It must not include:

- FModel, repak, UAssetGUI, or other downloaded third-party binaries;
- SCUM game files or extracted assets;
- AES keys or configuration files containing keys;
- generated `.pak` files or local build output.

If third-party binaries are ever bundled, review and satisfy every upstream
license before publishing. FModel is GPL-licensed and requires particular
attention to corresponding-source, license, and notice obligations.

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

Global configuration is written to `SCUM-Mod-Toolkit.yaml`. During
self-installation, configuration is merged in this order:

1. `skit.config.yml`;
2. `SKit.yaml`;
3. `SCUM-Mod-Toolkit.yaml`.

Later files take precedence per key, including an explicitly empty value.
The merged result is written to `SCUM-Mod-Toolkit.yaml`; legacy files are
retained as migration backups. Allowed keys:

```yaml
scumPath: 'C:\path\to\SCUM'
scumExecutable: 'C:\path\to\SCUM\SCUM\Binaries\Win64\SCUM.exe'
scumAesKey: '0x0000000000000000000000000000000000000000000000000000000000000000'
scumStartParams: '-windowed'
```

`scumExecutable` is optional for older or manually created configurations.
When it is missing, the path is derived from `scumPath`.
`scumAesKey` must be empty or contain `0x` followed by exactly 64 hexadecimal
characters. SKit normalizes the prefix to lowercase `0x` and the hexadecimal
characters to uppercase because repak requires the lowercase prefix.
`scumStartParams` is an optional string passed to SCUM at launch.

`setup detect-path` locates Steam through the registry or default
installation, reads both older and newer
`steamapps\libraryfolders.vdf` formats, and searches each library for
`steamapps\common\SCUM\SCUM\Binaries\Win64\SCUM.exe`. The detected
installation root and executable path are written to
`SCUM-Mod-Toolkit.yaml`.

`setup open-config` creates `SCUM-Mod-Toolkit.yaml` through the normal
configuration merge when it is missing. It first asks Windows to open the
file through its YAML association and falls back to `notepad.exe` if that
fails.

`setup get-key` stores the downloaded key even when `scumPath` is empty. For
an existing FModel SCUM entry, SKit identifies the entry by its `GameName`
when a configured SCUM path is unavailable and updates only its AES key.

`setup help` is dispatched separately from the main help and lists only
setup commands. The former top-level `tools`, `self-install`, and `config`
forms are not accepted.

`setup register-path` uses the `User` environment-variable scope, so it does
not require administrator rights. A system `PATH` change is neither needed
nor attempted.

`setup uninstall` removes only validated paths below the SKit installation
directory. It removes the SKit user PATH entry when possible. The default
form retains root-level `.yaml` and `.yml` files; the `all` form prompts
before removing them.

`setup set-startparams <parameter-string>` stores the complete string as
`scumStartParams`. An explicitly empty string clears it. Both `play` modes
append the custom string. The `modded` mode first adds
`-fileopenlog -nobattleye`; the `default` mode does not.

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
- bootstrap release selection, SHA-256 verification, and current-session PATH
  refresh;
- version parsing and all bump rules;
- release order;
- strict YAML, required keys, and invalid constructs;
- updating the version without rewriting the rest of the project file;
- glob conversion and built-in protections;
- SHA-256 metadata;
- release asset selection;
- repak AES, omit-key, PAK version, and UAssetGUI arguments;
- staging with excluded files;
- Steam library detection and stored SCUM configuration;
- setup command dispatch and YAML editor fallback;
- AES key validation and YAML storage;
- default and custom arguments for modded and default launch modes.

A release must also be smoke-tested on Windows:

```powershell
.\SCUM-Mod-Toolkit.ps1 version
.\SCUM-Mod-Toolkit.ps1 help
.\SCUM-Mod-Toolkit.ps1 setup self
skit setup tools repak
skit setup tools uassetgui
```

Before a production release, also perform the following with real test
files:

1. Pack and unpack a small PAK.
2. Export a UE 4.27 `.uasset` to JSON.
3. Import the JSON and open the result.
4. Run `init`, `build`, `install`, `test`, `setup detect-path`,
   `setup open-config`, `setup set-startparams`, and both `play` modes
   against a test installation.

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
7. Create and inspect the ZIP with:

   ```powershell
   .\Publish-SKitRelease.ps1
   ```

   The archive root is `SCUM-Mod-Toolkit-<version>` and its allowlist is
   `SCUM-Mod-Toolkit.ps1`, `README.md`, `CHANGELOG.md`, `LICENSE`, and
   `THIRD-PARTY-NOTICES.md`. It must not include bootstrap, release, test, or
   other development files.
8. After committing the release changes, publish with:

   ```powershell
   .\Publish-SKitRelease.ps1 -Publish
   ```

   The script requires a clean Git working tree, creates and pushes tag
   `v<version>`, uploads `SCUM-Mod-Toolkit-<version>.zip`, and uses GitHub CLI
   generated release notes. Confirm that the GitHub release API reports its
   SHA-256 digest.
9. Inspect the ZIP and confirm that it includes `LICENSE` and
   `THIRD-PARTY-NOTICES.md` but no third-party binaries, game files, AES
   keys, configuration files, or generated mod content.
10. Run the published `irm ... | iex` command in a clean Windows PowerShell
    5.1 session.
11. Document what was verified and what still requires real-world testing.
