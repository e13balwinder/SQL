Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzureVmResourcesFromFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$SubscriptionsConfig
    )

    $results = @()
    $subs = @($SubscriptionsConfig.subscriptions | Where-Object { $_.include -ne $false })
    $subIds = @($subs | ForEach-Object { [string]$_.subscriptionId } | Where-Object { $_ })
    if ($subIds.Count -eq 0) {
        Write-Verbose 'No subscriptions listed in subscriptions config.'
        return @()
    }

    # Ensure Azure context
    if (-not (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)) {
        throw 'Az.Accounts module is required. Install-Module Az -Scope CurrentUser'
    }
    $ctx = $null
    try { $ctx = Get-AzContext -ErrorAction Stop } catch { $ctx = $null }
    if (-not $ctx -or -not $ctx.Account) {
        Write-Verbose 'No Azure context. Prompting for Connect-AzAccount...'
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }

    # Tag filter builder
    function New-TagFilterObject {
        param($global, $sub)
        $g = if ($global -and $global.azureTagFilter) { $global.azureTagFilter } else { $null }
        $s = if ($sub -and $sub.azureTagFilter) { $sub.azureTagFilter } else { $null }
        [pscustomobject]@{
            anyOf = @()
            allOf = @()
        } | ForEach-Object {
            if ($g) {
                if ($g.anyOf) { $_.anyOf += @($g.anyOf) }
                if ($g.allOf) { $_.allOf += @($g.allOf) }
            }
            if ($s) {
                if ($s.anyOf) { $_.anyOf += @($s.anyOf) }
                if ($s.allOf) { $_.allOf += @($s.allOf) }
            }
            $_
        }
    }

    function Build-KqlFromTagFilter {
        param([pscustomobject]$filter)
        if (-not $filter -or ((@($filter.anyOf).Count -eq 0) -and (@($filter.allOf).Count -eq 0))) { return '' }
        $anyConds = @()
        foreach ($e in @($filter.anyOf)) {
            if (-not $e) { continue }
            if ($e -match '=') {
                $kv = $e -split '=',2
                $k = $kv[0].Trim()
                $v = $kv[1].Trim()
                $anyConds += "tostring(tags['$k']) =~ '$v'"
            } else {
                $k = $e.Trim()
                $anyConds += "isnotempty(tostring(tags['$k']))"
            }
        }
        $allConds = @()
        foreach ($e in @($filter.allOf)) {
            if (-not $e) { continue }
            if ($e -match '=') {
                $kv = $e -split '=',2
                $k = $kv[0].Trim()
                $v = $kv[1].Trim()
                $allConds += "tostring(tags['$k']) =~ '$v'"
            } else {
                $k = $e.Trim()
                $allConds += "isnotempty(tostring(tags['$k']))"
            }
        }
        $clauses = @()
        if ($anyConds.Count -gt 0) { $clauses += '(' + ($anyConds -join ' or ') + ')' }
        if ($allConds.Count -gt 0) { $clauses += '(' + ($allConds -join ' and ') + ')' }
        if ($clauses.Count -eq 0) { return '' }
        return $clauses -join ' and '
    }

    $global = $SubscriptionsConfig.global
    $hasRG = Get-Command -Name Search-AzGraph -ErrorAction SilentlyContinue
    if ($hasRG) {
        Write-Verbose 'Using Azure Resource Graph for discovery.'
        $kqlBase = @()
        $kqlBase += "resources"
        $kqlBase += "| where type =~ 'microsoft.compute/virtualmachines'"
        $kqlBase += "| project id, name, resourceGroup, subscriptionId, tags"
        $kqlBase = $kqlBase -join "\n"

        $query = $kqlBase
        # We'll filter in KQL using a combined global+subscription filter per VM later; since ARG doesn't support per-sub different filters in one query, use global here; sub-specific filters applied client-side.
        if ($global -and $global.azureTagFilter) {
            $where = Build-KqlFromTagFilter -filter $global.azureTagFilter
            if ($where) { $query = $kqlBase + "\n| where " + $where }
        }
        $skip = $null
        $page = 0
        do {
            $page += 1
            $args = @{ Subscription = $subIds; Query = $query; First = 1000 }
            if ($skip) { $args.SkipToken = $skip }
            $resp = Search-AzGraph @args
            foreach ($row in $resp.Data) {
                # Apply per-sub filters client-side
                $subEntry = $subs | Where-Object { [string]$_.subscriptionId -eq [string]$row.subscriptionId } | Select-Object -First 1
                $combined = New-TagFilterObject -global $global -sub $subEntry
                $ok = $true
                # Client-side tag validation when we have any/allOf
                $vmTags = @{}
                if ($row.tags) { $vmTags = $row.tags }
                function Tag-Matches($vmTags, $flt) {
                    if (-not $flt) { return $true }
                    $any = @($flt.anyOf)
                    $all = @($flt.allOf)
                    if ($any.Count -gt 0) {
                        $matches = $false
                        foreach ($e in $any) {
                            if (-not $e) { continue }
                            if ($e -match '=') {
                                $kv = $e -split '=',2; $k=$kv[0].Trim(); $v=$kv[1].Trim()
                                if ($vmTags.ContainsKey($k) -and [string]$vmTags[$k] -match [regex]::Escape($v)) { $matches=$true; break }
                            } else { if ($vmTags.ContainsKey($e.Trim())) { $matches=$true; break } }
                        }
                        if (-not $matches) { return $false }
                    }
                    if ($all.Count -gt 0) {
                        foreach ($e in $all) {
                            if (-not $e) { continue }
                            if ($e -match '=') {
                                $kv = $e -split '=',2; $k=$kv[0].Trim(); $v=$kv[1].Trim()
                                if (-not ($vmTags.ContainsKey($k) -and [string]$vmTags[$k] -match [regex]::Escape($v))) { return $false }
                            } else { if (-not $vmTags.ContainsKey($e.Trim())) { return $false } }
                        }
                    }
                    return $true
                }
                $ok = Tag-Matches -vmTags $vmTags -flt $combined
                if (-not $ok) { continue }

                $results += [pscustomobject]@{
                    id            = [string]$row.id
                    type          = 'AzureVM'
                    identifier    = [pscustomobject]@{ name = [string]$row.name; resourceId = [string]$row.id }
                    subscriptionId= [string]$row.subscriptionId
                    resourceGroup = [string]$row.resourceGroup
                    tags          = @()
                }
            }
            $skip = $resp.SkipToken
        } while ($skip)
    }
    else {
        Write-Verbose 'Azure Resource Graph not available. Falling back to Get-AzVM.'
        if (-not (Get-Command -Name Get-AzVM -ErrorAction SilentlyContinue)) {
            throw 'Az.Compute module required for fallback discovery. Install-Module Az -Scope CurrentUser'
        }
        function Tag-MatchesLocal($vm, $filter) {
            if (-not $filter) { return $true }
            $vmTags = $vm.Tags
            if (-not $vmTags) { return $false }
            $any = @($filter.anyOf); $all=@($filter.allOf)
            if ($any.Count -gt 0) {
                $match=$false
                foreach ($e in $any) {
                    if (-not $e) { continue }
                    if ($e -match '=') { $kv=$e -split '=',2; $k=$kv[0].Trim(); $v=$kv[1].Trim(); if ($vmTags.ContainsKey($k) -and [string]$vmTags[$k] -match [regex]::Escape($v)) { $match=$true; break } }
                    else { if ($vmTags.ContainsKey($e.Trim())) { $match=$true; break } }
                }
                if (-not $match) { return $false }
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
        foreach ($sid in $subIds) {
            try { Select-AzSubscription -SubscriptionId $sid -ErrorAction Stop | Out-Null } catch { throw $_ }
            $subEntry = $subs | Where-Object { [string]$_.subscriptionId -eq [string]$sid } | Select-Object -First 1
            $combined = New-TagFilterObject -global $global -sub $subEntry
            $vms = Get-AzVM -Status -ErrorAction Stop
            foreach ($vm in $vms) {
                if (-not (Tag-MatchesLocal -vm $vm -filter $combined)) { continue }
                $rid = $vm.Id
                $results += [pscustomobject]@{
                    id            = [string]$rid
                    type          = 'AzureVM'
                    identifier    = [pscustomobject]@{ name = [string]$vm.Name; resourceId = [string]$rid }
                    subscriptionId= [string]$sid
                    resourceGroup = [string]$vm.ResourceGroupName
                    tags          = @()
                }
            }
        }
    }

    return ,$results
}

Export-ModuleMember -Function Get-AzureVmResourcesFromFilter

