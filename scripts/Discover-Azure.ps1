[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Subscriptions,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutJson,

    [switch]$VerboseOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path $repoRoot 'modules/Common/Discover-AzureResources.psm1') -Force | Out-Null

function Load-SubscriptionsConfig {
    param([string]$Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) { throw "Subscriptions config not found: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $cfj = Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($cfj -and $cfj.Parameters.ContainsKey('Depth')) { return ($raw | ConvertFrom-Json -Depth 64) }
    else { return ($raw | ConvertFrom-Json) }
}

function Ensure-AzureLogin {
    if (-not (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)) {
        throw 'Az.Accounts module is required. Install-Module Az -Scope CurrentUser'
    }
    $ctx = $null
    try { $ctx = Get-AzContext -ErrorAction Stop } catch { $ctx = $null }
    if (-not $ctx -or -not $ctx.Account) {
        Write-Host 'Connecting to Azure...' -ForegroundColor Cyan
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }
}

function Validate-Subscriptions {
    param([pscustomobject]$SubsCfg)
    $subs = @($SubsCfg.subscriptions | Where-Object { $_.include -ne $false })
    if ($subs.Count -eq 0) { throw 'No subscriptions listed in subscriptions JSON (or include=false). Add at least one subscriptionId.' }
    $results = @()
    foreach ($s in $subs) {
        $sid = [string]$s.subscriptionId
        try {
            $sub = Get-AzSubscription -SubscriptionId $sid -ErrorAction Stop
            Select-AzSubscription -SubscriptionId $sid -ErrorAction Stop | Out-Null
            $results += [pscustomobject]@{ subscriptionId=$sid; name=$sub.Name; reachable=$true; message='OK' }
        }
        catch {
            $results += [pscustomobject]@{ subscriptionId=$sid; name=$null; reachable=$false; message=$_.Exception.Message }
        }
    }
    return ,$results
}

if (-not $OutJson) {
    $outDir = Join-Path $repoRoot 'out'
    if (-not (Test-Path -Path $outDir -PathType Container)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $OutJson = Join-Path $outDir 'discovered-resources.json'
}

$subsCfg = Load-SubscriptionsConfig -Path $Subscriptions
Ensure-AzureLogin

$validation = Validate-Subscriptions -SubsCfg $subsCfg
$okSubs = @($validation | Where-Object { $_.reachable })
if ($okSubs.Count -eq 0) {
    Write-Host 'No accessible subscriptions. Please verify access and try again.' -ForegroundColor Red
    $validation | Format-Table -AutoSize | Out-String | Write-Host
    exit 2
}

Write-Host ("Validated {0}/{1} subscription(s)." -f $okSubs.Count, ($validation | Measure-Object).Count) -ForegroundColor Green
if ($VerboseOutput) { $validation | Format-Table -AutoSize | Out-String | Write-Host }

Write-Host 'Discovering Azure VMs by subscriptions/tags...' -ForegroundColor Cyan
$discovered = Get-AzureVmResourcesFromFilter -SubscriptionsConfig $subsCfg

$bySub = $discovered | Group-Object -Property subscriptionId
foreach ($g in $bySub) {
    $name = ($validation | Where-Object { $_.subscriptionId -eq $g.Name } | Select-Object -First 1).name
    Write-Host ("  {0} ({1}): {2} VM(s)" -f ($name ? $name : $g.Name), $g.Name, $g.Count)
}

$outObj = [pscustomobject]@{
    discoveredAt = (Get-Date).ToString('u')
    subscriptionsValidated = $validation
    vms = $discovered
}
$outObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutJson -Encoding UTF8
Write-Host ("Saved discovery output to: {0}" -f $OutJson) -ForegroundColor Green

