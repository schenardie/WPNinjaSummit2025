<#
.SYNOPSIS
    Script that initiates MCC Self Deployng on Intune
 
.NOTES
    Author: Jose Schenardie
    Contact: @schenardie
    Website: https://www.msendpointmgr.com
#>


param(
	[Parameter(Mandatory = $true)][string]$installationFolder,
	[Parameter(Mandatory = $true)][string]$cacheDrives,
	[Parameter(Mandatory = $true)][string]$customerId,
	[Parameter(Mandatory = $true)][string]$cacheNodeId,
	[Parameter(Mandatory = $true)][string]$customerKey,
	[Parameter(Mandatory = $true)][string]$registrationKey,
	[Parameter(Mandatory = $false)][pscredential]$mccLocalAccountCredential,
	[Parameter(Mandatory = $false)][int]$mccPublicPort = 80,
	[Parameter(Mandatory = $false)][string]$mccLocalAccountUser,
	[Parameter(Mandatory = $false)][string]$mccLocalAccountPassword
)

# Helper function for timestamped logging
function Log-Message {
	param([string]$Message)
	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	Write-Host "[$timestamp] $Message"
}

#Logging Function
    $Pname = "MicrosoftConnectedCacheBootstrap"
    $Pversion = "1.0"
    $client = "MCC"
    $logPath = "$env:ProgramData\$client\logs"
    $logFile = "$logPath\$PName" + "_" + "$Pversion" + "_Install.log"
#endregion
    if (!(Test-Path -Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -Force | Out-Null
    }

    Start-Transcript -Path $logFile -Force 
#Create credential object for local account
$User = "$env:COMPUTERNAME\$mccLocalAccountUser"

#Add account to local administrators group if not yet
if (-not (net localgroup Administrators | Select-String -Pattern $mccLocalAccountUser)) { 
	Log-Message "Adding $($mccLocalAccountUser) to local admins" 
	net localgroup Administrators $mccLocalAccountUser /add 
}
else { 
	Log-Message "$($mccLocalAccountUser) is already member of local admins"
}

#Define Working directory for scheduled Task
$WorkingDir = (Get-ChildItem "C:\program files\WindowsApps" -directory | Where-Object {$_.Name -like "Microsoft.DeliveryOptimization*"} | select-Object -First 1).Fullname + "\deliveryoptimization-cli\"

# Create action for scheduled Task
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -Command `" & '.\deploymcconwsl.ps1' -installationFolder $installationFolder -customerid $customerId -cachenodeid $cacheNodeId -customerkey $customerKey -registrationkey $registrationKey -cacheDrives '$($cacheDrives)' -mccRunTimeAccount $User -mccLocalAccountCredential (New-Object System.Management.Automation.PSCredential('$($User)', (ConvertTo-SecureString '$($mccLocalAccountPassword)' -AsPlainText -Force)))`"" -WorkingDirectory $WorkingDir

# Create principal for scheduled Task
$Principal = New-ScheduledTaskPrincipal -userID $User -LogonType Password -RunLevel Highest

# Create task for scheduled Task
$Task = New-ScheduledTask -Action $Action -Principal $Principal

# Create a task name for the scheduled Task
$DeployWSLTaskName = "MCC_DeployWSL"

# Register scheduled task
Log-Message "Registering scheduled task $DeployWSLTaskName"
Register-ScheduledTask -TaskName $DeployWSLTaskName -InputObject $Task -User $User -Password $mccLocalAccountPassword -Force

# Start scheduled Task
Log-Message "Starting scheduled task $DeployWSLTaskName"
schtasks /run /tn $DeployWSLTaskName /i

# Add 5 seconds wait
Log-Message "Waiting 5 seconds for task to initialize"
Start-Sleep 5

$timeoutMinutes = 15
$startTime = Get-Date
Log-Message "Monitoring $DeployWSLTaskName for completion (timeout: $timeoutMinutes minutes)..."
do {
	$taskInstance = Get-ScheduledTaskInfo -TaskName $DeployWSLTaskName
	Start-Sleep -Seconds 30

	$elapsed = (Get-Date) - $startTime
	Log-Message "$([math]::Floor($elapsed.TotalMinutes)) minutes elapsed, still waiting for $DeployWSLTaskName to complete..."
	if ($elapsed.TotalMinutes -ge $timeoutMinutes) {
		Log-Message "Timeout reached for $DeployWSLTaskName. Exiting with code 1."
		exit 1
	}
} while ($taskInstance.LastTaskResult -eq 267009 -or $taskInstance.LastTaskResult -eq 0)

Log-Message "$DeployWSLTaskName completed with result: $($taskInstance.LastTaskResult)"

#Update Install task to fix broken paths
$taskName = "MCC_Install_Task"
Log-Message "Updating paths for $taskName"

# Get original task
$task = Get-ScheduledTask -TaskName $taskName
$action = $task.Actions[0]
$trigger = $task.Triggers[0]
$principal = $task.Principal

# Extract the StartIn path
$startInPath = "'" + ($task.Actions | Where-Object { $_.Execute -like "*powershell*" }).WorkingDirectory + "'"
$WorkingDirectory = ($task.Actions | Where-Object { $_.Execute -like "*powershell*" }).WorkingDirectory

# Build updated command with StartIn path substitution
$originalArguments = $action.Arguments
$updatedArguments = $originalArguments -replace '"\."', "$startInPath"

# Also update relative paths like .\filename to full path
$updatedArguments = $updatedArguments -replace '\.\\', "$WorkingDirectory\"

# Build new action
$newAction = New-ScheduledTaskAction -Execute $action.Execute -Argument $updatedArguments -WorkingDirectory $WorkingDirectory

# Re-register the task using its original components
Log-Message "Re-registering $taskName with updated paths"
Register-ScheduledTask -TaskName $taskName -Action $newAction -Trigger $trigger -User $User -Password $mccLocalAccountPassword -Force

#Update Monitor task to fix broken paths
$taskName = "MCC_Monitor_Task"
Log-Message "Updating paths for $taskName"

# Get original task
$task = Get-ScheduledTask -TaskName $taskName
$action = $task.Actions[0]
$trigger = $task.Triggers[0]
$principal = $task.Principal

# Extract the StartIn path
$startInPath = "'" + ($task.Actions | Where-Object { $_.Execute -like "*powershell*" }).WorkingDirectory + "'"
$WorkingDirectory = ($task.Actions | Where-Object { $_.Execute -like "*powershell*" }).WorkingDirectory

# Build updated command with StartIn path substitution
$originalArguments = $action.Arguments
$updatedArguments = $originalArguments -replace '"\."', "$startInPath"

# Also update relative paths like .\filename to full path
$updatedArguments = $updatedArguments -replace '\.\\', "$WorkingDirectory\"

# Build new action
$newAction = New-ScheduledTaskAction -Execute $action.Execute -Argument $updatedArguments -WorkingDirectory $WorkingDirectory

# Re-register the task using its original components
Log-Message "Re-registering $taskName with updated paths"
Register-ScheduledTask -TaskName $taskName -Action $newAction -Trigger $trigger -User $User -Password $mccLocalAccountPassword -Force

# Check for MCC_Install_Task and start it if queued
$MCCInstallTaskName = "MCC_Install_Task"
try {
	$MCCInstallTaskStatus = (Get-ScheduledTask -TaskName $MCCInstallTaskName -ErrorAction Stop).State
	if ($MCCInstallTaskStatus -eq 'Ready' -or $MCCInstallTaskStatus -eq 'Queued') {
		Log-Message "Starting $MCCInstallTaskName task..."		
		$maxRetries = 5
		$retryCount = 0
		$taskStatus = (Get-ScheduledTask -TaskName $MCCInstallTaskName).State

		while ($taskStatus -ne 'Running' -and $retryCount -lt $maxRetries) {
			Log-Message "Task $MCCInstallTaskName is not running, retrying in 30 seconds... (Attempt $($retryCount + 1) of $maxRetries)"
			Start-Sleep -Seconds 30
			schtasks /run /tn $MCCInstallTaskName /i
			$taskStatus = (Get-ScheduledTask -TaskName $MCCInstallTaskName).State
			$retryCount++
		}

		# Monitor MCC_Install_Task for 45 minutes
		$timeoutMinutes = 45
		$startTime = Get-Date
		Log-Message "Monitoring $MCCInstallTaskName for completion (timeout: $timeoutMinutes minutes)..."
		do {
			$taskStatus = (Get-ScheduledTask -TaskName $MCCInstallTaskName).State
			$installTaskInstance = Get-ScheduledTaskInfo -TaskName $MCCInstallTaskName
			Start-Sleep -Seconds 60
			
			$elapsed = (Get-Date) - $startTime
			Log-Message "$([math]::Floor($elapsed.TotalMinutes)) minutes elapsed, task state: $taskStatus, result: $($installTaskInstance.LastTaskResult)"
			
			if ($taskStatus -ne "Running") {
			Log-Message "$MCCInstallTaskName is no longer running (state: $taskStatus). Exiting monitoring loop."
			break
			}
			
			if ($elapsed.TotalMinutes -ge $timeoutMinutes) {
			Log-Message "Timeout reached for $MCCInstallTaskName. Continuing..."
			break
			}
		} while ($true)
		
		Log-Message "$MCCInstallTaskName completed with result: $($installTaskInstance.LastTaskResult)"
	}
	else {
		Log-Message "$MCCInstallTaskName is in state: $MCCInstallTaskStatus. Not starting."
	}
} catch {
	Log-Message "$MCCInstallTaskName task not found or not accessible."
}

# Check for MCC_Monitor_Task and start it if queued
$MCCMonitorTaskName = "MCC_Monitor_Task"
try {
	$MCCMonitorTaskStatus = (Get-ScheduledTask -TaskName $MCCMonitorTaskName -ErrorAction Stop).State
	if ($MCCMonitorTaskStatus -eq 'Ready' -or $MCCMonitorTaskStatus -eq 'Queued') {
		Log-Message "Starting $MCCMonitorTaskName task..."
		schtasks /run /tn $MCCMonitorTaskName /i
	}
	else {
		Log-Message "$MCCMonitorTaskName is in state: $MCCMonitorTaskStatus. Not starting."
	}
} catch {
	Log-Message "$MCCMonitorTaskName task not found or not accessible."
}

# De-register the task
Log-Message "Removing $DeployWSLTaskName scheduled task..."
Unregister-ScheduledTask -TaskName $DeployWSLTaskName -Confirm:$false

# Remove account from local admins
Log-Message "Removing $mccLocalAccountUser from local administrators group"
net localgroup Administrators $mccLocalAccountUser /delete

# Add port forwarding if missing
if (!(netsh interface portproxy show v4tov4))
{
	Log-Message "Port forwarding not found, adding required port mappings"
	$ipFilePath = Join-Path ([System.Environment]::GetEnvironmentVariable("MCC_INSTALLATION_FOLDER", "Machine")) "wslIp.txt"
	
	$ipAddress = (Get-Content $ipFilePath | Select-Object -First 1).Trim()
	Log-Message "Using WSL IP address: $ipAddress"
	
	Log-Message "Adding port forwarding for port 80"
	netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=80 connectaddress=$ipAddress
	
	Log-Message "Adding port forwarding for port 5000"
	netsh interface portproxy add v4tov4 listenport=5000 listenaddress=0.0.0.0 connectport=5000 connectaddress=$ipAddress
}
else {
	Log-Message "Port forwarding already configured"
}

# Add firewall rules if missing
if (-not (Get-NetFirewallRule -DisplayName "WSL2 Port Bridge (MCC SUMMARY)" -ErrorAction SilentlyContinue)) { 
	Log-Message "Adding firewall rule for port 5000 (Terse Summary page)"
	New-NetFirewallRule -DisplayName "WSL2 Port Bridge (MCC SUMMARY)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5000 
	Log-Message "Firewall rule added successfully"
}
else {
	Log-Message "Firewall rule already exists for Terse Summary page"
}

Log-Message "Script completed successfully..."
Stop-Transcript