Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HealthCheckConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $cfj = Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($cfj -and $cfj.Parameters.ContainsKey('Depth')) {
            $config = $raw | ConvertFrom-Json -Depth 64
        } else {
            $config = $raw | ConvertFrom-Json
        }
    }
    catch {
        throw "Failed to parse config JSON at '$Path'. Error: $($_.Exception.Message)"
    }

    if (-not $config.schemaVersion) {
        throw "Config missing 'schemaVersion'"
    }
    if (-not $config.defaults) {
        throw "Config missing 'defaults'"
    }
    if (-not $config.resources) {
        throw "Config missing 'resources'"
    }

    # Return as-is for v1; merging of overrides happens in scripts as needed.
    [pscustomobject]@{
        SchemaVersion = [string]$config.schemaVersion
        Metadata      = $config.metadata
        Defaults      = $config.defaults
        Resources     = $config.resources
        Raw           = $config
    }
}

Export-ModuleMember -Function Get-HealthCheckConfig
