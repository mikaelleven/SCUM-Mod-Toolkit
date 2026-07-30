# Changelog

All notable SKit changes are documented in this file.

## Unreleased

### Changed

- Standardized the README, development guide, Codex handoff, and repository
  instructions in English.

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
