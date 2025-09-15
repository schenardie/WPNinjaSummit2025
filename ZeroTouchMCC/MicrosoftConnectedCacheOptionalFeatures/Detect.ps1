$vmPlatform = Get-WmiObject -Class Win32_OptionalFeature | Where-Object { $_.Name -eq "VirtualMachinePlatform" -and $_.InstallState -eq 1 }
$hyperV = Get-WmiObject -Class Win32_OptionalFeature | Where-Object { $_.Name -eq "Microsoft-Hyper-V-All" -and $_.InstallState -eq 1 }
if ($vmPlatform -and $hyperV) {$True}