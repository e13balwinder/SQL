# Azure Daily Checks – To‑Do

This plan breaks deployment into clear phases so we can grow checks without rewrites. Each phase is incremental and builds on the previous one.

## Phase 0 – Scaffolding (done)
- Config example with `defaults` and per-resource overrides
- Basic HTML template + CSS
- Config loader (`Get-HealthCheckConfig`)

## Phase 1 – Report v1 (done)
- Render config-driven summary to HTML (no live data)
- Entrypoint wiring (`Invoke-DailyChecks.ps1` → `Render-Report.ps1`)

## Phase 2 – VM Metrics (done)
- Add modular Azure Monitor metrics runner (`Test-AzVmMetric`)
- Config-driven metric definitions (`defaults.azureVm.metricChecks`)
- Per-VM overrides by metric `id`
  
  Acceptance
  - Collects `Percentage CPU` with thresholds and renders status
  - Handles no-data, API errors, and unit reporting
  - Pester covers severity logic and config merge

## Phase 3 – SQL Basics (done)
- TCP reachability for SQL instance (`Test-SqlInstanceHealth`)
- Placeholder outputs for remaining SQL checks

## Phase 4 – SQL Script Checks (in progress)
- Create `sql/` folder for T‑SQL files (one check per file)
- Add config-driven `defaults.sqlServer.scriptChecks[]` with:
  - `id`, `name`, `file`, `enabled`, `evaluator` (e.g., `scalar-threshold`, `rows-exist`), optional `queryParams`
- Implement modular runner (`Test-SqlScripts`) that:
  - Resolves defaults + per-resource overrides
  - Executes scripts (when enabled) via `Invoke-Sqlcmd` with timeouts
  - Evaluates results using `operator/warn/crit`
  - Supports `-WhatIf` to avoid live calls
  
  Acceptance
  - Runs at least 2 enabled checks (backup age, blocked sessions)
  - SQL auth supports Windows-first, optional AAD fallback (`mode=auto`)
  - Pester covers WhatIf and auth fallback

## Phase 5 – SQL Library Expansion
- Implement the SQL checks backlog (below) with one `.sql` file per check and JSON `scriptChecks[]` entries. Ensure SQL Server 2022 (v16) compatibility and target DB compatibility level 160 where applicable.
- Parameterize scripts where useful (e.g., DB exclusions, thresholds via evaluator only).

## Phase 6 – Report v2
- Add “Findings” table with per-check results and messages
- Severity summary + filters by resource/type/severity
- Link checks to script id/description for traceability
  
  Acceptance
  - Findings section lists all executed checks with thresholds and messages
  - Summary banner shows OK/Warn/Crit counts and filters apply
  - Optional anchors to per-resource sections

## Phase 7 – Testing & Quality
- Pester: config schema + merging + evaluators (mock `Get-AzMetric`/`Invoke-Sqlcmd`)
- ScriptAnalyzer formatting and lint
- Aim ≥85% coverage for changed code
  
  Acceptance
  - `Invoke-Pester -CI` green; coverage ≥85% on changed scripts/modules
  - `Invoke-ScriptAnalyzer` clean per repo settings
  - Renderer output smoke-tested in CI (artifact contains HTML)

## Phase 8 – CI/CD & Packaging
- GitHub Actions/Azure DevOps pipeline: lint, tests, artifact (report)
- Optional: package as a PowerShell module with entry scripts
  
  Acceptance
  - CI runs lint + tests on PRs and publishes artifacts on main
  - Optional module manifest packs `modules/*` with entry scripts

## Phase 9 – Auth, Telemetry, Docs
- Azure auth: Managed Identity / `Connect-AzAccount`
- SQL auth: Integrated, AAD token, or secret by Key Vault reference (no secrets in git)
- Structured logs (JSONL), run metadata (duration, counts)
- Quickstart and ops runbook
  
  Acceptance
  - Documented auth modes and minimal permissions per check
  - Report footer shows run metadata (duration, resource count)
  - Quickstart validated on a fresh environment

## Phase 10 – Baselines & Variance
- Add lightweight baseline store (e.g., `out/baseline.json` or workspace path)
- Track metrics like job runtime, backup size, waits mix; compare vs baseline
- Evaluators support variance (e.g., `+50%` regression)
  
  Acceptance
  - Baseline written/read; first run seeds; subsequent runs compute deltas
  - At least one variance-based check (job runtime) flagged correctly

## Phase 11 – Resilience & Performance
- Concurrency controls for checks (max degree of parallelism)
- Retry/backoff on Azure 429/5xx with jitter
- Optional caching for shared metric windows to reduce API calls
  
  Acceptance
  - Configurable concurrency; stable runtime under load
  - Retries observable in logs; no excessive API failures
  - Caching reduces duplicate queries in multi-VM scenarios

## Phase 12 – Result Exports
- Write machine-readable outputs: `out/results.json` and `out/run-*.jsonl`
- Include in CI artifact for downstream processing
  
  Acceptance
  - Results export matches HTML Findings; schema documented
  - CI publishes exports alongside HTML

## Phase 13 – Schema & Migration
- Provide JSON Schemas for config and subscriptions files
- Add schema validation step in tests
- Add migration notes when `schemaVersion` increments (breaking vs additive)
  
  Acceptance
  - Schemas present; validation step fails on malformed config
  - Migration doc/example when bumping schema

## Phase 14 – Redaction Mode
- Config switch to anonymize resource identifiers in HTML/exports
- Preserve internal IDs in machine outputs when allowed
  
  Acceptance
  - Redacted report hides hostnames/resourceIds; still useful for triage
  - Toggle verified via test snapshot

---

## Optional Next Steps (backlog)
- Subscriptions + tags filtering config:
  - Add `config/subscriptions.example.json` to carry a list of target subscriptions and tag filters.
  - Support filtering configured resources by `subscriptionId` and `tags` (done in engine).
  - Future: discovery mode to enumerate resources by subscription/tag using Az.ResourceGraph.
- Resource discovery (enumerate SQL/VMs by tag) to seed config
- Caching of metric results and SQL outputs for offline review
- Suppressions (temporary waivers with expiration)
- Threshold profiles by environment (dev/test/prod)
- AG failover intent detection and advisory

## Subscriptions & Tags Usage
- Copy and edit the example: `cp config/subscriptions.example.json config/subscriptions.json`
- List resources that would be included (no checks run):
  - `pwsh -File scripts/Invoke-DailyChecks.ps1 -Config config/health-check-config.example.json -Subscriptions config/subscriptions.json -OutDir out -ListResources`
- Run checks with filters and render report:
  - `pwsh -File scripts/Invoke-DailyChecks.ps1 -Config config/health-check-config.example.json -Subscriptions config/subscriptions.json -OutDir out`
- Render config-only report (no live checks):
  - `pwsh -File scripts/Invoke-DailyChecks.ps1 -Config config/health-check-config.example.json -OutDir out -SkipChecks`

### Discovery Plans (future)
- Add a discovery mode that builds `resources[]` by querying Azure Resource Graph across filtered subscriptions/tags (e.g., VMs with specific tags), then merges with static config.
- Map discovered VMs to SQL endpoints using conventions (default instance/port) or a mapping table; leave manual overrides for non-standard instances.
- Keep discovery read-only; store only non-sensitive metadata.

## SQL Checks Backlog (SQL Server 2022)

Notes
- Each item becomes a `.sql` in `sql/` returning a minimal, evaluator-friendly shape (scalar or rows) and is referenced in `defaults.sqlServer.scriptChecks[]`.
- Target: SQL Server 2022 (v16). Prefer DMVs, catalog views, and system functions present in 2022. Avoid deprecated features; guard optional features (e.g., AG, LS, Replication) with existence checks.

0) Instance & Platform
- Uptime/unexpected restart: detect reboots since planned maintenance.
- SQL services running: Engine/Agent/FT/SSRS/SSIS as applicable.
- Cluster/AG role stability: detect unexpected role changes.
- Edition/licensing sanity: matches CMDB/environment policy.

1) Backup & Restore (RPO/RTO)
- Last FULL backup age vs policy (per DB; highlight missing DBs).
- Last DIFF backup age (if used).
- Last LOG backup age for FULL recovery DBs.
- System DB backups (master, msdb, model) age/status.
- Backup job success and abnormal runtime (+50% over baseline).
- Backup size anomalies (±30% variance vs baseline).
- Checksum/compression policy compliance.
- Copy/verify step completed (if used).
- Off-box copy presence (tape/object storage) confirmation.
- Restore test cadence for key DBs.
- Suspect pages since last run.

2) High Availability / DR
- AG DB sync state and overall health.
- AG send/redo queue sizes vs thresholds.
- Automatic seeding status (if used).
- Readable secondary health (connectivity/lag checks).
- Log Shipping last backup/copy/restore times.
- Replication agents status and backlog/latency.
- Mirroring health (if present).

3) Agent Jobs & Alerts
- Failed jobs (last 24h).
- Job runtime regression (> +50% baseline).
- Unexpected disabled jobs/steps.
- Job owners policy compliance.
- Operator notification delivery status.
- Alerts fired (severity ≥16, 823/824/825, deadlocks, AG role change) and acknowledgment state.

4) Error Logs & OS Signals
- SQL Error Log criticals (823/824/825, dumps, stack traces).
- Long I/O warnings (“taking longer than ...”).
- Login failure spikes / brute-force patterns.
- Agent log errors.
- Windows System/Application critical events (disk/NIC/memory) since last run.

5) Database State & Config Hygiene
- All DBs ONLINE (not SUSPECT/RECOVERY_PENDING).
- Unexpected READ_ONLY or SINGLE_USER modes.
- Recovery model policy compliance (FULL/SIMPLE as designed).
- Compatibility level target (e.g., 160 for SQL 2022) compliance.
- PAGE_VERIFY = CHECKSUM across DBs.
- AUTO_CLOSE/AUTO_SHRINK off (prod) compliance.
- Database owner policy compliance.
- TRUSTWORTHY OFF unless justified.
- Contained DBs intentional/approved.

6) Capacity & Files
- Data/log file free space thresholds.
- Autogrowth sane (fixed MB; avoid tiny %; low growth event rate).
- Recent growth/shrink events reviewed.
- Log usage and growth health; truncation not stalled.
- VLF count reasonable (context-dependent; watch for extremes).
- TempDB sizing (pre-sized, multi-files, equal sizes).
- Disk volume free space thresholds.

7) Performance Health
- CPU utilization (avg/peak) vs SLO.
- Memory pressure: PLE trend, stolen memory, external pressure.
- I/O latency per file vs SLO.
- Top waits delta vs baseline (ignore benign waits).
- Blocking chains above threshold duration.
- Deadlock count (last 24h) vs baseline.
- Long-running requests exceeding SLA.
- TempDB allocation contention (PAGELATCH_* hotspots).
- Resource Governor (if used) throttling status.

8) Integrity & Corruption
- DBCC CHECKDB cadence compliance.
- Errors 823/824/825 since last run.
- CHECKDB failures actioned (evidence of response).

9) Statistics & Indexing
- Stats update cadence (policy-driven threshold or time-based).
- Index maintenance completed/selective policy adherence.
- Fragmentation outliers on large/hot indexes.
- Heaps with forwarded records monitored.

10) Security & Compliance (delta)
- New/changed logins/roles/perms vs baseline.
- Sysadmin membership reviewed.
- Failed login spikes and account lockouts.
- Endpoint/public perms — avoid public on sensitive objects.
- TDE cert/key health (expiry/backup presence).
- xp_cmdshell/unsafe CLR per policy.

11) Config & Drift Control
- sp_configure core settings compliance (max memory, MAXDOP, cost threshold, backup compression default, optimize for ad hoc, remote admin connections, clr enabled, etc.).
- Trace flags required are on; others off.
- Database-scoped configurations compliance (CE, sniffing mitigations, MAXDOP, memory grant feedback, etc.).
- Model DB template compliance (file sizes, options).


## Decisions / Principles
- Checks are config‑first; code is generic
- One public function per module; modules provide `Get-HealthCheckSpec` for discovery
- JSON is the contract; scripts referenced by path to avoid PowerShell hard‑coding
