[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Subscriptions,

    [Parameter()]
    [string]$OutJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Load-Json {
    param([string]$Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) { throw "File not found: $Path" }
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

function TagFilter-ToEvaluator {
    param($filter)
    $obj = [pscustomobject]@{ any=@(); all=@() }
    if ($filter) {
        if ($filter.anyOf) { $obj.any = @($filter.anyOf) }
        if ($filter.allOf) { $obj.all = @($filter.allOf) }
    }
    return $obj
}

function Test-TagMatch {
    param([hashtable]$vmTags, [pscustomobject]$eval)
    if (-not $eval) { return $true }
    $any = @($eval.any); $all = @($eval.all)
    if ($any.Count -gt 0) {
        $ok=$false
        foreach ($e in $any) {
            if (-not $e) { continue }
            if ($e -match '=') { $kv=$e -split '=',2; $k=$kv[0].Trim(); $v=$kv[1].Trim(); if ($vmTags.ContainsKey($k) -and [string]$vmTags[$k] -match [regex]::Escape($v)) { $ok=$true; break } }
            else { if ($vmTags.ContainsKey($e.Trim())) { $ok=$true; break } }
        }
        if (-not $ok) { return $false }
    }
    if ($all.Count -gt 0) {
        foreach ($e in $all) {
            if (-not $e) { continue }
            if ($e -match '=') { $kv=$e -split '=',2; $k=$kv[0].Trim(); $v=$kv[1].Trim(); if (-not ($vmTags.ContainsKey($k) -and [string]$vmTags[$k] -match [regex]::Escape($v))) { return $false } }
            else { if (-not $vmTags.ContainsKey($e.Trim())) { return $false } }
        }
    }
    return $true
}

$subsCfg = Load-Json -Path $Subscriptions
Ensure-AzureLogin

$subs = @($subsCfg.subscriptions | Where-Object { $_.include -ne $false })
if ($subs.Count -eq 0) { throw 'No subscriptions defined (or include=false). Provide at least one subscriptionId.' }

$discovered = @()
$validated = @()

foreach ($s in $subs) {
    $sid = [string]$s.subscriptionId
    try {
        $sub = Get-AzSubscription -SubscriptionId $sid -ErrorAction Stop
        Select-AzSubscription -SubscriptionId $sid -ErrorAction Stop | Out-Null
        $validated += [pscustomobject]@{ subscriptionId=$sid; name=$sub.Name; reachable=$true; message='OK' }
    }
    catch {
        $validated += [pscustomobject]@{ subscriptionId=$sid; name=$null; reachable=$false; message=$_.Exception.Message }
        continue
    }

    $eval = TagFilter-ToEvaluator -filter $subsCfg.global.azureTagFilter
    if ($s.azureTagFilter) {
        # Merge sub-specific filters
        $subEval = TagFilter-ToEvaluator -filter $s.azureTagFilter
        $eval = [pscustomobject]@{ any = @($eval.any + $subEval.any); all = @($eval.all + $subEval.all) }
    }

    if (-not (Get-Command -Name Get-AzVM -ErrorAction SilentlyContinue)) {
        throw 'Az.Compute module is required. Install-Module Az -Scope CurrentUser'
    }
    $vms = Get-AzVM -Status -ErrorAction Stop
    foreach ($vm in $vms) {
        $tags = @{}
        if ($vm.Tags) { $tags = $vm.Tags }
        if (-not (Test-TagMatch -vmTags $tags -eval $eval)) { continue }
        $discovered += [pscustomobject]@{
            id             = [string]$vm.Id
            type           = 'AzureVM'
            identifier     = [pscustomobject]@{ name = [string]$vm.Name; resourceId = [string]$vm.Id }
            subscriptionId = [string]$sid
            resourceGroup  = [string]$vm.ResourceGroupName
        }
    }
}

Write-Host ("Validated {0}/{1} subscription(s)." -f (@($validated | Where-Object { $_.reachable }).Count), ($validated | Measure-Object).Count) -ForegroundColor Green
$bySub = $discovered | Group-Object -Property subscriptionId
foreach ($g in $bySub) {
    $name = ($validated | Where-Object { $_.subscriptionId -eq $g.Name } | Select-Object -First 1).name
    Write-Host ("  {0} ({1}): {2} VM(s)" -f ($name ? $name : $g.Name), $g.Name, $g.Count)
}

if (-not $OutJson) {
    $outDir = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'out'
    if (-not (Test-Path -Path $outDir -PathType Container)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $OutJson = Join-Path $outDir 'discovered-resources.json'
}

([pscustomobject]@{ discoveredAt=(Get-Date).ToString('u'); subscriptionsValidated=$validated; vms=$discovered }) |
  ConvertTo-Json -Depth 6 |
  Set-Content -LiteralPath $OutJson -Encoding UTF8

Write-Host ("Saved discovery output to: {0}" -f $OutJson) -ForegroundColor Green
