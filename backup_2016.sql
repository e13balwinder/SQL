-- Change this
DECLARE @db sysname = N'YourDB';

DECLARE @lastDiffFinish  datetime,
        @lastDiffLastLsn numeric(25,0);

-- Last differential backup metadata
SELECT TOP (1)
  @lastDiffFinish  = bs.backup_finish_date,
  @lastDiffLastLsn = bs.last_lsn
FROM msdb.dbo.backupset AS bs
WHERE bs.database_name = @db
  AND bs.[type] = 'I'           -- differential
ORDER BY bs.backup_finish_date DESC;

IF @lastDiffFinish IS NULL
BEGIN
  SELECT @db AS database_name, 'No differential backup found' AS note;
  RETURN;
END;

-- Convert DECIMAL(25,0) LSN -> canonical hex string (HHHHHHHH:MMMMMMMM:LLLL)
DECLARE @pow48 numeric(25,0) = CONVERT(numeric(25,0), POWER(CAST(2 AS bigint), 48));
DECLARE @pow16 numeric(25,0) = CONVERT(numeric(25,0), POWER(CAST(2 AS bigint), 16));

DECLARE @hi  bigint = CAST(@lastDiffLastLsn / @pow48 AS bigint);
DECLARE @rem numeric(25,0) = @lastDiffLastLsn % @pow48;
DECLARE @mid bigint = CAST(@rem / @pow16 AS bigint);
DECLARE @lo  bigint = CAST(@rem % @pow16 AS bigint);

DECLARE @lastDiffLsnStr nvarchar(30) =
  CONCAT(
    RIGHT(REPLICATE('0',8) + FORMAT(@hi,  'X'), 8), ':',
    RIGHT(REPLICATE('0',8) + FORMAT(@mid, 'X'), 8), ':',
    RIGHT(REPLICATE('0',4) + FORMAT(@lo,  'X'), 4)
  );

-- Current end-of-log LSN from the database log
DECLARE @curLsnStr nvarchar(30);
DECLARE @sql nvarchar(max) = N'USE ' + QUOTENAME(@db) + N';
SELECT TOP (1) @out = UPPER([Current LSN])
FROM sys.fn_dblog(NULL, NULL)
ORDER BY [Current LSN] DESC;';
EXEC sp_executesql @sql, N'@out nvarchar(30) OUTPUT', @out = @curLsnStr OUTPUT;

-- Result
SELECT
  @db                              AS database_name,
  @lastDiffFinish                  AS last_diff_finish_time,
  @lastDiffLastLsn                 AS last_diff_end_lsn_dec,
  UPPER(@lastDiffLsnStr)           AS last_diff_end_lsn,
  @curLsnStr                       AS current_end_lsn,
  CASE WHEN @curLsnStr = UPPER(@lastDiffLsnStr)
       THEN 'No logged activity since last differential'
       ELSE 'Logged activity since last differential (changes likely)'
  END                              AS assessment;
