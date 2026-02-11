function Install-MSIFromURL {
    param (
        [string]$AppName,
        [string]$Url,
        [string]$Arguments = ""
    )
    
    $AppTempPath = "$ENV:TEMP\$AppName.msi"
    
    if (Get-ChildItem HKLM:\SOFTWARE\$_\Microsoft\Windows\CurrentVersion\Uninstall\ | ? {($_.GetValue("DisplayName")) -like "*$AppName*"} ) {
        Write-Output "$AppName is already installed, skipping."
        return
    } else {
        Write-Output "Downloading $AppName."
        C:\Windows\System32\curl.exe -Lso $AppTempPath $Url
        if($LASTEXITCODE -ne 0){
            Write-Error "Failed to download $AppName. [$LASTEXITCODE]"
            return
        }
    }
    
    Write-Output "Installing $AppName."
    $process = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i $AppTempPath /qn $Arguments"
    
    if ($process.ExitCode -eq 0) {
        Write-Output "$AppName installed. Cleaning up."
        Remove-Item $AppTempPath
        Write-Output "Completed."
    } else {
        Write-Error "Install failed. [$($process.ExitCode)]"
    }
}
