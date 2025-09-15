try {
    $appname = 'Windows Subsystem for Linux';
    $output = 'Detected';
    $Newversion = [System.Version]'X.X.X';
    $Currentversion = ((Get-Package -Name $appname -ErrorAction SilentlyContinue).version)
    if ($Currentversion.count -gt 1 ) {
        if ([System.Version]$Currentversion[0] -ge $Newversion) {
            return $output
        }
    }
    else {
        if ([System.Version]$Currentversion -ge $Newversion) {
            return $output
        }
    }
}
catch { exit }