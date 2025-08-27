/* Returns a single scalar: blocked_sessions */
SET NOCOUNT ON;
SELECT COUNT(*) AS blocked_sessions
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0;

