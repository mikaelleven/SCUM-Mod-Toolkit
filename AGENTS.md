# Codex instructions for SKit

These instructions apply to the complete repository.

## Read first

Before changing code, read `README.md`, `DEVELOPMENT.md`, and
`CHANGELOG.md`. Treat the documented CLI, project schema, version rules,
security checks, and external-tool arguments as compatibility contracts.

## Platform and compatibility

- Target Windows 11 and Windows PowerShell 5.1.
- Do not require PowerShell 7.
- Do not introduce syntax or standard-library APIs unavailable in
  Windows PowerShell 5.1.
- Keep `SCUM-Mod-Toolkit.ps1` dot-sourceable. Dot-sourcing must define
  functions without installing SKit, mutating PATH, starting processes, or
  dispatching a command.
- Preserve compatibility with existing `skit.yml`, `skit.config.yml`, and
  `SKit.yaml` files unless a migration is explicitly requested.

## Code and documentation

- Write code, function names, comments, test names, log messages, and error
  messages in English.
- Keep all documentation in English.
- Prefer small, focused functions and PowerShell/.NET built-ins.
- Keep the strict YAML parser dependency-free. Do not add a general YAML
  module unless explicitly requested.
- Use literal paths for filesystem mutations and validate targets before
  overwriting or deleting files.
- Do not silently ignore invalid input or failed external commands.

## Behaviors that must not change accidentally

- Install SKit and tools below `%LOCALAPPDATA%\Programs\SKit`.
- Register that directory in the user PATH without adding duplicates.
- Require a valid `sha256:<64 hex characters>` digest from GitHub release
  metadata and verify downloaded bytes before installation.
- Stop installation when the digest is absent, malformed, or mismatched.
- Install the latest published GitHub release of FModel, repak, and
  UAssetGUI.
- Use repak PAK version `V11`.
- Use UAssetGUI engine version `VER_UE4_27` by default.
- Create `<asset>.full.json` for `tojson`.
- Preserve the version transitions documented in `DEVELOPMENT.md`.
- Always exclude `skit.yml`, `.git/**`, and `build/**` from project builds.
- Exit the CLI with code `1` and an `[SKit] ERROR:` message on failure.

## External tools

Verify external CLI syntax against the upstream repository or official
documentation before changing an invocation. Update both `DEVELOPMENT.md`
and tests when an external command contract changes.

Never weaken checksum verification merely to support an upstream release
that lacks a digest. Report the compatibility issue instead.

## Tests and delivery

For every behavior change:

1. Add or update Pester tests.
2. Run the parser check and the complete Pester suite in Windows
   PowerShell 5.1.
3. Update `README.md` when user-visible behavior changes.
4. Update `DEVELOPMENT.md` when architecture or a compatibility contract
   changes.
5. Update `CHANGELOG.md` and `$script:SKitVersion` for a new SKit release.
6. Report what was verified and what still requires a real Windows/SCUM
   end-to-end test.

Do not claim an end-to-end test passed if repak, UAssetGUI, FModel, Steam,
or SCUM was mocked or unavailable.

## Git commits

Whenever the user asks for a Git commit, increment the final component of
`$script:SKitVersion` before creating it unless the user explicitly requests
otherwise. Update `CHANGELOG.md`, run the required checks, and include all
intended changes in the commit.

## GitHub releases

Before preparing a release, synchronize the local `master` branch with
GitHub. The working tree must be clean, then run:

```powershell
git fetch origin
git pull --ff-only origin master
```

Do not create a release from a local branch that is behind `origin/master`.

When an automation or outer PowerShell process invokes the publishing script,
escape `$false` so Windows PowerShell receives it as a Boolean expression:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Publish-SKitRelease.ps1' -Publish -Confirm:`$false"
```

From an already interactive Windows PowerShell session, invoke the script
directly instead:

```powershell
.\Publish-SKitRelease.ps1 -Publish -Confirm:$false
```
