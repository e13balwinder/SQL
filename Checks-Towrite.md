0) Instance & platform

 Uptime & unexpected restart — detect crashes.
Pass: Uptime > last planned maintenance. Fail: Unplanned reboot.

 SQL services running (Engine, Agent, Full-Text/SSRS/SSIS as used).
Pass: Running. Fail: Any stopped/disabled.

 Cluster/AG role stability — detect failovers.
Pass: No unexpected role changes. Fail: Role change without CAB/maintenance note.

 Edition/licensing sanity (Developer in non-prod, Standard/Ent in prod).
Pass: Matches CMDB. Fail: Drift.

1) Backup & restore (RPO/RTO)

 Last FULL backup age vs policy.
Pass: ≤ policy (e.g., 24h). Fail: > policy or missing DBs.

 Last DIFF backup age (if used).
Pass: ≤ policy. Fail: > policy.

 Last LOG backup age for FULL recovery DBs.
Pass: ≤ policy (e.g., ≤ 15 min). Fail: > policy or “never”.

 System DB backups (master, msdb, model).
Pass: Within policy. Fail: Missing/stale.

 Backup success status (jobs).
Pass: 100% success. Fail: Any failure/longer runtime > +50% baseline.

 Backup size anomalies (sudden ±30%).
Pass: Within variance. Fail: Spikes/drops unexplained.

 Checksum/compression enabled per standard.
Pass: Enabled. Fail: Off without reason.

 Copy/verify step (if used) completed.
Pass: Completed OK. Fail: Failed or skipped.

 Off-box copy presence (tape/object storage).
Pass: Latest set present. Fail: Missing.

 Restore test cadence (key DBs monthly or as per policy).
Pass: Last test ≤ policy. Fail: Overdue.

 Suspect pages (msdb) empty.
Pass: 0 rows (new since yesterday). Fail: Any new page entries.

2) High availability / DR

 AG database sync state.
Pass: SYNCHRONIZED/HEALTHY. Fail: NOT SYNCHRONIZED/NOT HEALTHY.

 AG send/redo queues.
Pass: ≤ thresholds (e.g., send/redo < 100MB). Fail: Over threshold or rising.

 Automatic seeding status (if used).
Pass: Completed/Not running. Fail: Error/Retry loops.

 Readable secondary (if required) responding.
Pass: Queries OK. Fail: Connection/lag issues.

 Log Shipping last backup/copy/restore times.
Pass: All within thresholds. Fail: Any step late/failing.

 Replication agents (Log Reader, Distribution, Merge).
Pass: Running, undistributed cmds low, latency within SLO. Fail: Failed agents/backlog.

 Mirroring (if present) SYNCHRONIZED/Running.
Pass: Healthy. Fail: Suspended/Disconnected.

3) Agent jobs & alerts

 Failed jobs (last 24h).
Pass: 0 failures. Fail: Any failure (triage now).

 Runtime regression.
Pass: Duration within ±30% baseline. Fail: > +50% without reason.

 Unexpected disabled jobs/steps.
Pass: As per CM. Fail: New disables.

 Job owners (SQL login mapped, not disabled).
Pass: Valid non-sa policy owner. Fail: Orphan/sa against policy.

 Operator notifications (emails/pages).
Pass: Recent alert delivered. Fail: Bounced/none.

 Alerts fired (sev ≥ 16, 823/824/825, deadlocks, AG role change).
Pass: 0 unacknowledged. Fail: Any unacknowledged.

4) Error logs & OS signals

 SQL Error Log criticals (823/824/825 I/O, dumps, stack traces).
Pass: None. Fail: Any new critical.

 Long I/O warnings (“taking longer than”).
Pass: None. Fail: Any new entries.

 Login failure spikes / brute-force patterns.
Pass: Baseline level. Fail: Spike >2× baseline.

 Agent log errors.
Pass: None. Fail: Any new.

 Windows System/Application critical events (disk/NIC/memory).
Pass: None new. Fail: Any since yesterday.

5) Database state & configuration hygiene

 All DBs ONLINE (not SUSPECT/RECOVERY_PENDING).
Pass: ONLINE. Fail: Any other state.

 Unexpected READ_ONLY or SINGLE_USER.
Pass: None. Fail: Any drift.

 Recovery model matches policy.
Pass: Expected (FULL/SIMPLE). Fail: Drift.

 Compatibility level matches target (e.g., 160 for SQL 2022).
Pass: As designed. Fail: Mismatch.

 PAGE_VERIFY = CHECKSUM.
Pass: CHECKSUM. Fail: TORN_PAGE_DETECTION/NONE.

 AUTO_CLOSE/AUTO_SHRINK off (prod).
Pass: OFF. Fail: ON.

 Database owner policy (e.g., dedicated owner, not sa).
Pass: Per standard. Fail: Non-compliant.

 TRUSTWORTHY OFF (unless explicitly needed).
Pass: OFF. Fail: ON without justification.

 Contained DBs intentional.
Pass: As designed. Fail: Accidental containment.

6) Capacity & files

 Data/log file free space.
Pass: ≥ 15–20% free or ≥ 7 days growth headroom. Fail: Below threshold.

 Autogrowth settings sane (fixed MB, not tiny %; rare growth events).
Pass: Fixed MB sized; ≤ 1–2 growths/day. Fail: Frequent growths or % growth.

 Recent growth/shrink events reviewed.
Pass: None unexpected. Fail: Unplanned growth/shrink.

 Log usage & growth.
Pass: No runaway log; LOG backups clearing VLFs. Fail: Persistent high % used or stalled truncation.

 VLF count reasonable.
Pass: < ~1000/DB (context-dependent). Fail: Excessive VLFs trending up.

 TempDB sizing (pre-sized, multiple files, equal size).
Pass: Files 1 per 4–8 cores (cap ~8), proper size. Fail: Single small file or frequent autogrowth.

 Disk free space on volumes.
Pass: ≥ 15–20% free. Fail: Below threshold.

7) Performance health

 CPU utilization (avg/peak).
Pass: Peaks < 70–80%, no sustained > 80%. Fail: Chronic high CPU.

 Memory pressure (signs of external/internal pressure, PLE trend).
Pass: Stable PLE/free list, no stolen-memory spikes. Fail: Constant trimming/low PLE trend.

 I/O latency per file.
Pass: Avg read/write < 20 ms (or your SLO). Fail: Over SLO or spiky.

 Top waits (delta vs baseline) ignoring benign waits.
Pass: Matches normal profile. Fail: New dominant waits.

 Blocking chains.
Pass: None > threshold (e.g., > 60s). Fail: Long chains/recurrence.

 Deadlocks (count last 24h).
Pass: 0 or within expected baseline. Fail: Spike/new pattern.

 Long-running requests.
Pass: None > SLA (e.g., > 15 min) without change record. Fail: Exceeds.

 TempDB allocation contention (PAGELATCH_*).
Pass: None. Fail: Recurrent latch waits.

 Resource Governor (if used) not in throttle.
Pass: Queues normal. Fail: Throttling unexpected.

8) Integrity & corruption

 DBCC CHECKDB cadence compliant (daily for critical clones, weekly/monthly per size).
Pass: Last CHECKDB ≤ policy. Fail: Overdue.

 Errors 823/824/825 since yesterday = 0.
Pass: 0. Fail: Any > 0.

 CHECKDB failures actioned.
Pass: N/A. Fail: Ticket opened with plan (restore from good backup, etc.).

9) Statistics & indexing

 Stats update job ran and within policy (e.g., > 20% mod threshold or time-based).
Pass: On schedule. Fail: Missed/overdue.

 Index maintenance completed (or policy-based selective).
Pass: As designed; no excessive fragmentation on hot paths. Fail: Skipped/overdue.

 Fragmentation outliers on large/hot indexes.
Pass: ≤ thresholds (e.g., < 30%). Fail: Over threshold with performance impact.

 Heaps with forwarded records watched.
Pass: Stable. Fail: High FR% increasing.

10) Security & compliance (delta since yesterday)

 New/changed logins, roles, perms (diff against baseline).
Pass: Approved changes only. Fail: Unknown changes.

 Sysadmin membership reviewed.
Pass: Approved list only. Fail: Additions/drift.

 Failed login patterns & account lockouts.
Pass: Baseline. Fail: Spike/attack.

 Endpoint/public perms (no public on sensitive objects).
Pass: Compliant. Fail: Over-grant.

 TDE cert/key health (expiry/backup presence).
Pass: Not nearing expiry; backups stored off-box. Fail: Expiry < 30 days or missing backups.

 xp_cmdshell/unsafe CLR per policy.
Pass: Disabled unless justified. Fail: Enabled drift.

11) Config & drift control

 sp_configure core settings (max server memory, maxdop, cost threshold, backup compression default, optimize for ad hoc, remote admin connections, clr enabled, etc.).
Pass: Matches standard. Fail: Drift.

 Trace flags required are on; others off.
Pass: As standard. Fail: Drift.

 Database-scoped configurations (legacy CE, parameter sniffing mitigations, MAXDOP, row mode memory grant feedback, etc.).
Pass: Matches standard. Fail: Drift.

 Model DB template (file sizes, options).
Pass: Standardized. Fail: Drift.