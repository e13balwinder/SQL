/* Returns a single scalar: ag_unhealthy */
SET NOCOUNT ON;
SELECT COUNT(*) AS ag_unhealthy
FROM sys.dm_hadr_availability_replica_states AS s
JOIN sys.availability_replicas AS r ON s.replica_id = r.replica_id
WHERE s.synchronization_health_desc <> 'HEALTHY';

