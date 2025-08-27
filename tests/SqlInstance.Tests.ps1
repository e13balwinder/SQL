Import-Module "$PSScriptRoot/../modules/Checks/Test-SqlInstanceHealth.psm1" -Force

Describe 'Test-SqlInstanceHealth' {
    It 'emits NA for placeholders and ok/crit for TCP reachability (WhatIf -> NA)' {
        $res = [pscustomobject]@{ id='sql1'; type='SqlServer'; identifier=[pscustomobject]@{ server='localhost'; port=1433; instance='MSSQLSERVER' } }
        $defs = [pscustomobject]@{ instanceReachable=@{ connectTimeoutSeconds=1 }; agentRunning=@{ required=$true } }
        $r = Test-SqlInstanceHealth -Resource $res -CheckDefs $defs -ConnectTimeoutSeconds 1 -WhatIf
        ($r | Where-Object { $_.CheckId -eq 'instanceReachable' }).Severity | Should -Be 'na'
        ($r | Where-Object { $_.CheckId -eq 'agentRunning' }).Severity | Should -Be 'na'
    }
}
