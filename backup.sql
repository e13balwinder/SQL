DECLARE @db sysname = N'YourDB';

;WITH last_diff AS (
  SELECT TOP (1)
         backup_finish_date,
         last_lsn
  FROM msdb.dbo.backupset
  WHERE database_name = @db AND type = 'I'
  ORDER BY backup_finish_date DESC
)
SELECT 
    ld.backup_finish_date  AS last_diff_finish_time,
    ld.last_lsn            AS last_diff_end_lsn,
    ls.end_of_log_lsn,
    CASE 
      WHEN ls.end_of_log_lsn = ld.last_lsn THEN 'No logged activity since last differential'
      ELSE 'Logged activity since last differential (likely changes)'
    END AS assessment
FROM last_diff ld
CROSS APPLY sys.dm_db_log_stats(DB_ID(@db)) AS ls;  -- SQL Server 2019+
