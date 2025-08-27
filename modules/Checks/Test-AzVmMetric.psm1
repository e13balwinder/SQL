Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-AzVmMetric {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject]$Resource,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject[]]$MetricDefs,

        [switch]$WhatIf
    )

    # Validate resourceId presence
    $resourceId = $Resource.identifier.resourceId
    if (-not $resourceId) {
        throw "Azure VM resource missing identifier.resourceId: $($Resource | ConvertTo-Json -Depth 4)"
    }

    $now = Get-Date
    $results = @()

    foreach ($def in $MetricDefs) {
        $start = $now.AddMinutes(-[int]$def.windowMinutes)
        $end = $now
        $grain = New-TimeSpan -Minutes ([int]$def.granularityMinutes)
        $aggProp = [string]$def.aggregation

        $value = $null
        $unit = $null
        $msg = $null
        $severity = 'na'
        $operator = [string]$def.operator

        if ($WhatIf) {
            # In WhatIf mode, do not call Azure. Simulate NA with message.
            $msg = 'WhatIf: metrics not collected'
        }
        else {
            try {
                if (-not (Get-Command -Name Get-AzMetric -ErrorAction SilentlyContinue)) {
                    throw 'Get-AzMetric is not available. Install Az.Monitor.'
                }
                $m = Get-AzMetric -ResourceId $resourceId -MetricName $def.name -TimeGrain $grain -StartTime $start -EndTime $end -Aggregation $aggProp -WarningAction SilentlyContinue
                $points = @()
                if ($m -and $m.Timeseries) {
                    foreach ($ts in $m.Timeseries) { if ($ts.Data) { $points += $ts.Data } }
                }
                elseif ($m -and $m.Data) { $points = $m.Data }
                elseif ($m -and $m.MetricValues) { $points = $m.MetricValues }

                # Take the latest non-null aggregated value
                $points = @($points | Sort-Object -Property TimeStamp)
                $last = $null
                foreach ($p in ($points | Where-Object { $_.PSObject.Properties.Name -contains $aggProp -and $null -ne $_.$aggProp })) { $last = $p }
                if ($last) {
                    $value = [double]$last.$aggProp
                } else {
                    if ($def.treatNoDataAs -eq 'Zero') { $value = 0 } else { $severity = 'na'; $msg = 'No datapoints in window'; }
                }

                if ($m.Unit) { $unit = [string]$m.Unit }
            }
            catch {
                $severity = 'error'
                $msg = "Metric query failed: $($_.Exception.Message)"
            }
        }

        if ($null -ne $value -and $severity -ne 'error') {
            switch ($operator) {
                'GreaterThan' {
                    if ($value -ge $def.crit) { $severity = 'crit' }
                    elseif ($value -ge $def.warn) { $severity = 'warn' } else { $severity = 'ok' }
                }
                'LessThan' {
                    if ($value -le $def.crit) { $severity = 'crit' }
                    elseif ($value -le $def.warn) { $severity = 'warn' } else { $severity = 'ok' }
                }
                'GreaterThanOrEqual' {
                    if ($value -ge $def.crit) { $severity = 'crit' }
                    elseif ($value -ge $def.warn) { $severity = 'warn' } else { $severity = 'ok' }
                }
                'LessThanOrEqual' {
                    if ($value -le $def.crit) { $severity = 'crit' }
                    elseif ($value -le $def.warn) { $severity = 'warn' } else { $severity = 'ok' }
                }
                default {
                    # Fallback treat as GreaterThan
                    if ($value -ge $def.crit) { $severity = 'crit' }
                    elseif ($value -ge $def.warn) { $severity = 'warn' } else { $severity = 'ok' }
                }
            }
            if (-not $msg) { $msg = "Observed $value$([string]::IsNullOrEmpty($unit) ? '' : " $unit")" }
        }

        $results += [pscustomobject]@{
            ResourceId   = [string]$Resource.id
            ResourceType = [string]$Resource.type
            CheckId      = [string]$def.id
            DisplayName  = [string]$def.name
            Severity     = [string]$severity
            Observed     = $value
            Unit         = $unit
            Threshold    = [pscustomobject]@{ warn = $def.warn; crit = $def.crit; operator = $operator }
            Message      = $msg
            TimeRange    = [pscustomobject]@{ start = $start; end = $end; grainMinutes = $def.granularityMinutes }
        }
    }

    return ,$results
}

function Get-HealthCheckSpec {
    [CmdletBinding()]
    param()
    # Returns a single spec for AzureVM metrics. The engine will call .Invoke with -Resource, -Config, -WhatIf
    $invoke = {
        param(
            [Parameter(Mandatory)][pscustomobject]$Resource,
            [Parameter(Mandatory)][pscustomobject]$Config,
            [switch]$WhatIf
        )
        # Resolve defaults + per-resource overrides for metrics
        $defs = @($Config.Defaults.azureVm.metricChecks)
        $overrides = $null
        if ($Resource.thresholdOverrides -and $Resource.thresholdOverrides.metricChecks) {
            $overrides = $Resource.thresholdOverrides.metricChecks
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
                id                 = $d.id
                name               = $d.name
                namespace          = $d.namespace
                enabled            = [bool]$d.enabled
                aggregation        = $d.aggregation
                operator           = $d.operator
                warn               = $d.warn
                crit               = $d.crit
                windowMinutes      = $d.windowMinutes
                granularityMinutes = $d.granularityMinutes
                treatNoDataAs      = $d.treatNoDataAs
            }
            if ($o) {
                foreach ($prop in 'enabled','aggregation','operator','warn','crit','windowMinutes','granularityMinutes','treatNoDataAs') {
                    if ($null -ne $o.$prop) { $item.$prop = $o.$prop }
                }
            }
            if ($item.enabled) { $resolved += $item }
        }
        if ($resolved.Count -eq 0) { return @() }
        return Test-AzVmMetric -Resource $Resource -MetricDefs $resolved -WhatIf:$WhatIf.IsPresent
    }
    return ,([pscustomobject]@{ ResourceType = 'AzureVM'; Id = 'vm.metrics'; Invoke = $invoke })
}

Export-ModuleMember -Function Test-AzVmMetric, Get-HealthCheckSpec
