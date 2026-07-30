# Instructions for Codex

Use the following text when handing the project to a new Codex session:

> First read `AGENTS.md`, `README.md`, `DEVELOPMENT.md`, and `CHANGELOG.md`.
> Treat documented CLI commands, version rules, SHA-256 checks, external tool
> arguments, and the `skit.yml` format as backward-compatibility contracts.
>
> Implement the requested change in `SCUM-Mod-Toolkit.ps1`. Preserve Windows
> PowerShell 5.1 compatibility, and do not install anything or modify `PATH`
> when the script is dot-sourced. Code, function names, comments, log
> messages, error messages, test names, and documentation must be in English.
>
> Add or update Pester tests for both the normal case and relevant failures.
> Run the complete test suite in Windows PowerShell 5.1. Update documentation
> and `CHANGELOG.md` when behavior changes. If this is a new SKit version,
> also update `$script:SKitVersion`.
>
> Verify changes involving repak, UAssetGUI, FModel, or the GitHub API against
> the corresponding official upstream source. Do not weaken SHA-256
> verification.
>
> Finish with a short summary of changed files, test results, and anything
> that still requires a real Windows/SCUM test.

Append the concrete task after the text. For example:

> Task: Add the `skit clean` command, which removes local project build
> artifacts after explicit confirmation.
