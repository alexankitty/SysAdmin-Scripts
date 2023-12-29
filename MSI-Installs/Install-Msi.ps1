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
foreach ($item in $Path) {
    $getMsiProduct = "$PSScriptRoot\Get-MsiProductCode.ps1 $item"
    [string]$productGUID = Invoke-Expression $getMsiProduct
    $productGUID = $productGUID.trim()
    [scriptblock]$filter = { $_.IdentifyingNumber -eq $productGUID }
    $product = Get-WmiObject Win32_Product | Where-Object {$_.IdentifyingNumber -like $productGUID}
    if(!$product){
        ##Not installed, let's install it
        echo "Installing"
        $installer = Copy-Item $item -Destination "C:\Windows\Temp" -PassThru
        Start-Process msiexec "/i $installer /norestart /qn" -Wait;
        Remove-Item $installer
    }
}
