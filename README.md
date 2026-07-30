# SCUM Mod Toolkit (SKit)

SKit is a PowerShell tool for Windows that installs and provides FModel,
repak, and UAssetGUI through the `skit` command. It also includes a simple
project workflow for building, installing, and testing SCUM mods.

## Requirements

- Windows 10+
- Windows PowerShell 5.1 or later
- An internet connection when installing tools
- The current .NET Desktop Runtime versions required by FModel and UAssetGUI

SKit downloads external tools but does not install their runtime dependencies.

## Installation

The recommended installation method is the PowerShell bootstrap script:

```powershell
irm https://raw.githubusercontent.com/w33zl/SCUM-Mod-Toolkit/master/Install-SKit.ps1 | iex
```

Review `Install-SKit.ps1` before running the command. The bootstrap installer
downloads the latest published SKit release, requires a valid SHA-256 digest
from GitHub release metadata, verifies the downloaded archive, and installs
SKit below `%LOCALAPPDATA%\Programs\SKit`. It uses an execution-policy bypass
only for the current installer processes and does not permanently weaken the
user or machine policy.

The latest GitHub release must contain either
`SCUM-Mod-Toolkit-<version>.zip`, matching its release tag, or
`SCUM-Mod-Toolkit.zip`. The release asset must include GitHub's
`sha256:<64 hex characters>` digest metadata.

After installation, the bootstrap script verifies `skit version` and reloads
the SKit directory into `PATH` for the current PowerShell session. If the
command is still unavailable because of a system-managed policy or
environment restriction, open a new PowerShell terminal and run:

```powershell
skit version
```

The command should print the installed four-part SKit version.

For a manual installation, extract the release files and run:

```powershell
Unblock-File -LiteralPath .\SCUM-Mod-Toolkit.ps1
.\SCUM-Mod-Toolkit.ps1 setup self
```

Only use `Unblock-File` after reviewing and trusting the script. Open a new terminal and install the tools:

```powershell
skit setup tools
```

If PowerShell blocks the script or cannot find the `skit` command, see [FAQ and troubleshooting](#faq-and-troubleshooting).

SKit is installed in:

```text
%LOCALAPPDATA%\Programs\SKit
```

The directory is added to the user `PATH`. If SKit is not already installed, running `SCUM-Mod-Toolkit.ps1` directly also performs an initial
self-installation. Run `skit setup self` again to update the installed copy. The installed script keeps the name `SCUM-Mod-Toolkit.ps1`, and `skit.cmd`
launches that file.

Every downloaded release asset is verified against the SHA-256 value in the GitHub release metadata. Installation stops if a valid SHA-256 value is
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

SCUM's original game archives require a SCUM-specific 256-bit AES key. You
must locate that key yourself and enter it as `scumAesKey` in the global
configuration. SKit expects `0x` followed by 64 hexadecimal characters and
normalizes the value before passing it to repak. SKit does not provide or
document where to obtain it.

Open the global YAML configuration in the default associated editor:

```powershell
skit setup open-config
```

SKit creates the configuration first when it does not exist. If Windows cannot open the configured YAML editor, SKit falls back to Notepad.

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
scumAesKey: ''
scumStartParams: '-windowed -ResX=1920 -ResY=1080'
```

## File commands

```powershell
skit unpack ".\MyMod.pak"
skit unpack ".\MyMod.pak" ".\unpacked"
skit unpack -omit-key ".\MyMod.pak"

skit pack ".\MyMod" ".\MyMod.pak"
skit pack ".\MyMod" ".\MyMod.pak" -omit-key

skit tojson ".\Asset.uasset"
skit fromjson ".\Asset.full.json"
```

When `scumAesKey` is configured, `pack` and `unpack` pass it to repak
automatically. Use `-o` or `-omit-key` anywhere in either command to run
repak without the configured key.

`tojson` waits for UAssetGUI to finish, uses `VER_UE4_27`, and creates
`Asset.full.json`. A different engine version or mappings file can be specified:

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

`name` and `version` are required. `exclude` is optional and can be `[]` or an indented list:

```yaml
name: 'MyMod'
version: 0.1.0.0
exclude:
  - 'README.md'
  - 'docs/**'
  - '**/*.bak'
```

Patterns are relative to the project root. `*` matches within one path segment, `?` matches one character, and `**` matches across directory boundaries.

The following paths are always excluded:

- `skit.yml`
- `.git/**`
- `build/**`

YAML parsing is intentionally strict. Only `name`, `version`, and `exclude` are accepted. Tabs, unknown or duplicate keys, and inline lists other than
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

Only use `-nobattleye` for modded gameplay where anti-cheat is not required. Restart the game normally before joining servers that use BattlEye.

## Individual tools

```powershell
skit setup tools fmodel
skit setup tools repak
skit setup tools uassetgui
```

After installation, `FModel`, `repak`, and `UAssetGUI` can be started directly from a new terminal.

## License and third-party software

SCUM Mod Toolkit is available under the [MIT License](LICENSE).

FModel, repak, and UAssetGUI are not included in the SKit source repository
or release archives. SKit downloads them separately from their upstream
release pages when the user requests tool installation. Each tool remains
subject to its own license and copyright terms; see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

SKit distributions do not include SCUM game files, AES keys, extracted game
assets, or other copyrighted game material. Do not add such material to
issues, pull requests, source archives, or releases.

SCUM Mod Toolkit is an independent community project. It is not affiliated
with, endorsed by, sponsored by, or approved by Gamepires or Epic Games.
SCUM, Unreal Engine, and other names and trademarks belong to their
respective owners.

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

You can also start a separate Windows PowerShell 5.1 process with a one-time policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SCUM-Mod-Toolkit.ps1 setup self
```

Do not change `LocalMachine` or `CurrentUser` to `Bypass` solely for SKit. A permanent solution for broad distribution is to sign releases with a trusted code-signing certificate. The script must be signed again after every change.

### The `skit` command is not found

After installation, PowerShell may display:

```text
skit: The term 'skit' is not recognized as a name of a cmdlet, function,
script file, or executable program.
```

`skit setup self` adds `%LOCALAPPDATA%\Programs\SKit` to the user `PATH`, but an already open terminal normally does not load the updated setting automatically. The recommended solution is:

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

The message that the command exists in the current directory describes a different issue. For security reasons, PowerShell does not search the current directory for commands automatically. Run the local launcher with an explicit relative path:

```powershell
.\skit.cmd version
```

This runs the local `skit.cmd`. The `skit version` command without `.\` uses the globally installed copy found through `PATH`.
