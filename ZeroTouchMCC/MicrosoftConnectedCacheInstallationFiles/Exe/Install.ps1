Param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Uninstall")]
    [String[]]$Mode
)

# ----------------------------------------
# Read file info: locate the MSIX bundle
# ----------------------------------------
$MSIX = (Get-ChildItem -Recurse -Path ".\*.msixbundle").FullName

# ----------------------------------------
# Retrieve MSIX properties
# ----------------------------------------

# Load .NET assembly to work with ZIP files
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Open the .msixbundle as a ZIP archive
$zip = [System.IO.Compression.ZipFile]::OpenRead($MSIX)

# Create an empty array to store package info
$packageInfoList = @()

# Find all embedded .msix or .appx packages inside the bundle
$packages = $zip.Entries | Where-Object { $_.FullName -like "*.msix" -or $_.FullName -like "*.appx" }

# Loop through each embedded package
foreach ($pkg in $packages) {
    # Open the embedded package stream
    $pkgStream = $pkg.Open()

    # Treat the embedded package as a ZIP archive
    $pkgZip = New-Object System.IO.Compression.ZipArchive($pkgStream, [System.IO.Compression.ZipArchiveMode]::Read)

    # Locate the AppxManifest.xml file inside the embedded package
    $manifestEntry = $pkgZip.Entries | Where-Object { $_.FullName -eq "AppxManifest.xml" }

    if ($manifestEntry) {
        # Read and parse the manifest XML
        $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
        [xml]$manifest = $reader.ReadToEnd()
        $reader.Close()

        # Create a custom object with Name, Version, and Publisher
        $packageInfo = [PSCustomObject]@{
            Name      = $manifest.Package.Identity.Name
            Version   = $manifest.Package.Identity.Version
            Publisher = $manifest.Package.Identity.Publisher
        }

        # Add the object to the array
        $packageInfoList += $packageInfo
    }

    # Dispose of the embedded package ZIP archive
    $pkgZip.Dispose()
}

# Dispose of the main .msixbundle ZIP archive
$zip.Dispose()

# ----------------------------------------
# Initialize ExitCode
# ----------------------------------------
$ExitCode = 0

# ----------------------------------------
# Main logic based on mode
# ----------------------------------------
switch ($Mode) {
    "Install" {
		if ($MSIX)
			{	
				# Install MSIX from local source
				Add-AppProvisionedPackage -Online -PackagePath $MSIX -SkipLicense
			}
		else 
			{
				# Install MSIX from online binaries
				Add-AppProvisionedPackage -Online -PackagePath "https://aka.ms/do-mcc-ent-windows-x64" -SkipLicense
			}
    }

    "Uninstall" {
        # Uninstall MSIX
        Get-AppxPackage -AllUsers -Name $packageInfoList.name | Remove-AppPackage -AllUsers
    }
}

# ----------------------------------------
# Exit with appropriate code
# ----------------------------------------
[System.Environment]::Exit($ExitCode)
