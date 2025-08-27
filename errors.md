PS C:\Users\bsingh\Downloads\Archive\scripts> .\Invoke-DailyChecks.ps1 -Config config\health-check-config.json -Subscriptions config\subscriptions.json -OutDir out -ListResources

Security warning
Run only scripts that you trust. While scripts from the internet can be useful, this script can
potentially harm your computer. If you trust this script, use the Unblock-File cmdlet to allow the
script to run without this warning message. Do you want to run
C:\Users\bsingh\Downloads\Archive\scripts\Invoke-DailyChecks.ps1?
[D] Do not run  [R] Run once  [S] Suspend  [?] Help (default is "D"): r

Security warning
Run only scripts that you trust. While scripts from the internet can be useful, this script can
potentially harm your computer. If you trust this script, use the Unblock-File cmdlet to allow the
script to run without this warning message. Do you want to run
C:\Users\bsingh\Downloads\Archive\modules\Common\Get-HealthCheckConfig.psm1?
[D] Do not run  [R] Run once  [S] Suspend  [?] Help (default is "D"): r

Security warning
Run only scripts that you trust. While scripts from the internet can be useful, this script can
potentially harm your computer. If you trust this script, use the Unblock-File cmdlet to allow the
script to run without this warning message. Do you want to run
C:\Users\bsingh\Downloads\Archive\modules\Common\Invoke-HealthChecks.psm1?
[D] Do not run  [R] Run once  [S] Suspend  [?] Help (default is "D"): r
Config file not found: config\health-check-config.json
At C:\Users\bsingh\Downloads\Archive\modules\Common\Get-HealthCheckConfig.psm1:13 char:9
+         throw "Config file not found: $Path"
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (Config file not...eck-config.json:String) [], Runti
   meException
    + FullyQualifiedErrorId : Config file not found: config\health-check-config.json
