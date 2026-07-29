param(
    [Parameter(Position=0, Mandatory=$true)]
    [string] $OU,
    [Parameter(Position=1, Mandatory=$true)]
    [string] $recovery_id
)

function convert-DNFormat
{
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [string] $ou,
        [Parameter(Position=1, Mandatory=$false)]
        [string] $base
    )

    $ouparts = $ou.Split("/")
    $base_parts = $ouparts[0].Split(".")
    $oupath = ""

    if(($base_parts.Length -gt 1) -and ([string]::IsNullOrEmpty($base))){
        $ouparts = $ouparts[1..$ouparts.Length]
        for($x = 0; $x -lt $base_parts.Length; $x++)
        {
            if($x -gt 0){
                $base += ","
            }
            $base += "DC=$($base_parts[$x])"
        }
    }

    if([string]::IsNullOrEmpty($base)){
        Throw "No domain controller is provided or can be inferred."
    }

    for($x = $ouparts.Length-1; $x -ge 0; $x--)
    {

        $oupath += "OU=$($ouparts[$x])"
        if($x -gt 0){
            $oupath += ","
        }
    }

    return "${oupath},${base}"
}

function get-ADComputerRecoveryKeys
{
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [Microsoft.ActiveDirectory.Management.ADComputer] $computer
    )

    $params = @{
        Filter     = "objectclass -eq 'msFVE-RecoveryInformation'"
        SearchBase = $computer.DistinguishedName
        Properties = 'msFVE-RecoveryPassword', 'whencreated'
    }

    $keys = Get-ADObject @params | Sort-Object -Property WhenCreated -Descending

    $parsed_keys = @()

    foreach($key in $keys){
        $parsed_keys += [PSCustomObject][ordered]@{
            ComputerName      = $computer.Name
            RecoveryPassword  = $key.'msFVE-RecoveryPassword'
            RecoveryID        = $key.Name.Substring(26, 36)
            Date              = $key.Name.Substring(0, 10)
            Time              = $key.Name.Substring(11, 8)
            DistinguishedName = $Computer.DistinguishedName
            OperatingSystem   = $Computer.OperatingSystem
        }
    }

    return $parsed_keys
}

if (-not (Get-Module -ListAvailable -Name ActiveDirectory))
{
    Write-Host '[ERROR] The ActiveDirectory module is not installed.' -ForegroundColor Red
    Write-Host '        Install RSAT (Active Directory DS Tools) and re-run.' -ForegroundColor Red
    exit 1
}

$dnpath = $(convert-DNFormat $OU)

$candidate_computers = Get-ADComputer -searchbase $dnpath -Filter 'ObjectClass -eq "computer"'
$success = $false

foreach($computer in $candidate_computers)
{

    $keys = get-ADComputerRecoveryKeys $computer
    foreach($key in $keys){
        if($key.RecoveryId -like "*$recovery_id*"){
            Write-Host "Match Found: $($key.ComputerName), $($key.RecoveryPassword)"
            $success = $true
        }
    }
}

if( -not $success){
    Write-Warning "No recovery password found for $recovery_id in $dnpath"
}
