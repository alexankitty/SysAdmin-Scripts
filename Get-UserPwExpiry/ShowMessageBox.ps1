Param (
    [Parameter(
        Mandatory = $true
    )]
    [String[]]
    $Msg,
    [String[]]
    $Title,
    [String[]]
    $Type
)
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show($Msg, $title, 'OK',$Type)
