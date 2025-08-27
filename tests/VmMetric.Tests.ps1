Import-Module "$PSScriptRoot/../modules/Checks/Test-AzVmMetric.psm1" -Force

Describe 'Test-AzVmMetric' {
    It 'returns warn/crit based on thresholds (mocked)' {
        $resource = [pscustomobject]@{ id='vm1'; type='AzureVM'; identifier=[pscustomobject]@{ resourceId='/subs/..../rg/..../providers/Microsoft.Compute/virtualMachines/vm1' } }
        $def = [pscustomobject]@{ id='vm.cpu'; name='Percentage CPU'; namespace='Microsoft.Compute/virtualMachines'; enabled=$true; aggregation='Average'; operator='GreaterThan'; warn=50; crit=80; windowMinutes=5; granularityMinutes=1; treatNoDataAs='Ignore' }

        Mock -CommandName Get-AzMetric -MockWith {
            # Return a shape similar to Az.Monitor with Data containing Average
            [pscustomobject]@{ 
                Unit='Percent';
                Timeseries=@(
                    [pscustomobject]@{ Data = @(
                        [pscustomobject]@{ Timestamp=(Get-Date).AddMinutes(-4); Average=30 },
                        [pscustomobject]@{ Timestamp=(Get-Date).AddMinutes(-3); Average=55 },
                        [pscustomobject]@{ Timestamp=(Get-Date).AddMinutes(-2); Average=85 }
                    ) }
                )
            }
        }

        $r = Test-AzVmMetric -Resource $resource -MetricDefs @($def)
        ($r | Where-Object { $_.CheckId -eq 'vm.cpu' }).Severity | Should -Be 'crit'
    }

    It 'marks na when no datapoints and treatNoDataAs Ignore' {
        $resource = [pscustomobject]@{ id='vm1'; type='AzureVM'; identifier=[pscustomobject]@{ resourceId='/subs/x/rg/y/providers/Microsoft.Compute/virtualMachines/vm1' } }
        $def = [pscustomobject]@{ id='vm.cpu'; name='Percentage CPU'; namespace='Microsoft.Compute/virtualMachines'; enabled=$true; aggregation='Average'; operator='GreaterThan'; warn=50; crit=80; windowMinutes=5; granularityMinutes=1; treatNoDataAs='Ignore' }

        Mock -CommandName Get-AzMetric -MockWith { [pscustomobject]@{ Unit='Percent'; Timeseries=@() } }
        $r = Test-AzVmMetric -Resource $resource -MetricDefs @($def)
        ($r | Where-Object { $_.CheckId -eq 'vm.cpu' }).Severity | Should -Be 'na'
    }
}
