Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-SqlInstanceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject]$Resource,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject]$CheckDefs,

        [Parameter()]
        [ValidateRange(1,600)]
        [int]$ConnectTimeoutSeconds = 15,

        [switch]$WhatIf
    )

    $results = @()

    # Helper to emit a standard result
    function New-Result {
        param(
            [string]$id,
            [string]$name,
            [string]$severity,
            [string]$message,
            [object]$observed = $null,
            [object]$threshold = $null
        )
        [pscustomobject]@{
            ResourceId   = [string]$Resource.id
            ResourceType = [string]$Resource.type
            CheckId      = $id
            DisplayName  = $name
            Severity     = $severity
            Observed     = $observed
            Threshold    = $threshold
            Message      = $message
            TimeRange    = $null
        }
    }

    # 1) Instance reachability via TCP (no SQL auth required)
    if ($CheckDefs.instanceReachable) {
        $server = [string]$Resource.identifier.server
        $port = [int]$Resource.identifier.port
        $timeoutMs = 1000 * [int]$ConnectTimeoutSeconds
        if ($WhatIf) {
            $results += New-Result -id 'instanceReachable' -name 'Instance Reachable' -severity 'na' -message 'WhatIf: not tested' -observed $null -threshold @{ connectTimeoutSeconds = $ConnectTimeoutSeconds }
        }
        else {
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $iar = $client.BeginConnect($server, $port, $null, $null)
                if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
                    $client.Close()
                    $results += New-Result -id 'instanceReachable' -name 'Instance Reachable' -severity 'crit' -message "TCP connect to $server:$port timed out" -threshold @{ connectTimeoutSeconds = $ConnectTimeoutSeconds }
                } else {
                    $client.EndConnect($iar)
                    $client.Close()
                    $results += New-Result -id 'instanceReachable' -name 'Instance Reachable' -severity 'ok' -message "TCP connect to $server:$port succeeded in < $ConnectTimeoutSeconds s" -observed $true -threshold @{ connectTimeoutSeconds = $ConnectTimeoutSeconds }
                }
            }
            catch {
                $results += New-Result -id 'instanceReachable' -name 'Instance Reachable' -severity 'crit' -message ("TCP connect failed: " + $_.Exception.Message) -threshold @{ connectTimeoutSeconds = $ConnectTimeoutSeconds }
            }
        }
    }

    # 2) Other SQL checks (placeholders until T-SQL queries are added)
    foreach ($p in $CheckDefs.PSObject.Properties) {
        $id = $p.Name
        if ($id -eq 'instanceReachable') { continue }
        $display = switch ($id) {
            'cpuPercent' { 'CPU Utilization' }
            'memory' { 'Memory / PLE' }
            'agentRunning' { 'SQL Agent Running' }
            'blockedSessions' { 'Blocked Sessions' }
            'deadlocksPerHour' { 'Deadlocks per Hour' }
            'databaseStatus' { 'Database Status' }
            'dbFreeSpacePercent' { 'DB Free Space %' }
            'backupAgeHours' { 'Backup Age (hours)' }
            'jobFailures24h' { 'Job Failures (24h)' }
            'tempdb' { 'TempDB Health' }
            'indexFragmentation' { 'Index Fragmentation %' }
            'vlfCount' { 'Log VLF Count' }
            'ioLatencyMs' { 'IO Latency (ms)' }
            'diskFreePercent' { 'Disk Free %' }
            'availabilityGroups' { 'Availability Group Health' }
            'errorLogSeverityMin' { 'Error Log Severity' }
            Default { $id }
        }
        $results += New-Result -id $id -name $display -severity 'na' -message 'Not collected (SQL query not implemented in v1)'
    }

    return ,$results
}

function Get-HealthCheckSpec {
    [CmdletBinding()]
    param()
    $invoke = {
        param(
            [Parameter(Mandatory)][pscustomobject]$Resource,
            [Parameter(Mandatory)][pscustomobject]$Config,
            [switch]$WhatIf
        )
        $base = $Config.Defaults.sqlServer.checks.PSObject.Copy()
        if ($Resource.thresholdOverrides) {
            foreach ($prop in $Resource.thresholdOverrides.PSObject.Properties) {
                if ($base.PSObject.Properties.Name -contains $prop.Name) {
                    $base.($prop.Name) = $prop.Value
                }
            }
        }
        $connTimeout = 15
        if ($Config.Defaults.sqlServer.connection -and $Config.Defaults.sqlServer.connection.loginTimeoutSeconds) {
            $connTimeout = [int]$Config.Defaults.sqlServer.connection.loginTimeoutSeconds
        }
        return Test-SqlInstanceHealth -Resource $Resource -CheckDefs $base -ConnectTimeoutSeconds $connTimeout -WhatIf:$WhatIf.IsPresent
    }
    return ,([pscustomobject]@{ ResourceType='SqlServer'; Id='sql.instance'; Invoke=$invoke })
}

Export-ModuleMember -Function Test-SqlInstanceHealth, Get-HealthCheckSpec
