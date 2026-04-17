#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Bulk-creates Active Directory users from a CSV file.

.DESCRIPTION
    Reads user data from CompleteUsers.csv in the script directory, creates AD accounts,
    and assigns group memberships. Prompts interactively when a username conflict is found.

.NOTES
    CSV must contain columns:
    username, password, firstname, lastname, email, location, streetaddress, city,
    zipcode, state, country, telephone, jobtitle, company, department, awsregion,
    passwordchange, crc, waypoint, rpm, yendo, DUO
#>

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string] $CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$Domain        = 'example.com'
$HomeServer    = '\\192.168.1.5\home$'
$HomeDrive     = 'H:'
$LogonScript   = 'logon.bat'
$OuTemplate    = 'OU=Users,OU={0},OU=Locations,OU=CRC,DC=example,DC=com'

# Map location codes to display names used in the OU path.
# Add or remove entries here without touching any other code.
$LocationMap = Get-Content -Path "$PSScriptRoot\LocationCodes.json" | ConvertFrom-Json

# AD groups that are gated by a CSV column (column name → AD group name).
# The 'Agents' group is always applied and is handled separately.
$ConditionalGroups = Get-Content -Path "$PSScriptRoot\GroupCodes.json" | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Assert-RunAsAdministrator {
    <#
    .SYNOPSIS Restarts the script elevated if not already running as admin, preserving all arguments. #>
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        # Escape each argument so values with spaces or special characters survive the re-launch
        $escapedArgs = $script:MyInvocation.BoundParameters.GetEnumerator() | ForEach-Object {
            if ($_.Value -is [switch]) {
                if ($_.Value) { "-$($_.Key)" }
            } else {
                "-$($_.Key) `"$($_.Value -replace '"', '\"')`""
            }
        }
        $argString = "& '$($script:MyInvocation.MyCommand.Path)' $($escapedArgs -join ' ')"
 
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo 'PowerShell'
        $startInfo.Arguments = $argString
        $startInfo.Verb = 'runas'
        [System.Diagnostics.Process]::Start($startInfo) | Out-Null
        exit
    }
    Write-Host 'Running with Administrator privileges.' -ForegroundColor Green
}

function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a yes/no answer and returns $true for yes, $false for no.
    .PARAMETER Prompt
        The prompt string shown to the user (do not include [Y/n]).
    .PARAMETER Default
        The value returned when the user presses Enter without typing anything.
    #>
    param(
        [Parameter(Mandatory)] [string]  $Prompt,
        [bool] $Default = $true
    )

    $defaultLabel = if ($Default) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        $raw = Read-Host "$Prompt $defaultLabel"
        if ($raw -eq '') { return $Default }
        if ($raw -match '^y(es)?$') { return $true  }
        if ($raw -match '^no?$')    { return $false }
        Write-Warning 'Invalid selection — please enter Y or N.'
    }
}

function Add-UserToGroups {
    <#
    .SYNOPSIS Adds a user to the 'Agents' group and any conditional groups flagged in the CSV. #>
    param(
        [Parameter(Mandatory)] [string]    $SamAccountName,
        [Parameter(Mandatory)] [hashtable] $GroupFlags   # column-name → 'y'/'n' value from CSV
    )

    # Always add to the base group
    Add-ADGroupMember -Identity 'Agents' -Members $SamAccountName

    foreach ($column in $ConditionalGroups.Keys) {
        if (-not $GroupFlags.ContainsKey($column)) {
            Write-Warning "CSV is missing expected column '$column' for conditional group membership. Skipping group assignment for '$($ConditionalGroups[$column])'."
            continue
        }
        if ($GroupFlags[$column] -match '^y(es)?$') {
            Add-ADGroupMember -Identity $ConditionalGroups[$column] -Members $SamAccountName
        }
    }
}

function Get-UniqueSamAccountName {
    <#
    .SYNOPSIS
        Returns the first available SamAccountName by appending an incrementing integer
        to the base name while keeping the result within AD's 20-character limit.
    #>
    param([Parameter(Mandatory)] [string] $BaseName)

    $counter = 1
    while ($true) {
        $suffix    = "$counter"
        $maxBase   = 20 - $suffix.Length
        $candidate = if ($BaseName.Length -gt $maxBase) {
            $BaseName.Substring(0, $maxBase) + $suffix
        } else {
            $BaseName + $suffix
        }

        if (-not (Get-ADUser -Filter { SamAccountName -eq $candidate } -ErrorAction SilentlyContinue)) {
            return $candidate
        }
        $counter++
    }
}

function New-DomainUser {
    <#
    .SYNOPSIS Thin wrapper around New-ADUser with all site-standard parameters. #>
    param(
        [Parameter(Mandatory)] [string] $SamAccountName,
        [Parameter(Mandatory)] [string] $DisplayName,
        [Parameter(Mandatory)] [string] $GivenName,
        [Parameter(Mandatory)] [string] $Surname,
        [Parameter(Mandatory)] [string] $OU,
        [Parameter(Mandatory)] [string] $Password,
        [Parameter(Mandatory)] [bool]   $ChangePasswordAtLogon,
        [string] $City, [string] $Company, [string] $State,
        [string] $StreetAddress, [string] $Telephone, [string] $Email,
        [string] $JobTitle, [string] $Department, [string] $Country
    )    

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    New-ADUser `
        -SamAccountName        $SamAccountName `
        -UserPrincipalName     "$SamAccountName@$Domain" `
        -Name                  $DisplayName `
        -GivenName             $GivenName `
        -Surname               $Surname `
        -DisplayName           $DisplayName `
        -Path                  $OU `
        -City                  $City `
        -Company               $Company `
        -State                 $State `
        -StreetAddress         $StreetAddress `
        -OfficePhone           $Telephone `
        -EmailAddress          $Email `
        -Title                 $JobTitle `
        -Department            $Department `
        -ScriptPath            $LogonScript `
        -HomeDirectory         "$HomeServer\$SamAccountName" `
        -HomeDrive             $HomeDrive `
        -Country               $Country

    Set-ADAccountPassword -Identity $SamAccountName -Reset -NewPassword $securePassword
    Set-ADUser -Identity $SamAccountName `
        -Enabled               $true `
        -ChangePasswordAtLogon $ChangePasswordAtLogon
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Assert-RunAsAdministrator
Import-Module ActiveDirectory

$users = Import-Csv $CsvPath

foreach ($user in $users) {

    # --- Resolve location code -----------------------------------------------
    $locationCode = $user.location
    if (-not $LocationMap.ContainsKey($locationCode)) {
        Write-Warning "Unknown location code '$locationCode' for user '$($user.username)' - skipping."
        continue
    }
    if (-not $user.PSObject.Properties['city'] -or -not $user.PSObject.Properties['state'] -or -not $user.PSObject.Properties['country']) {
        # If city/state/country are not provided in the CSV, attempt to fill them in based on the location code.
        $address = $LocationMap[$locationCode]
        if ($address) {
            $city    = $address.City
            $state   = $address.State
            $country = $address.Country
        }
        else {
            Write-Warning "No address mapping found for location code '$locationCode' - leaving city/state/country blank for user '$($user.username)'."
            $city = $state = $country = ''
        }
    }
    else {
        $city    = $user.city
        $state   = $user.state
        $country = $user.country
    }

    $locationDisplay = $LocationMap[$locationCode].OUPart
    $ou              = $OuTemplate -f $locationDisplay

    # --- Field extraction (optional fields default to empty string) ----------
    $samName            = $user.username.Trim()
    $password           = $user.password
    $firstName          = $user.firstname.Trim()
    $lastName           = $user.lastname.Trim()
    $email              = if ($user.PSObject.Properties['email'])         { $user.email          } else { '' }
    $streetAddress      = if ($user.PSObject.Properties['streetaddress']) { $user.streetaddress  } else { '' }
    $telephone          = if ($user.PSObject.Properties['telephone'])     { $user.telephone      } else { '' }
    $jobTitle           = if ($user.PSObject.Properties['jobtitle'])      { $user.jobtitle       } else { '' }
    $company            = if ($user.PSObject.Properties['company'])       { $user.company        } else { '' }
    $department         = if ($user.PSObject.Properties['department'])    { $user.department     } else { '' }
    $forcePasswordReset = ($user.passwordchange -match '^y(es)?$')

    $email = if ($user.PSObject.Properties['email']) { $user.email } else { '' }
    $emailPattern = '^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$'
    if ($email -and ($email -notmatch $emailPattern)) {
        Write-Warning "Invalid email address '$email' for user '$samName' - removing email."
        $email = ''
    }
    $invalidChars = '[\/\\\[\]:;\|=,\+\*\?<>\s]'
    if ($samName.Length -gt 20 -or $samName -match $invalidChars) {
        Write-Warning "Username '$samName' is invalid (too long or contains forbidden characters) - skipping."
        continue
    }

    $groupFlags = @{}
    foreach ($col in $ConditionalGroups.Keys) { $groupFlags[$col] = $user.$col }

    # --- Check for existing account ------------------------------------------
    $existingUser = Get-ADUser -Filter { SamAccountName -eq $samName } -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-Warning "User '$samName' already exists in Active Directory."

        # Option 1: reset the password on the existing account
        $resetPassword = Read-YesNo -Prompt "Reset password to '$password'?" -Default $true

        if ($resetPassword) {
            Set-ADAccountPassword -Identity $samName -Reset `
                -NewPassword (ConvertTo-SecureString $password -AsPlainText -Force)
            Set-ADUser -Identity $samName -ChangePasswordAtLogon $forcePasswordReset
            Write-Host "Password reset for '$samName'." -ForegroundColor Cyan
            Add-UserToGroups -SamAccountName $samName -GroupFlags $groupFlags
            continue
        }

        # Option 2: create a new account with an incremented username
        $newSamName = Get-UniqueSamAccountName -BaseName $samName
        $increment  = ($newSamName -replace '^.*?(\d+)$', '$1')   # extract the numeric suffix
        $rename     = Read-YesNo -Prompt "Increment username to '$newSamName'?" -Default $true

        if (-not $rename) {
            Write-Host "Skipping '$samName'." -ForegroundColor Yellow
            continue
        }

        $samName    = $newSamName
        $displayName = "$firstName $lastName $increment"
    }
    else {
        $displayName = "$firstName $lastName"
    }

    # --- Create the account ---------------------------------------------------
    try{
        New-DomainUser `
            -SamAccountName        $samName `
            -DisplayName           $displayName `
            -GivenName             $firstName `
            -Surname               $lastName `
            -OU                    $ou `
            -Password              $password `
            -ChangePasswordAtLogon $forcePasswordReset `
            -City                  $city `
            -Company               $company `
            -State                 $state `
            -StreetAddress         $streetAddress `
            -Telephone             $telephone `
            -Email                 $email `
            -JobTitle              $jobTitle `
            -Department            $department `
            -Country               $country
    }
    catch {
        Write-Error "Failed to create user '$samName': $_"
        continue
    }
    Write-Host "Created user '$samName'." -ForegroundColor Green
    Add-UserToGroups -SamAccountName $samName -GroupFlags $groupFlags
}