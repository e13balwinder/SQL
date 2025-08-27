Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SqlAuthParams {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter()][string]$Mode
    )

    $authCfg = $Config.Defaults.sqlServer.auth
    if (-not $Mode) { $Mode = if ($authCfg.mode) { [string]$authCfg.mode } else { 'auto' } }
    $Mode = $Mode.ToLowerInvariant()

    switch ($Mode) {
        'windows' { return @{} }
        'aad'     { return (Get-AadTokenParams -Config $Config) }
        default   { return @{} }
    }
}

function Get-AadTokenParams {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][pscustomobject]$Config
    )
    $tenantId = $Config.Defaults.sqlServer.auth.tenantId
    $resourceUrl = if ($Config.Defaults.sqlServer.auth.resourceUrl) { [string]$Config.Defaults.sqlServer.auth.resourceUrl } else { 'https://database.windows.net/' }

    if (-not (Get-Command -Name Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        throw 'Get-AzAccessToken not available. Install Az.Accounts to use AAD tokens.'
    }
    $params = @{ ResourceUrl = $resourceUrl }
    if ($tenantId) { $params.TenantId = [string]$tenantId }
    $tok = Get-AzAccessToken @params
    if (-not $tok -or -not $tok.Token) { throw 'Failed to acquire Azure AD access token.' }
    return @{ AccessToken = $tok.Token }
}

Export-ModuleMember -Function Get-SqlAuthParams, Get-AadTokenParams

