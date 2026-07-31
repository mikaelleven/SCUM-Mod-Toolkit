# Changelog

All notable SKit changes are documented in this file.

## Unreleased

### Added

- Added `Install-SKit.ps1` for `irm <URL> | iex` installation from the latest
  GitHub release with mandatory SHA-256 verification, self-installation,
  current-session PATH refresh, and post-installation version verification.

## 1.1.0.10 - 2026-07-31

### Added

- Added `Publish-SKitRelease.ps1` to build a verified end-user release archive
  and, with explicit `-Publish`, create and push the Git tag and publish the
  GitHub release through GitHub CLI.

## 1.1.0.9 - 2026-07-31

### Added

- Added `skit setup uninstall` to remove installed SKit scripts, command
  files, and tools while retaining YAML configuration files by default.
- Added `skit setup uninstall all`, with Y/N confirmation before YAML
  configuration files are removed.

## 1.1.0.8 - 2026-07-31

### Added

- Added `skit setup register-path` to retry user PATH registration after a
  managed-profile or environment failure.

### Fixed

- Prevented self-installation output from being interpreted as an installer
  exit code.
- Made failed user PATH registration a warning so a successful installation
  remains usable.

## 1.1.0.7 - 2026-07-30

### Fixed

- Waited for GUI-subsystem command-line tools such as UAssetGUI and safely
  initialized their exit code before checking it under strict mode.

## 1.1.0.6 - 2026-07-30

### Fixed

- Normalized configured SCUM AES keys to a lowercase `0x` prefix before
  passing them to repak, including keys previously stored with `0X`.

### Changed

- Removed contributor-only document ordering and test instructions from the
  end-user README. Development guidance remains in `AGENTS.md` and
  `DEVELOPMENT.md`.
- Removed the redundant `CODEX-HANDOFF.md`; its permanent rules and technical
  guidance are already covered by `AGENTS.md` and `DEVELOPMENT.md`.

## 1.1.0.5 - 2026-07-30

### Added

- MIT licensing for SKit and third-party notices for FModel, repak, and
  UAssetGUI.
- Repository ignore rules for downloaded tools, runtime configuration, AES
  keys, game assets, and generated mod content.

### Changed

- `skit pack` and `skit unpack` now pass the configured SCUM AES key to
  repak automatically.
- Added `-o` and `-omit-key` to pack and unpack for explicitly omitting the
  configured AES key.
- Updated the README to require a user-supplied SCUM-specific AES key
  without documenting a source.
- Documented source-only distribution rules and the project's independent,
  unofficial status.

## 1.1.0.4 - 2026-07-30

### Added

- `skit setup open-config` for creating and opening the global YAML
  configuration through its Windows file association with a Notepad
  fallback.
- `skit setup help` with dedicated setup command documentation.

### Changed

- Moved tool installation, self-installation, SCUM path configuration,
  automatic path detection, AES key commands, and custom launch parameters
  below `skit setup`.
- Renamed automatic SCUM detection to `skit setup detect-path`.
- Removed the replaced top-level and `skit config` command forms.

### Fixed

- Replaced the unavailable `Get-FileHash` dependency with a
  Windows PowerShell 5.1-compatible .NET SHA-256 implementation.

## 1.1.0.3 - 2026-07-30

### Added

- `skit config get-key` for storing the current SCUM AES key in the global
  YAML configuration and, when safe, in an existing FModel SCUM entry.
- `skit config set-startparams <parameter-string>` and the
  `scumStartParams` setting for custom SCUM launch arguments.

### Changed

- `skit config find-key` now writes `SCUM-AES-Key.txt` to the current
  directory.
- Custom launch parameters are appended in both modded and default play
  modes.

## 1.1.0.2 - 2026-07-30

### Changed

- Standardized the README, development guide, Codex handoff, and repository
  instructions in English.
- Renamed the installed script to `SCUM-Mod-Toolkit.ps1` and the global
  configuration to `SCUM-Mod-Toolkit.yaml`.
- Added ordered migration of `skit.config.yml` and `SKit.yaml` values into
  the new global configuration file.
- Changed the missing SCUM path error to recommend
  `skit config detect-scum`.

## 1.1.0.1 - 2026-07-30

### Changed

- Added installation troubleshooting for unsigned downloaded scripts,
  execution policies, PATH refresh, and local `skit.cmd` invocation.

## 1.1.0 - 2026-07-30

### Added

- `skit config find-key` for downloading and validating the current SCUM AES
  key without relying on a fixed source line number.
- `skit config detect-scum` for locating SCUM in configured Steam libraries.
- `skit play modded` and `skit play default` launch modes.

### Changed

- `skit play` starts `SCUM.exe` in modded mode by default with
  `-fileopenlog -nobattleye`.
- Global configuration is written to `SKit.yaml`; legacy `skit.config.yml`
  remains readable.

### Fixed

- Strict YAML error messages now parse correctly in Windows PowerShell 5.1.

## 1.0.1 - 2026-07-30

### Added

- `AGENTS.md` with permanent Codex development rules.
- `DEVELOPMENT.md` with architecture, compatibility contracts, version
  semantics, test strategy, and release checklist.
- `CODEX-HANDOFF.md` with a reusable handoff prompt.
- Pester tests for parsing, versions, YAML, globs, checksums, asset
  selection, external command arguments, staging, and release sequencing.

### Changed

- The command dispatcher is now wrapped in `Invoke-SKitCommand`.
- Dot-sourcing loads functions without installation or command dispatch,
  enabling isolated Pester tests.
- GitHub API requests use the current `2026-03-10` API version.
- User documentation now explicitly describes automatic self-installation
  and the build-first release version flow.

## 1.0.0 - 2026-07-30

### Added

- Initial SKit implementation.
- Verified installation of FModel, repak, and UAssetGUI.
- Wrappers for packing, unpacking, UAsset JSON export, and JSON import.
- Strict `skit.yml` project format.
- Project build, bump, release, install, test, play, and init commands.
