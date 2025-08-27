# Repository Guidelines

PowerShell tooling for a modular Azure Daily Checks Dashboard/Report: runs SQL Server health checks and VM status checks, then renders a dashboard artifact.

## Project Structure & Modules
- `scripts/`: entrypoints (e.g., `Invoke-DailyChecks.ps1`, `Render-Report.ps1`).
- `modules/Checks/`: individual check modules (e.g., `Test-SqlInstance.psm1`, `Test-AzVm.psm1`).
- `modules/Common/`: shared helpers (auth, formatting, telemetry).
- `config/`: environment JSON (resource IDs, subscriptions). Commit `*.example.json` only.
- `assets/`: report templates/CSS; `out/`: generated reports (ignored by Git).

## Run, Build, and Test
- Setup: `pwsh -NoProfile -Command "Install-Module Az,Pester,PSScriptAnalyzer -Scope CurrentUser"`.
- Run local: `pwsh -File scripts/Invoke-DailyChecks.ps1 -Config config/dev.json -OutDir out/`.
- Lint: `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1`.
- Format: `Invoke-Formatter -Path scripts,modules`.
- Tests: `Invoke-Pester -Path tests -CI -CodeCoverage scripts,modules`.

## Coding Style & Naming
- Indentation: 4 spaces; UTF-8; max line ~120 chars.
- Cmdlets: `Verb-Noun` with approved verbs (e.g., `Test-SqlInstanceHealth`). One public function per file; file name matches function.
- Parameters: typed, validated (`[Parameter(Mandatory)]`, `[ValidateSet()]`); support `-WhatIf` where applicable.
- Entrypoints: `Set-StrictMode -Version Latest`; `$ErrorActionPreference='Stop'`; use `try/catch` and `throw`.

## Testing Guidelines
- Framework: Pester v5. Tests live in `tests/` as `*.Tests.ps1` mirroring modules.
- Coverage: aim ≥ 85% for changed code; mock Az/SQL calls; no live network in unit tests.
- Include edge cases: auth failures, missing resources, throttling, transient errors.

## Commit & Pull Requests
- Conventional Commits (e.g., `feat(checks): add VM power state`, `fix(sql): handle offline DBs`).
- PRs: clear scope, linked issues, sample report snippet/screenshot, and test notes. Keep diffs minimal and pass lint/tests.

## Security & Config
- Never commit secrets. Use Azure AD/Managed Identity or `Connect-AzAccount`. Store sensitive values in Key Vault; reference by name in `config/*.json`.
- Limit permissions to read-only where possible; log only non-sensitive metadata.
