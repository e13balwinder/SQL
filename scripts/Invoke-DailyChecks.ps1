[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Config,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutDir,

    [Parameter()]
    [string]$Subscriptions, # optional subscriptions filter JSON

    [switch]$ListResources, # list included resources after filters, do not run checks

    [switch]$DiscoverAzure, # discover Azure VMs by Azure tags in subscriptions JSON

    [switch]$SkipChecks # v1: show config-only report when set
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path $repoRoot 'modules/Common/Get-HealthCheckConfig.psm1') -Force | Out-Null
Import-Module (Join-Path $repoRoot 'modules/Common/Invoke-HealthChecks.psm1') -Force | Out-Null
Import-Module (Join-Path $repoRoot 'modules/Common/Discover-AzureResources.psm1') -Force | Out-Null

$cfg = Get-HealthCheckConfig -Path $Config

# Local helpers to load subscriptions config and compute filtered resource set
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
function Get-ResourceDisplayName {
    param([pscustomobject]$Resource)
    $type = [string]$Resource.type
    if ($type -eq 'SqlServer') {
        if ($Resource.identifier.instance -and $Resource.identifier.instance -ne 'MSSQLSERVER') { return "{0}\\{1}" -f $Resource.identifier.server, $Resource.identifier.instance }
        else { return "{0},{1}" -f $Resource.identifier.server, $Resource.identifier.port }
    } elseif ($type -eq 'AzureVM') { return [string]$Resource.identifier.name }
    else { return [string]$Resource.id }
}

$subsCfg = Load-SubscriptionsConfig -path $Subscriptions

# Normalize resources to an array for reliable counting/enumeration
$cfgResources = @()
if ($null -ne $cfg.Resources) {
    if ($cfg.Resources -is [System.Array]) { $cfgResources = $cfg.Resources }
    else { $cfgResources = @($cfg.Resources) }
}

$targetResources = @()
foreach ($r in $cfgResources) {
    if (Resource-PassesFilters $r $subsCfg) { $targetResources += $r }
}

$discovered = @()
if ($DiscoverAzure) {
    if (-not $subsCfg) { throw 'Discovery requires -Subscriptions pointing to a subscriptions JSON.' }
    Write-Host 'Discovering Azure VMs via subscriptions/tags...' -ForegroundColor Cyan
    $discovered = Get-AzureVmResourcesFromFilter -SubscriptionsConfig $subsCfg
}

if ($ListResources) {
    $includedCount = ($targetResources | Measure-Object).Count
    $discCount = ($discovered | Measure-Object).Count
    Write-Host "Included resources after filters: $includedCount (config)" -ForegroundColor Cyan
    if ($DiscoverAzure) { Write-Host "Discovered resources: $discCount (Azure)" -ForegroundColor Cyan }
    $byType = @()
    if ($includedCount -gt 0) { $byType = $targetResources | Group-Object -Property type }
    foreach ($g in $byType) { Write-Host ("  {0}: {1}" -f $g.Name, $g.Count) }
    foreach ($r in $targetResources) {
        $name = Get-ResourceDisplayName -Resource $r
        Write-Host ("- {0} | {1} | sub={2} | tags=[{3}]" -f $name, $r.type, $r.subscriptionId, ($r.tags -join ','))
    }
    foreach ($r in $discovered) {
        $name = Get-ResourceDisplayName -Resource $r
        Write-Host ("- {0} | {1} | sub={2} | rg={3} (discovered)" -f $name, $r.type, $r.subscriptionId, $r.resourceGroup)
    }
    exit 0
}

$results = @()
if (-not $SkipChecks) {
    # Collect Azure VM metrics and SQL checks
    $allResources = @($targetResources + $discovered)
    if ($Subscriptions) {
        $results = Invoke-HealthChecks -Config $Config -IncludeVmMetrics -SubscriptionsConfigPath $Subscriptions -Resources $allResources
    } else {
        $results = Invoke-HealthChecks -Config $Config -IncludeVmMetrics -Resources $allResources
    }
}

& (Join-Path $PSScriptRoot 'Render-Report.ps1') -Config $Config -OutDir $OutDir -Results $results

Write-Host "Report generated in: $OutDir" -ForegroundColor Green
