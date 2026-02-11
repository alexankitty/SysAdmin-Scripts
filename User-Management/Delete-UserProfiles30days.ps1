## Source: https://www.elevenforum.com/t/user-profile-issue-modified-date-incorrect.28854/
$excludes = @("Administrator", "ets")

@(Get-CimInstance -Namespace 'root\cimv2' -ClassName 'Win32_UserProfile' -Filter '(Special = ''False'') AND (Loaded = ''False'')' |
ForEach-Object {
    [string]$profileSID = $_.SID

    $profile = [PSCustomObject]@{
        SID = $profileSID
        LastUseTime = [DateTime]::MaxValue
    }

    $identifier = New-Object System.Security.Principal.SecurityIdentifier($profileSID) ## Has to be across two lines otherwise it fails.
    try{
        $userName = $identifier.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    }
    catch{
        Write-Warning "Could not translate SID: $profileSID. Using SID as username instead."
        $userName = "deleted_user_$($profileSID)"
    }    

    if ($null -eq (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($_.SID)" -Name @('LocalProfileLoadTimeHigh', 'LocalProfileLoadTimeLow', 'LocalProfileUnloadTimeHigh', 'LocalProfileUnloadTimeLow') -ErrorAction SilentlyContinue))
    {
        $profile.LastUseTime = [DateTime]::new(1970,1,1,0,0,0)
    }
    else
    {
        Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($_.SID)" -Name @('LocalProfileLoadTimeHigh', 'LocalProfileLoadTimeLow', 'LocalProfileUnloadTimeHigh', 'LocalProfileUnloadTimeLow') -ErrorAction SilentlyContinue |
        ForEach-Object {
            [DateTime]$loadTime = [DateTime]::new(1980,1,1,0,0,0)
            if (([bool]$_.PSObject.Properties['LocalProfileLoadTimeLow']) -and ([bool]$_.PSObject.Properties['LocalProfileLoadTimeHigh']))
            {
                [System.UInt64]$highTime = $_.LocalProfileLoadTimeHigh
                [System.UInt64]$lowTime = $_.LocalProfileLoadTimeLow
                $highTime = $highTime -shl 32
                [DateTime]$loadTime = [DateTime]::FromFileTime($highTime -bor $lowTime)
            }

            [DateTime]$unloadTime = [DateTime]::new(1980,1,1,0,0,0)
            if (([bool]$_.PSObject.Properties['LocalProfileUnloadTimeLow']) -and ([bool]$_.PSObject.Properties['LocalProfileUnloadTimeHigh']))
            {
                [System.UInt64]$highTime = $_.LocalProfileUnloadTimeHigh
                [System.UInt64]$lowTime = $_.LocalProfileUnloadTimeLow
                $highTime = $highTime -shl 32
                $unloadTime = [DateTime]::FromFileTime($highTime -bor $lowTime)
            }

            $profile.LastUseTime = [DateTime]::FromFileTime(([Math]::Max($loadTime.ToFileTime(), $unloadTime.ToFileTime())))
        }
    }
    $date30DaysAgo = (Get-Date).AddDays(-30)
    Write-Host "Processing profile: $userName with SID: $profileSID and Last Use Time: $($profile.LastUseTime) < $date30DaysAgo"
    if($profile.LastUseTime -lt $date30DaysAgo)
    {
        if($excludes -contains $userName)
        {
            Write-Host "Skipping excluded user profile: $userName"
        }
        else {
            Remove-CimInstance -InputObject $_
            Write-Host "Deleted user profile: $($userName)"
        }
    }
})