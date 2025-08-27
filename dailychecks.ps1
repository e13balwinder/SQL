# Connect to Azure (will prompt for credentials)
Connect-AzAccount

# Get all subscriptions and prepare results array
$subscriptions = Get-AzSubscription
$reportItems = @()

# Define time range (last 24 hours)
$endTime = Get-Date
$startTime = $endTime.AddDays(-1)

foreach ($sub in $subscriptions) {
    # Set context to current subscription
    Set-AzContext -SubscriptionId $sub.Id

    # Get all VMs in this subscription
    $vms = Get-AzVM
    foreach ($vm in $vms) {
        $vmName = $vm.Name
        $resourceGroup = $vm.ResourceGroupName
        $resourceId = $vm.Id

        # Define metrics to retrieve
        $metrics = @{
            "Percentage CPU" = @{Agg="Average"}
            "Available Memory Percentage" = @{Agg="Average"}
            "Disk Read Bytes" = @{Agg="Total"}
            "Disk Write Bytes" = @{Agg="Total"}
            "Disk Read Operations/Sec" = @{Agg="Average"}
            "Disk Write Operations/Sec" = @{Agg="Average"}
            "Network In Total" = @{Agg="Total"}
            "Network Out Total" = @{Agg="Total"}
        }

        # Initialize values
        $cpuAvg = $cpuMin = $cpuMax = 0
        $memAvg = 0
        $diskReadTotal = $diskWriteTotal = 0
        $diskReadIOPSAvg = $diskWriteIOPSAvg = 0
        $netInTotal = $netOutTotal = 0

        # Retrieve each metric
        foreach ($metricName in $metrics.Keys) {
            $agg = $metrics[$metricName].Agg
            # Use Get-AzMetric to get the metric data
            $metricData = Get-AzMetric -ResourceId $resourceId `
                           -MetricName $metricName -StartTime $startTime -EndTime $endTime `
                           -AggregationType $agg -ErrorAction SilentlyContinue

            if ($metricData.Data) {
                # Each metric may return multiple time series; take the first for simplicity
                $data = $metricData.Data | Select-Object -First 1
                switch ($metricName) {
                    "Percentage CPU" {
                        $cpuAvg = [math]::Round($data.Average,2)
                        $cpuMin = [math]::Round($data.Minimum,2)
                        $cpuMax = [math]::Round($data.Maximum,2)
                    }
                    "Available Memory Percentage" {
                        $memAvg = [math]::Round($data.Average,2)
                    }
                    "Disk Read Bytes" {
                        $diskReadTotal = $data.Total
                    }
                    "Disk Write Bytes" {
                        $diskWriteTotal = $data.Total
                    }
                    "Disk Read Operations/Sec" {
                        $diskReadIOPSAvg = [math]::Round($data.Average,2)
                    }
                    "Disk Write Operations/Sec" {
                        $diskWriteIOPSAvg = [math]::Round($data.Average,2)
                    }
                    "Network In Total" {
                        $netInTotal = $data.Total
                    }
                    "Network Out Total" {
                        $netOutTotal = $data.Total
                    }
                }
            }
        }

        # Add the collected data for this VM to the report array
        $reportItems += [PSCustomObject]@{
            Subscription      = $sub.Name
            ResourceGroup     = $resourceGroup
            VMName            = $vmName
            CPU_AvgPercent    = $cpuAvg
            CPU_MinPercent    = $cpuMin
            CPU_MaxPercent    = $cpuMax
            Mem_AvgPercent    = $memAvg
            DiskRead_Bytes    = $diskReadTotal
            DiskWrite_Bytes   = $diskWriteTotal
            DiskRead_IOPSAvg  = $diskReadIOPSAvg
            DiskWrite_IOPSAvg = $diskWriteIOPSAvg
            NetworkIn_Bytes   = $netInTotal
            NetworkOut_Bytes  = $netOutTotal
        }
    }
}

# Generate an HTML report
$reportHtml = $reportItems | ConvertTo-Html `
    -Property Subscription, ResourceGroup, VMName, CPU_AvgPercent, CPU_MinPercent, CPU_MaxPercent, `
               Mem_AvgPercent, DiskRead_Bytes, DiskWrite_Bytes, DiskRead_IOPSAvg, DiskWrite_IOPSAvg, `
               NetworkIn_Bytes, NetworkOut_Bytes `
    -Title "Azure VM Metrics Daily Report" `
    -PreContent "<h1>Azure VM Metrics Daily Report</h1>" `
    -As Table `
    -CssUri "https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css"

# Save to file
$outFile = "C:\Temp\AzureVM_Metrics_Report.html"
$reportHtml | Out-File -FilePath $outFile -Encoding UTF8

Write-Host "Report generated: $outFile"
