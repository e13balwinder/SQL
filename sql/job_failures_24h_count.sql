/* Returns a single scalar: job_failed_24h */
SET NOCOUNT ON;
SELECT COUNT(*) AS job_failed_24h
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON h.job_id = j.job_id
WHERE h.run_status = 0 /* failed */
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(HOUR, -24, SYSDATETIME());

