Param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Uninstall")]
    [String]$Mode
)

#region Config
$Features = @("VirtualMachinePlatform", "Microsoft-Hyper-V-All")
$Client = "MCC"
$LogPath = "$env:ProgramData\$Client\logs"
$LogFile = "$LogPath\FeatureManagement.log"
#endregion

# Ensure log directory exists
if (!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

$RestartNeeded = $false

foreach ($Feature in $Features) {
    switch ($Mode) {
        "Install" {
            Write-Output "Installing $Feature..." | Tee-Object -FilePath $LogFile -Append
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $Feature -All -NoRestart -ErrorAction SilentlyContinue
        }
        "Uninstall" {
            Write-Output "Uninstalling $Feature..." | Tee-Object -FilePath $LogFile -Append
            $result = Disable-WindowsOptionalFeature -Online -FeatureName $Feature -NoRestart -ErrorAction SilentlyContinue
        }
    }

    if ($result.RestartNeeded) {
        $RestartNeeded = $true
    }

    Write-Output "$Feature - RestartNeeded: $($result.RestartNeeded)" | Tee-Object -FilePath $LogFile -Append
}

Write-Output "Overall RestartNeeded: $RestartNeeded" | Tee-Object -FilePath $LogFile -Append
# Exit code 1641 indicates restart required
if ($RestartNeeded) {
    [System.Environment]::Exit(1641)
} else {
    [System.Environment]::Exit(0)
}
