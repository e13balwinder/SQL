/* Returns a single scalar: db_problem */
SET NOCOUNT ON;
SELECT COUNT(*) AS db_problem
FROM sys.databases
WHERE state_desc IN ('OFFLINE','EMERGENCY','RECOVERY_PENDING','SUSPECT','RECOVERY');

