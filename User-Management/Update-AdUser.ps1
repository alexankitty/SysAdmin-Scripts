#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Interactively pick an Organizational Unit (OU) and update the City and Country
    for every user account found directly inside that OU.

.DESCRIPTION
    1. Connects to Active Directory and retrieves all OUs.
    2. Presents a numbered list so the operator can select the target OU.
    3. Prompts for the new City and Country values.
    4. Optionally shows a preview of affected users before committing changes.
    5. Updates City (l) and Country (co / c / countryCode) for every user in the OU.
    6. Writes a summary log to the same directory as the script.

.NOTES
    - Run on a machine with the ActiveDirectory PowerShell module installed
      (RSAT: Active Directory DS Tools).
    - The account running the script must have Write permission on the user
      objects in the chosen OU.
    - Country input accepts either a full country name (e.g. "United States")
      or an ISO 3166-1 alpha-2 code (e.g. "US").  The script resolves both.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helper: map ISO-2 code <-> country name for the most common countries.
# Extend this table as needed for your environment.
# ---------------------------------------------------------------------------
$CountryTable = @(
    [PSCustomObject]@{ Name = 'Afghanistan';               Code = 'AF'; Numeric = 4   }
    [PSCustomObject]@{ Name = 'Albania';                   Code = 'AL'; Numeric = 8   }
    [PSCustomObject]@{ Name = 'Australia';                 Code = 'AU'; Numeric = 36  }
    [PSCustomObject]@{ Name = 'Austria';                   Code = 'AT'; Numeric = 40  }
    [PSCustomObject]@{ Name = 'Belgium';                   Code = 'BE'; Numeric = 56  }
    [PSCustomObject]@{ Name = 'Brazil';                    Code = 'BR'; Numeric = 76  }
    [PSCustomObject]@{ Name = 'Canada';                    Code = 'CA'; Numeric = 124 }
    [PSCustomObject]@{ Name = 'China';                     Code = 'CN'; Numeric = 156 }
    [PSCustomObject]@{ Name = 'Colombia';                  Code = 'CO'; Numeric = 170 }
    [PSCustomObject]@{ Name = 'Denmark';                   Code = 'DK'; Numeric = 208 }
    [PSCustomObject]@{ Name = 'Finland';                   Code = 'FI'; Numeric = 246 }
    [PSCustomObject]@{ Name = 'France';                    Code = 'FR'; Numeric = 250 }
    [PSCustomObject]@{ Name = 'Germany';                   Code = 'DE'; Numeric = 276 }
    [PSCustomObject]@{ Name = 'India';                     Code = 'IN'; Numeric = 356 }
    [PSCustomObject]@{ Name = 'Ireland';                   Code = 'IE'; Numeric = 372 }
    [PSCustomObject]@{ Name = 'Italy';                     Code = 'IT'; Numeric = 380 }
    [PSCustomObject]@{ Name = 'Japan';                     Code = 'JP'; Numeric = 392 }
    [PSCustomObject]@{ Name = 'Mexico';                    Code = 'MX'; Numeric = 484 }
    [PSCustomObject]@{ Name = 'Netherlands';               Code = 'NL'; Numeric = 528 }
    [PSCustomObject]@{ Name = 'New Zealand';               Code = 'NZ'; Numeric = 554 }
    [PSCustomObject]@{ Name = 'Norway';                    Code = 'NO'; Numeric = 578 }
    [PSCustomObject]@{ Name = 'Poland';                    Code = 'PL'; Numeric = 616 }
    [PSCustomObject]@{ Name = 'Portugal';                  Code = 'PT'; Numeric = 620 }
    [PSCustomObject]@{ Name = 'Russia';                    Code = 'RU'; Numeric = 643 }
    [PSCustomObject]@{ Name = 'South Africa';              Code = 'ZA'; Numeric = 710 }
    [PSCustomObject]@{ Name = 'South Korea';               Code = 'KR'; Numeric = 410 }
    [PSCustomObject]@{ Name = 'Spain';                     Code = 'ES'; Numeric = 724 }
    [PSCustomObject]@{ Name = 'Sweden';                    Code = 'SE'; Numeric = 752 }
    [PSCustomObject]@{ Name = 'Switzerland';               Code = 'CH'; Numeric = 756 }
    [PSCustomObject]@{ Name = 'United Arab Emirates';      Code = 'AE'; Numeric = 784 }
    [PSCustomObject]@{ Name = 'United Kingdom';            Code = 'GB'; Numeric = 826 }
    [PSCustomObject]@{ Name = 'United States';             Code = 'US'; Numeric = 840 }
)

function Resolve-Country {
    param([string]$InputValue)
 
    $trimmed = $InputValue.Trim()
 
    # 1. Exact ISO-2 code match (e.g. "US", "GB") — must be exactly 2 chars
    if ($trimmed.Length -eq 2) {
        $match = $CountryTable | Where-Object { $_.Code -ieq $trimmed } | Select-Object -First 1
        if ($match) { return $match }
    }
 
    # 2. Exact full name match (e.g. "United States")
    $match = $CountryTable | Where-Object { $_.Name -ieq $trimmed } | Select-Object -First 1
    if ($match) { return $match }
 
    # 3. Starts-with match on name (e.g. "United S" -> "United States")
    #    Only accept if exactly ONE result to avoid ambiguity (e.g. "United" matches 3 countries)
    $startMatches = $CountryTable | Where-Object { $_.Name -ilike "$trimmed*" }
    if ($startMatches.Count -eq 1) { return $startMatches[0] }
 
    if ($startMatches.Count -gt 1) {
        Write-Host "  [!] '$trimmed' is ambiguous. Did you mean one of these?" -ForegroundColor Yellow
        $startMatches | ForEach-Object { Write-Host "      $($_.Name) [$($_.Code)]" -ForegroundColor DarkGray }
        return $null
    }
 
    # 4. No match found
    return $null
}

function Write-Header {
    param([string]$Text)
    $line = '─' * ($Text.Length + 4)
    Write-Host ""
    Write-Host "  $line"  -ForegroundColor Cyan
    Write-Host "  │ $Text │"  -ForegroundColor Cyan
    Write-Host "  $line"  -ForegroundColor Cyan
    Write-Host ""
}

# ---------------------------------------------------------------------------
# STEP 1 – Verify the AD module is available
# ---------------------------------------------------------------------------
Write-Header 'AD User Location Updater'

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host '[ERROR] The ActiveDirectory module is not installed.' -ForegroundColor Red
    Write-Host '        Install RSAT (Active Directory DS Tools) and re-run.' -ForegroundColor Red
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop
Write-Host '[OK] ActiveDirectory module loaded.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# STEP 2 – Retrieve and display all OUs
# ---------------------------------------------------------------------------
Write-Header 'Select Organizational Unit'

try {
    $allOUs = Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName, Name |
              Sort-Object DistinguishedName
}
catch {
    Write-Host "[ERROR] Could not query Active Directory: $_" -ForegroundColor Red
    exit 1
}

if ($allOUs.Count -eq 0) {
    Write-Host '[ERROR] No Organizational Units found in the domain.' -ForegroundColor Red
    exit 1
}

# Display the OU list with index numbers
$index = 1
$ouMap = @{}

foreach ($ou in $allOUs) {
    $label = '{0,4}.  {1}' -f $index, $ou.DistinguishedName
    Write-Host $label
    $ouMap[$index] = $ou
    $index++
}

Write-Host ""
do {
    $selection = Read-Host "  Enter the number of the target OU (1-$($allOUs.Count))"
    $selInt    = 0
    $valid     = [int]::TryParse($selection, [ref]$selInt) -and
                 $selInt -ge 1 -and $selInt -le $allOUs.Count
    if (-not $valid) {
        Write-Host "  [!] Please enter a number between 1 and $($allOUs.Count)." -ForegroundColor Yellow
    }
} while (-not $valid)

$selectedOU = $ouMap[$selInt]
Write-Host ""
Write-Host "  Selected OU: " -NoNewline
Write-Host $selectedOU.DistinguishedName -ForegroundColor Green

# ---------------------------------------------------------------------------
# STEP 3 – Prompt for new City and Country
# ---------------------------------------------------------------------------
Write-Header 'Enter New Location Values'

$newCity = ''
while ([string]::IsNullOrWhiteSpace($newCity)) {
    $newCity = Read-Host '  New City'
    if ([string]::IsNullOrWhiteSpace($newCity)) {
        Write-Host '  [!] City cannot be blank.' -ForegroundColor Yellow
    }
}
$newCity = $newCity.Trim()

$newState = Read-Host '  New State/Province (optional)'
if ($newState) {
    $newState = $newState.Trim()
}

$countryResolved = $null
while (-not $countryResolved) {
    $countryInput    = Read-Host '  New Country (name or ISO-2 code, e.g. "United States" or "US")'
    $countryResolved = Resolve-Country -Input $countryInput

    if (-not $countryResolved) {
        Write-Host "  [!] '$countryInput' was not recognised. Try the full name or a 2-letter ISO code." -ForegroundColor Yellow
        Write-Host "      Recognised countries:" -ForegroundColor Yellow
        $CountryTable | Sort-Object Name | ForEach-Object {
            Write-Host ("      {0,-35} {1}" -f $_.Name, $_.Code) -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "  City    : $newCity"                       -ForegroundColor Cyan
Write-Host "  State    : $newState"                       -ForegroundColor Cyan
Write-Host "  Country : $($countryResolved.Name) [$($countryResolved.Code)]"  -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# STEP 4 – Retrieve users in the OU (SearchScope OneLevel = direct members)
# ---------------------------------------------------------------------------
Write-Header 'Retrieving Users'

$searchScope = 'Subtree'   # Change to 'Subtree' to include nested OUs

try {
    $users = Get-ADUser -Filter * `
                        -SearchBase  $selectedOU.DistinguishedName `
                        -SearchScope $searchScope `
                        -Properties  SamAccountName, DisplayName, City, Country, State, co
}
catch {
    Write-Host "[ERROR] Failed to retrieve users: $_" -ForegroundColor Red
    exit 1
}

if ($users.Count -eq 0) {
    Write-Host "  No user accounts found in the selected OU (SearchScope: $searchScope)." -ForegroundColor Yellow

    $expandScope = Read-Host '  Would you like to search all nested sub-OUs as well? (Y/N)'
    if ($expandScope -imatch '^y') {
        $searchScope = 'Subtree'
        $users = Get-ADUser -Filter * `
                            -SearchBase  $selectedOU.DistinguishedName `
                            -SearchScope $searchScope `
                            -Properties  SamAccountName, DisplayName, City, Country, State, co
    }

    if ($users.Count -eq 0) {
        Write-Host '  Still no users found. Nothing to update. Exiting.' -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "  Found $($users.Count) user(s) in OU (SearchScope: $searchScope)." -ForegroundColor Green

# ---------------------------------------------------------------------------
# STEP 5 – Preview
# ---------------------------------------------------------------------------
Write-Host ""
$preview = Read-Host '  Show a preview of affected users before making changes? (Y/N)'

if ($preview -imatch '^y') {
    Write-Host ""
    Write-Host ('  {0,-25} {1,-30} {2,-20} {3,-20} {4}' -f 'SamAccountName','DisplayName','Current City','Current State','Current Country')
    Write-Host ('  ' + ('─' * 110))
    foreach ($u in $users | Sort-Object SamAccountName) {
        Write-Host ('  {0,-25} {1,-30} {2,-20} {3,-20} {4}' -f
            $u.SamAccountName,
            ($u.DisplayName  -replace '^$','(none)'),
            ($u.City         -replace '^$','(none)'),
            ($u.State        -replace '^$','(none)'),
            ($u.co           -replace '^$','(none)'))
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# STEP 6 – Confirm before writing
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  About to set City='$newCity'  State='$newState'  Country='$($countryResolved.Name)'" -ForegroundColor Yellow
Write-Host "  for $($users.Count) user(s) in:" -ForegroundColor Yellow
Write-Host "  $($selectedOU.DistinguishedName)" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host '  Proceed with update? (Y/N)'
if ($confirm -notmatch '^[Yy]') {
    Write-Host '  Update cancelled by user.' -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------------------
# STEP 7 – Apply changes and log results
# ---------------------------------------------------------------------------
Write-Header 'Applying Changes'

$logPath    = Join-Path -Path $PSScriptRoot -ChildPath ("OUUpdate_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$succeeded  = 0
$failed     = 0
$logEntries = [System.Collections.Generic.List[string]]::new()

$logEntries.Add("AD User Location Update Log")
$logEntries.Add("Run at  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$logEntries.Add("OU      : $($selectedOU.DistinguishedName)")
$logEntries.Add("City    : $newCity")
$logEntries.Add("State   : $newState")
$logEntries.Add("Country : $($countryResolved.Name) [$($countryResolved.Code)] (numeric $($countryResolved.Numeric))")
$logEntries.Add("Scope   : $searchScope")
$logEntries.Add("Users   : $($users.Count)")
$logEntries.Add(("─" * 80))

foreach ($user in $users | Sort-Object SamAccountName) {
    try {
        if (-not $newState) {
            $newState = ''
            Set-ADUser -Identity $user.SamAccountName `
                   -City     $newCity `
                   -Country  $countryResolved.Code `
                   -Replace  @{
                       co           = $countryResolved.Name
                       countryCode  = $countryResolved.Numeric
                   }
        }
        else {
            Set-ADUser -Identity $user.SamAccountName `
                   -City     $newCity `
                   -State    $newState `
                   -Country  $countryResolved.Code `
                   -Replace  @{
                       co           = $countryResolved.Name
                       countryCode  = $countryResolved.Numeric
                   }
        }
        

        $msg = "  [OK]  $($user.SamAccountName) ($($user.DisplayName))"
        Write-Host $msg -ForegroundColor Green
        $logEntries.Add("OK   | $($user.SamAccountName) | $($user.DisplayName)")
        $succeeded++
    }
    catch {
        $errMsg = $_.Exception.Message
        $msg    = "  [FAIL] $($user.SamAccountName) - $errMsg"
        Write-Host $msg -ForegroundColor Red
        $logEntries.Add("FAIL | $($user.SamAccountName) | $($user.DisplayName) | ERROR: $errMsg")
        $failed++
    }
}

# ---------------------------------------------------------------------------
# STEP 8 – Summary
# ---------------------------------------------------------------------------
Write-Header 'Summary'

$logEntries.Add(("─" * 80))
$logEntries.Add("Succeeded : $succeeded")
$logEntries.Add("Failed    : $failed")

Write-Host "  Succeeded : $succeeded" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed    : $failed" -ForegroundColor Red
} else {
    Write-Host "  Failed    : $failed" -ForegroundColor Green
}

# Write log file
try {
    $logEntries | Set-Content -Path $logPath -Encoding UTF8
    Write-Host ""
    Write-Host "  Log saved to: $logPath" -ForegroundColor Cyan
}
catch {
    Write-Host "  [WARNING] Could not save log file: $_" -ForegroundColor Yellow
}

Write-Host ""