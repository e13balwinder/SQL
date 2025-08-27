Import-Module "$PSScriptRoot/../modules/Checks/Test-SqlScripts.psm1" -Force

Describe 'Test-SqlScriptChecks' {
    $resource = [pscustomobject]@{
        id='sql1'; type='SqlServer'; identifier=[pscustomobject]@{ server='localhost'; port=1433; instance='MSSQLSERVER' }
    }
    $configBase = [pscustomobject]@{
        Defaults = [pscustomobject]@{
            sqlServer = [pscustomobject]@{
                connection = [pscustomobject]@{ queryTimeoutSeconds = 5 }
                auth = [pscustomobject]@{ mode = 'windows' }
            }
        }
    }

    It 'returns NA in WhatIf mode without executing SQL' {
        $defs = @([pscustomobject]@{
            id='script.test'; name='Test Script'; file='sql/blocked_sessions_count.sql'; enabled=$true;
            evaluator=[pscustomobject]@{ type='scalar-threshold'; column='blocked_sessions'; operator='GreaterThan'; warn=5; crit=20 }
        })
        # Ensure Invoke-Sqlcmd would fail if called, to prove WhatIf bypasses it.
        Mock -CommandName Invoke-Sqlcmd -MockWith { throw 'should not be called in WhatIf' }
        $r = Test-SqlScriptChecks -Resource $resource -ScriptDefs $defs -Config $configBase -WhatIf
        ($r | Where-Object { $_.CheckId -eq 'script.test' }).Severity | Should -Be 'na'
    }

    It 'auto auth falls back to AAD when Windows fails' {
        $configAuto = [pscustomobject]@{
            Defaults = [pscustomobject]@{
                sqlServer = [pscustomobject]@{
                    connection = [pscustomobject]@{ queryTimeoutSeconds = 5 }
                    auth = [pscustomobject]@{ mode = 'auto'; tenantId='00000000-0000-0000-0000-000000000000'; resourceUrl='https://database.windows.net/' }
                }
            }
        }
        $defs = @([pscustomobject]@{
            id='script.test'; name='Test Script'; file='sql/blocked_sessions_count.sql'; enabled=$true;
            evaluator=[pscustomobject]@{ type='scalar-threshold'; column='blocked_sessions'; operator='GreaterThan'; warn=5; crit=20 }
        })

        # First call (Windows) should throw
        Mock -CommandName Invoke-Sqlcmd -ParameterFilter { -not $PSBoundParameters.ContainsKey('AccessToken') } -MockWith { throw 'login failed' }
        # Second call (AAD) should succeed returning a row
        Mock -CommandName Invoke-Sqlcmd -ParameterFilter { $PSBoundParameters.ContainsKey('AccessToken') } -MockWith { ,([pscustomobject]@{ blocked_sessions = 0 }) }
        Mock -CommandName Get-AzAccessToken -MockWith { [pscustomobject]@{ Token = 'dummy' } }

        $r = Test-SqlScriptChecks -Resource $resource -ScriptDefs $defs -Config $configAuto
        ($r | Where-Object { $_.CheckId -eq 'script.test' }).Severity | Should -Be 'ok'
    }
}

