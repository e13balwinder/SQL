Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Config,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutDir,

    [Parameter()]
    [AllowNull()]
    [object[]]$Results,

    [switch]$WhatIf
)

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$assetsDir = Join-Path $repoRoot 'assets'
$templatePath = Join-Path $assetsDir 'report-template.html'
$cssPath = Join-Path $assetsDir 'report.css'

Import-Module (Join-Path $repoRoot 'modules/Common/Get-HealthCheckConfig.psm1') -Force | Out-Null
$cfg = Get-HealthCheckConfig -Path $Config

if (-not (Test-Path -Path $templatePath -PathType Leaf)) {
    throw "Template not found: $templatePath"
}

$template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8

# Build resource rows from config. v1 shows configured checks, not live statuses.
$sqlDefaults = $cfg.Defaults.sqlServer.checks
$vmMetricDefaults = $cfg.Defaults.azureVm.metricChecks | Where-Object { $_.enabled -eq $true }

function Get-ResourceDisplayName {
    param([pscustomobject]$Resource)
    $type = [string]$Resource.type
    if ($type -eq 'SqlServer') {
        if ($Resource.identifier.instance -and $Resource.identifier.instance -ne 'MSSQLSERVER') {
            return "{0}\\{1}" -f $Resource.identifier.server, $Resource.identifier.instance
        } else {
            return "{0},{1}" -f $Resource.identifier.server, $Resource.identifier.port
        }
    } elseif ($type -eq 'AzureVM') {
        return [string]$Resource.identifier.name
    } else { return [string]$Resource.id }
}

function New-ResourceRowHtml {
    param(
        [Parameter(Mandatory)][pscustomobject]$Resource,
        [Parameter()][AllowNull()][object[]]$AllResults
    )

    $type = [string]$Resource.type
    $name = Get-ResourceDisplayName -Resource $Resource

    $resResults = @()
    if ($AllResults) { $resResults = @($AllResults | Where-Object { $_.ResourceId -eq $Resource.id }) }

    if ($type -eq 'SqlServer') {
        $checks = ($sqlDefaults.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
    }
    elseif ($type -eq 'AzureVM') {
        if ($resResults.Count -gt 0) {
            $checks = ($resResults | ForEach-Object { $_.DisplayName } | Sort-Object -Unique) -join ', '
        } else {
            $checks = ($vmMetricDefaults | ForEach-Object { $_.name }) -join ', '
            if (-not $checks) { $checks = 'No metrics enabled' }
        }
    }
    else { $checks = 'N/A' }

    $status = '<span class="status na">Not collected</span>'
    if ($resResults.Count -gt 0) {
        $crit = ($resResults | Where-Object { $_.Severity -eq 'crit' } | Measure-Object).Count
        $warn = ($resResults | Where-Object { $_.Severity -eq 'warn' } | Measure-Object).Count
        $err  = ($resResults | Where-Object { $_.Severity -eq 'error' } | Measure-Object).Count
        $ok   = ($resResults | Where-Object { $_.Severity -eq 'ok' } | Measure-Object).Count
        if ($crit -gt 0) { $status = "<span class=\"status crit\">Critical ($crit)</span>" }
        elseif ($err -gt 0) { $status = "<span class=\"status crit\">Error ($err)</span>" }
        elseif ($warn -gt 0) { $status = "<span class=\"status warn\">Warning ($warn)</span>" }
        elseif ($ok -gt 0) { $status = "<span class=\"status ok\">OK ($ok)</span>" }
        else { $status = '<span class="status na">No data</span>' }
    }
    @"
    <tr>
      <td><div>$name</div><div class="muted">$($Resource.id)</div></td>
      <td>$type</td>
      <td>$checks</td>
      <td>$status</td>
    </tr>
"@
}

# Build combined resource list: config resources + any new resources present in Results
$cfgResources = @()
if ($null -ne $cfg.Resources) {
    if ($cfg.Resources -is [System.Array]) { $cfgResources = $cfg.Resources } else { $cfgResources = @($cfg.Resources) }
}

function New-ResourceFromResult {
    param([pscustomobject]$r)
    $id = [string]$r.ResourceId
    $type = [string]$r.ResourceType
    $identifier = $null
    if ($type -eq 'AzureVM') {
        $name = $id
        if ($id -match '/virtualMachines/([^/]+)') { $name = $Matches[1] }
        $identifier = [pscustomobject]@{ name = $name; resourceId = $id }
    } else {
        $identifier = [pscustomobject]@{ name = $id }
    }
    [pscustomobject]@{ id = $id; type = $type; identifier = $identifier; tags=@() }
}

$map = @{}
foreach ($r in $cfgResources) { $map[[string]$r.id] = $r }
foreach ($rr in @($Results)) {
    if (-not $rr) { continue }
    $rid = [string]$rr.ResourceId
    if (-not $rid) { continue }
    if (-not $map.ContainsKey($rid)) { $map[$rid] = New-ResourceFromResult -r $rr }
}
$allResources = $map.GetEnumerator() | ForEach-Object { $_.Value }

$rows = @()
foreach ($res in $allResources) {
    $rows += New-ResourceRowHtml -Resource $res -AllResults $Results
}

$resourceCount = ($cfg.Resources | Measure-Object).Count
$sqlCount = ($cfg.Resources | Where-Object { $_.type -eq 'SqlServer' } | Measure-Object).Count
$vmCount = ($cfg.Resources | Where-Object { $_.type -eq 'AzureVM' } | Measure-Object).Count

$html = $template
$html = $html.Replace('{{generatedAt}}', (Get-Date).ToString('u'))
$html = $html.Replace('{{schemaVersion}}', [string]$cfg.SchemaVersion)
$html = $html.Replace('{{owner}}', [string]$cfg.Metadata.owner)
$html = $html.Replace('{{description}}', [string]$cfg.Metadata.description)
$html = $html.Replace('{{resourceCount}}', [string]$resourceCount)
$html = $html.Replace('{{sqlCount}}', [string]$sqlCount)
$html = $html.Replace('{{vmCount}}', [string]$vmCount)
$html = $html.Replace('<!-- RESOURCES_TABLE_ROWS -->', ($rows -join "`n"))

# Build findings sections
function New-FindingsSectionHtml {
    param(
        [Parameter(Mandatory)][pscustomobject]$Resource,
        [Parameter()][AllowNull()][object[]]$AllResults
    )
    $resResults = @()
    if ($AllResults) { $resResults = @($AllResults | Where-Object { $_.ResourceId -eq $Resource.id }) }
    if ($resResults.Count -eq 0) { return '' }
    $name = Get-ResourceDisplayName -Resource $Resource
    $rows = foreach ($r in $resResults) {
        $sev = [string]$r.Severity
        $obs = if ($null -ne $r.Observed) { [string]$r.Observed } else { '-' }
        $th = '-'
        if ($r.Threshold) {
            if ($r.Threshold.warn -or $r.Threshold.crit) {
                $op = if ($r.Threshold.operator) { $r.Threshold.operator } else { '' }
                $unit = if ($r.Threshold.unit) { " $($r.Threshold.unit)" } else { '' }
                $th = "$op warn=$($r.Threshold.warn) crit=$($r.Threshold.crit)$unit"
            } else {
                $th = ($r.Threshold | ConvertTo-Json -Compress -Depth 5)
            }
        }
        @"
        <tr>
          <td>$([System.Net.WebUtility]::HtmlEncode($r.DisplayName))</td>
          <td class="status $sev">$sev</td>
          <td>$obs</td>
          <td><code>$th</code></td>
          <td>$([System.Net.WebUtility]::HtmlEncode([string]$r.Message))</td>
        </tr>
"@
    }
    @"
    <h3>$([System.Net.WebUtility]::HtmlEncode($name))</h3>
    <table>
      <thead>
        <tr><th>Check</th><th>Severity</th><th>Observed</th><th>Threshold</th><th>Message</th></tr>
      </thead>
      <tbody>
        $($rows -join "`n")
      </tbody>
    </table>
"@
}

$findingsSections = @()
foreach ($res in $allResources) {
    $sec = New-FindingsSectionHtml -Resource $res -AllResults $Results
    if ($sec) { $findingsSections += $sec }
}
$html = $html.Replace('<!-- FINDINGS_SECTIONS -->', ($findingsSections -join "`n`n"))

if (-not (Test-Path -Path $OutDir -PathType Container)) {
    if ($WhatIf) {
        Write-Host "[WhatIf] Would create directory: $OutDir"
    } else {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
}

$outHtml = Join-Path $OutDir 'report.html'
$outCss = Join-Path $OutDir 'report.css'

if ($WhatIf) {
    Write-Host "[WhatIf] Would write: $outHtml"
    if (Test-Path -Path $cssPath -PathType Leaf) {
        Write-Host "[WhatIf] Would copy CSS: $cssPath -> $outCss"
    }
} else {
    $html | Set-Content -LiteralPath $outHtml -Encoding UTF8
    if (Test-Path -Path $cssPath -PathType Leaf) {
        Copy-Item -LiteralPath $cssPath -Destination $outCss -Force
    }
}

Write-Host "Report generated: $outHtml"
