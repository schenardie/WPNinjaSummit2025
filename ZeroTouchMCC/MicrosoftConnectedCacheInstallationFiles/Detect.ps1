IF (Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq "microsoft.deliveryoptimization"})
{$True}