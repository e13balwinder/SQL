Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-HealthChecks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Config,

        [switch]$IncludeVmMetrics,
        [Parameter()]
        [string]$SubscriptionsConfigPath,

        [Parameter()]
        [object[]]$Resources,

        [switch]$WhatIf
    )

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Common/Get-HealthCheckConfig.psm1') -Force | Out-Null
    $cfg = Get-HealthCheckConfig -Path $Config

    # Discover check specs from modules under modules/Checks that expose Get-HealthCheckSpec
    $checksPath = Join-Path $repoRoot 'Checks'
    Get-ChildItem -Path $checksPath -Filter '*.psm1' -File | ForEach-Object {
        Import-Module $_.FullName -Force -ErrorAction Stop | Out-Null
    }

    $specs = @()
    foreach ($m in (Get-Module | Where-Object { $_.Path -and $_.Path -like (Join-Path $checksPath '*') })) {
        $getter = Get-Command -Module $m.Name -Name Get-HealthCheckSpec -ErrorAction SilentlyContinue
        if ($getter) {
            try { $specs += & $getter } catch { Write-Verbose "Spec load failed in $($m.Name): $($_.Exception.Message)" }
        }
    }

    # Optional filter for VM metrics
    if (-not $IncludeVmMetrics) {
        $specs = $specs | Where-Object { $_.ResourceType -ne 'AzureVM' }
    }

    # Load optional subscriptions filter config and filter resources
    function Load-SubscriptionsConfig($path) {
        if (-not $path) { return $null }
        if (-not (Test-Path -Path $path -PathType Leaf)) { throw "Subscriptions config not found: $path" }
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            $cfj = Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($cfj -and $cfj.Parameters.ContainsKey('Depth')) { $raw | ConvertFrom-Json -Depth 64 }
            else { $raw | ConvertFrom-Json }
        }
        catch { throw "Failed to parse subscriptions JSON '$path': $($_.Exception.Message)" }
    }
    function Resource-PassesFilters($resource, $subsCfg) {
        if (-not $subsCfg) { return $true }
        $allowedSubs = @($subsCfg.subscriptions | Where-Object { $_.include -ne $false })
        if ($allowedSubs.Count -gt 0) {
            $match = $false
            foreach ($s in $allowedSubs) { if ([string]$resource.subscriptionId -eq [string]$s.subscriptionId) { $match = $true; break } }
            if (-not $match) { return $false }
        }
        $resTags = @($resource.tags)
        $globalInclude = @($subsCfg.global.includeTags)
        $globalExclude = @($subsCfg.global.excludeTags)
        $subEntry = $null
        foreach ($s in $subsCfg.subscriptions) { if ([string]$resource.subscriptionId -eq [string]$s.subscriptionId) { $subEntry = $s; break } }
        $include = @($globalInclude + @($subEntry.includeTags)) | Where-Object { $_ }
        $exclude = @($globalExclude + @($subEntry.excludeTags)) | Where-Object { $_ }
        if ($exclude.Count -gt 0 -and $resTags) {
            foreach ($t in $exclude) { if ($resTags -contains $t) { return $false } }
        }
        if ($include.Count -gt 0) {
            if (-not $resTags) { return $false }
            $any = $false
            foreach ($t in $include) { if ($resTags -contains $t) { $any = $true; break } }
            if (-not $any) { return $false }
        }
        return $true
    }

    $subsCfg = Load-SubscriptionsConfig -path $SubscriptionsConfigPath
    $targetResources = @()
    if ($PSBoundParameters.ContainsKey('Resources') -and $Resources) {
        $targetResources = @($Resources)
    } else {
        $cfgResources = @()
        if ($null -ne $cfg.Resources) {
            if ($cfg.Resources -is [System.Array]) { $cfgResources = $cfg.Resources } else { $cfgResources = @($cfg.Resources) }
        }
        foreach ($r in $cfgResources) { if (Resource-PassesFilters $r $subsCfg) { $targetResources += $r } }
    }

    $results = @()
    foreach ($res in $targetResources) {
        $matching = $specs | Where-Object { $_.ResourceType -eq $res.type }
        foreach ($spec in $matching) {
            try {
                $inv = $spec.Invoke
                if ($inv -is [scriptblock]) {
                    $results += & $inv -Resource $res -Config $cfg -WhatIf:$WhatIf.IsPresent
                }
            }
            catch {
                $results += [pscustomobject]@{
                    ResourceId   = $res.id
                    ResourceType = $res.type
                    CheckId      = [string]$spec.Id
                    DisplayName  = "Check failed"
                    Severity     = 'error'
                    Observed     = $null
                    Threshold    = $null
                    Message      = $_.Exception.Message
                    TimeRange    = $null
                }
            }
        }
    }

    return ,$results
}

Export-ModuleMember -Function Invoke-HealthChecks
