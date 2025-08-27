/* Returns a single scalar: full_backup_age_hours (max age across user DBs) */
SET NOCOUNT ON;
SELECT MAX(DATEDIFF(HOUR, bs.backup_finish_date, SYSDATETIME())) AS full_backup_age_hours
FROM msdb.dbo.backupset AS bs
WHERE bs.type = 'D' /* full */
  AND bs.is_copy_only = 0
  AND bs.database_name NOT IN ('tempdb');

