# SCUM Mod Toolkit (SKit)

SKit is a PowerShell tool for Windows that installs and provides FModel,
repak, and UAssetGUI through the `skit` command. It also includes a simple
project workflow for building, installing, and testing SCUM mods.

## Requirements

- Windows 11
- Windows PowerShell 5.1 or later
- An internet connection when installing tools
- The current .NET Desktop Runtime versions required by FModel and UAssetGUI

SKit downloads external tools but does not install their runtime dependencies.

## Installation

Extract the files and run:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.ps1
.\SCUM-Mod-Toolkit.ps1 setup self
```

Only use `Unblock-File` after reviewing and trusting the script. Open a new
terminal and install the tools:

```powershell
skit setup tools
```

If PowerShell blocks the script or cannot find the `skit` command, see
[FAQ and troubleshooting](#faq-and-troubleshooting).

SKit is installed in:

```text
%LOCALAPPDATA%\Programs\SKit
```

The directory is added to the user `PATH`. If SKit is not already installed,
running `SCUM-Mod-Toolkit.ps1` directly also performs an initial
self-installation. Run `skit setup self` again to update the installed copy.
The installed script keeps the name `SCUM-Mod-Toolkit.ps1`, and `skit.cmd`
launches that file.

Every downloaded release asset is verified against the SHA-256 value in the
GitHub release metadata. Installation stops if a valid SHA-256 value is
missing or does not match.

Let SKit detect SCUM automatically in the configured Steam libraries:

```powershell
skit setup detect-path
```

The installation directory can also be configured manually:

```powershell
skit setup set-path "D:\SteamLibrary\steamapps\common\SCUM"
```

The setting is stored in:

```text
%LOCALAPPDATA%\Programs\SKit\SCUM-Mod-Toolkit.yaml
```

During installation, values from legacy `skit.config.yml` and `SKit.yaml`
files are merged into `SCUM-Mod-Toolkit.yaml`. Values in `SKit.yaml` take
precedence over `skit.config.yml`, and values already present in
`SCUM-Mod-Toolkit.yaml` take final precedence. The legacy files are retained
as migration backups.

Download the current AES key for SCUM:

```powershell
skit setup find-key
```

SKit locates the entry named `SCUM` on the source page regardless of its line
number, validates that the value is a 256-bit hexadecimal key, and stores it
as `SCUM-AES-Key.txt` in the current directory.

To store the key directly in `SCUM-Mod-Toolkit.yaml`, use:

```powershell
skit setup get-key
```

If FModel has been started before and already has a SCUM game entry, SKit
also updates the main AES key in FModel. Close FModel before running the
command. SKit creates `AppSettings.json.skit-backup` before the first update.
If FModel is unavailable or has no SCUM entry, the key is still stored in
the SKit configuration.

Open the global YAML configuration in the default associated editor:

```powershell
skit setup open-config
```

SKit creates the configuration first when it does not exist. If Windows
cannot open the configured YAML editor, SKit falls back to Notepad.

Show all setup commands:

```powershell
skit setup help
```

Custom SCUM launch parameters can be configured from the CLI:

```powershell
skit setup set-startparams "-windowed -ResX=1920 -ResY=1080"
```

Clear them by passing an empty string:

```powershell
skit setup set-startparams ""
```

The same values can be edited manually in
`%LOCALAPPDATA%\Programs\SKit\SCUM-Mod-Toolkit.yaml`:

```yaml
scumPath: 'D:\SteamLibrary\steamapps\common\SCUM'
scumExecutable: 'D:\SteamLibrary\steamapps\common\SCUM\SCUM\Binaries\Win64\SCUM.exe'
scumAesKey: '0x0B1F4E543FB798EFC5BD861BB405BE7081CD03698EA9BA06469462A3B113CA81'
scumStartParams: '-windowed -ResX=1920 -ResY=1080'
```

## File commands

```powershell
skit unpack ".\MyMod.pak"
skit unpack ".\MyMod.pak" ".\unpacked"

skit pack ".\MyMod" ".\MyMod.pak"

skit tojson ".\Asset.uasset"
skit fromjson ".\Asset.full.json"
```

`tojson` uses `VER_UE4_27` and creates `Asset.full.json`. A different engine
version or mappings file can be specified:

```powershell
skit tojson ".\Asset.uasset" VER_UE4_27 ".\Mappings.usmap"
skit fromjson ".\Asset.full.json" ".\Asset.uasset" ".\Mappings.usmap"
```

PAK files are created with repak PAK version `V11`.

## Projects

Create a project in the current directory:

```powershell
skit init
```

This creates `skit.yml`:

```yaml
name: 'MyMod'
version: 0.1.0.0
exclude: []
```

`name` and `version` are required. `exclude` is optional and can be `[]` or
an indented list:

```yaml
name: 'MyMod'
version: 0.1.0.0
exclude:
  - 'README.md'
  - 'docs/**'
  - '**/*.bak'
```

Patterns are relative to the project root. `*` matches within one path
segment, `?` matches one character, and `**` matches across directory
boundaries.

The following paths are always excluded:

- `skit.yml`
- `.git/**`
- `build/**`

YAML parsing is intentionally strict. Only `name`, `version`, and `exclude`
are accepted. Tabs, unknown or duplicate keys, and inline lists other than
`[]` are rejected.

## Project commands

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

- `build` increments the build number and creates
  `build\<name>-<version>.pak`.
- `bump` increments the minor version by default. `major`, `minor`, `patch`,
  and `build` are supported.
- `release` performs a build and then a minor bump. `major` can be specified.
- `install` copies the latest build to `SCUM\Content\Paks\~mods`.
- `test` runs build and then install.
- `play` and `play modded` start `SCUM.exe` with
  `-fileopenlog -nobattleye`.
- `play default` starts `SCUM.exe` without those arguments.
- Custom parameters from `scumStartParams` are added in both launch modes.

Example of the intentional release flow:

```text
Version before release:  0.1.0.3
PAK created:             MyMod-0.1.0.4.pak
Version after release:   0.2.0.0
```

Only use `-nobattleye` for modded gameplay where anti-cheat is not required.
Restart the game normally before joining servers that use BattlEye.

## Individual tools

```powershell
skit setup tools fmodel
skit setup tools repak
skit setup tools uassetgui
```

After installation, `FModel`, `repak`, and `UAssetGUI` can be started
directly from a new terminal.

## Development

Read the documents in this order:

1. `AGENTS.md` - permanent Codex rules.
2. `DEVELOPMENT.md` - architecture, contracts, and test matrix.
3. `CODEX-HANDOFF.md` - reusable instructions for a new Codex session.
4. `CHANGELOG.md` - version history.

Run tests with Pester 5:

```powershell
.\tests\Run-Tests.ps1
```

## FAQ and troubleshooting

### The script is not digitally signed

PowerShell may display the following error:

```text
SCUM-Mod-Toolkit.ps1 cannot be loaded. The file is not digitally signed.
You cannot run this script on the current system.
```

This commonly happens when PowerShell uses `RemoteSigned` and Windows has
marked the file as downloaded from the internet. Check the current policy:

```powershell
Get-ExecutionPolicy -List
```

After reviewing and trusting the script, the recommended solution is to
remove the internet mark from that specific file:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.ps1
.\SCUM-Mod-Toolkit.ps1 setup self
```

If the distribution is delivered as a ZIP file, unblock the ZIP file before
extracting it:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.zip
```

As a temporary workaround, change the policy for the current PowerShell
process only:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\SCUM-Mod-Toolkit.ps1 setup self
```

You can also start a separate Windows PowerShell 5.1 process with a one-time
policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SCUM-Mod-Toolkit.ps1 setup self
```

Do not change `LocalMachine` or `CurrentUser` to `Bypass` solely for SKit. A
permanent solution for broad distribution is to sign releases with a trusted
code-signing certificate. The script must be signed again after every change.

### The `skit` command is not found

After installation, PowerShell may display:

```text
skit: The term 'skit' is not recognized as a name of a cmdlet, function,
script file, or executable program.
```

`skit setup self` adds `%LOCALAPPDATA%\Programs\SKit` to the user `PATH`, but an
already open terminal normally does not load the updated setting
automatically. The recommended solution is:

1. Close the current terminal.
2. Open a new PowerShell terminal.
3. Verify the installation:

```powershell
skit version
```

To update only the current terminal without restarting it:

```powershell
$skitRoot = Join-Path $env:LOCALAPPDATA 'Programs\SKit'
if (($env:Path -split ';') -notcontains $skitRoot) {
    $env:Path += ";$skitRoot"
}
skit version
```

Check that the installation exists:

```powershell
Test-Path -LiteralPath "$env:LOCALAPPDATA\Programs\SKit\skit.cmd"
```

If the result is `False`, run the installation again:

```powershell
.\SCUM-Mod-Toolkit.ps1 setup self
```

The message that the command exists in the current directory describes a
different issue. For security reasons, PowerShell does not search the current
directory for commands automatically. Run the local launcher with an explicit
relative path:

```powershell
.\skit.cmd version
```

This runs the local `skit.cmd`. The `skit version` command without `.\` uses
the globally installed copy found through `PATH`.
