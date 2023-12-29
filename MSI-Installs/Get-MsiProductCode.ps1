

<#PSScriptInfo
 
.VERSION
    1.0
.GUID
    01281c47-25e2-4245-a1c0-b70e27acbe21
.AUTHOR
    Thomas J. Malkewitz @dotsp1
 
#>

<#
 
.SYNOPSIS
    Gets the product code from a Windows Installer Database.
.DESCRIPTION
    Opens a Windows Installer Database (.msi) and querys for the product code.
.INPUTS
    System.String.
.OUTPUTS
    System.Guid.
.EXAMPLE
    PS C:\> Get-MsiProductCode -Path C:\my.msi
.LINK
    http://dotps1.github.io
 
#>

[OutputType(
    [Guid]
)]

Param (
    [Parameter(
        Mandatory = $true,
        ValueFromPipeLine = $true
    )]
    [ValidateScript({
        if ($_.EndsWith('.msi')) {
            $true
        } else {
            throw "$_ must be an '*.msi' file."
        }
    })]
    [String[]]
    $Path
)

Process {
    foreach ($item in $Path) {
        try {
            $windowsInstaller = New-Object -com WindowsInstaller.Installer

            $database = $windowsInstaller.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $windowsInstaller, @((Get-Item -Path $item).FullName, 0))

            $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, ("SELECT Value FROM Property WHERE Property = 'ProductCode'"))
            $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)

            $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)

            Write-Output -InputObject $($record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 1))

            $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
            [Void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($windowsInstaller)
        } catch {
            Write-Error -Message $_.ToString()
            
            break
        }
    }
}
