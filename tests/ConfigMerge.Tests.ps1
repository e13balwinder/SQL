Import-Module "$PSScriptRoot/../modules/Common/Invoke-HealthChecks.psm1" -Force

Describe 'Config merge for VM metrics' {
    It 'applies per-resource overrides for vm.cpu thresholds' {
        $cfgPath = Join-Path $PSScriptRoot '../config/health-check-config.example.json'
        $results = Invoke-HealthChecks -Config $cfgPath -IncludeVmMetrics -WhatIf
        $vmCpu = $results | Where-Object { $_.ResourceId -eq 'vm-app-01' -and $_.CheckId -eq 'vm.cpu' }
        $vmCpu | Should -Not -BeNullOrEmpty
        $vmCpu.Threshold.warn | Should -Be 65
        $vmCpu.Threshold.crit | Should -Be 85
    }
}
