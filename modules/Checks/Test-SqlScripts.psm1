Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-SqlScriptChecks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Resource,

        [Parameter(Mandatory)]
        [pscustomobject[]]$ScriptDefs,

        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [int]$QueryTimeoutSeconds = 60,

        [switch]$WhatIf
    )

    $results = @()

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

    # Build ServerInstance for Invoke-Sqlcmd
    $server = [string]$Resource.identifier.server
    $port = [int]$Resource.identifier.port
    $instance = [string]$Resource.identifier.instance
    $serverInstance = if ($instance -and $instance -ne 'MSSQLSERVER') {
        if ($port) { "{0}\{1},{2}" -f $server, $instance, $port } else { "{0}\{1}" -f $server, $instance }
    } else {
        if ($port) { "{0},{1}" -f $server, $port } else { $server }
    }

    # Load auth helper
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'Common/Get-SqlAuth.psm1') -Force | Out-Null
    $authMode = if ($Config.Defaults.sqlServer.auth.mode) { [string]$Config.Defaults.sqlServer.auth.mode } else { 'auto' }

    foreach ($def in $ScriptDefs) {
        $id = [string]$def.id
        $name = [string]$def.name
        $file = [string]$def.file
        $eval = $def.evaluator
        $threshold = $null
        $severity = 'na'
        $msg = 'Not collected'
        $observed = $null

        if ($WhatIf) {
            $results += New-Result -id $id -name $name -severity 'na' -message 'WhatIf: SQL not executed'
            continue
        }

        if (-not (Get-Command -Name Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
            $results += New-Result -id $id -name $name -severity 'error' -message 'Invoke-Sqlcmd not available. Install SqlServer module or configure alternate execution.'
            continue
        }

        if (-not (Test-Path -Path $file -PathType Leaf)) {
            $results += New-Result -id $id -name $name -severity 'error' -message "SQL file not found: $file"
            continue
        }

        try {
            $sqlText = Get-Content -LiteralPath $file -Raw -Encoding UTF8

            $exec = {
                param($authParams)
                if ($authParams -and $authParams.ContainsKey('AccessToken')) {
                    Invoke-Sqlcmd -ServerInstance $serverInstance -Query $sqlText -QueryTimeout $QueryTimeoutSeconds -ErrorAction Stop -AccessToken $authParams.AccessToken
                } else {
                    Invoke-Sqlcmd -ServerInstance $serverInstance -Query $sqlText -QueryTimeout $QueryTimeoutSeconds -ErrorAction Stop
                }
            }

            $rows = $null
            switch ($authMode.ToLowerInvariant()) {
                'windows' { $rows = & $exec @{} }
                'aad'     { $rows = & $exec (Get-SqlAuthParams -Config $Config -Mode 'aad') }
                default {
                    # auto: try windows first, then AAD
                    try { $rows = & $exec @{} }
                    catch {
                        try { $rows = & $exec (Get-SqlAuthParams -Config $Config -Mode 'aad') }
                        catch { throw }
                    }
                }
            }
            $rowCount = if ($rows) { ($rows | Measure-Object).Count } else { 0 }

            switch ($eval.type) {
                'scalar-threshold' {
                    $col = [string]$eval.column
                    $op  = [string]$eval.operator
                    $warn = [double]$eval.warn
                    $crit = [double]$eval.crit
                    $unit = [string]$eval.unit
                    $threshold = [pscustomobject]@{ warn = $warn; crit = $crit; operator = $op; unit = $unit }
                    if ($rowCount -gt 0 -and $rows[0].PSObject.Properties[$col]) {
                        $observed = [double]$rows[0].$col
                        switch ($op) {
                            'GreaterThan' { if ($observed -ge $crit) { $severity='crit' } elseif ($observed -ge $warn) { $severity='warn' } else { $severity='ok' } }
                            'LessThan'    { if ($observed -le $crit) { $severity='crit' } elseif ($observed -le $warn) { $severity='warn' } else { $severity='ok' } }
                            default       { if ($observed -ge $crit) { $severity='crit' } elseif ($observed -ge $warn) { $severity='warn' } else { $severity='ok' } }
                        }
                        $msg = "Observed $observed$([string]::IsNullOrEmpty($unit) ? '' : " $unit")"
                    } else {
                        $severity = 'na'
                        $msg = 'No rows or missing column'
                    }
                }
                'rows-exist' {
                    $threshold = [pscustomobject]@{ type='rows-exist' }
                    if ($rowCount -gt 0) { $severity='crit'; $msg = "Rows returned: $rowCount" } else { $severity='ok'; $msg = 'No rows' }
                }
                default { $severity = 'error'; $msg = "Unknown evaluator type: $($eval.type)" }
            }
        }
        catch {
            $severity = 'error'
            $msg = $_.Exception.Message
        }

        $results += New-Result -id $id -name $name -severity $severity -message $msg -observed $observed -threshold $threshold
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
        $defs = @($Config.Defaults.sqlServer.scriptChecks)
        if (-not $defs -or $defs.Count -eq 0) { return @() }
        $overrides = $null
        if ($Resource.thresholdOverrides -and $Resource.thresholdOverrides.scriptChecks) {
            $overrides = $Resource.thresholdOverrides.scriptChecks
        }

        $resolved = @()
        foreach ($d in $defs) {
            if (-not $d) { continue }
            $o = $null
            if ($overrides) {
                foreach ($p in $overrides.PSObject.Properties) {
                    if ($p.Name -eq $d.id) { $o = $p.Value; break }
                }
            }
            $item = [pscustomobject]@{
                id        = $d.id
                name      = $d.name
                file      = $d.file
                enabled   = [bool]$d.enabled
                evaluator = $d.evaluator | ConvertTo-Json -Depth 32 | ConvertFrom-Json
            }
            if ($o) {
                foreach ($prop in 'enabled','file','evaluator') {
                    if ($null -ne $o.$prop) { $item.$prop = $o.$prop }
                }
            }
            if ($item.enabled) { $resolved += $item }
        }

        if ($resolved.Count -eq 0) { return @() }
        $queryTimeout = 60
        if ($Config.Defaults.sqlServer.connection -and $Config.Defaults.sqlServer.connection.queryTimeoutSeconds) {
            $queryTimeout = [int]$Config.Defaults.sqlServer.connection.queryTimeoutSeconds
        }
        return Test-SqlScriptChecks -Resource $Resource -ScriptDefs $resolved -Config $Config -QueryTimeoutSeconds $queryTimeout -WhatIf:$WhatIf.IsPresent
    }
    return ,([pscustomobject]@{ ResourceType='SqlServer'; Id='sql.scripts'; Invoke=$invoke })
}

Export-ModuleMember -Function Test-SqlScriptChecks, Get-HealthCheckSpec
