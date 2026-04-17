$all      = Get-ADUser -Filter * -Properties enabled, LastLogon, LastLogonTimestamp, whenCreated
$enabled = $all | Where-Object Enabled -eq $true |
  Where-Object SamAccountName -ne "ets" | Where-Object SamAccountName -ne "administrator" |
  Where-Object whenCreated -lt (get-date).AddDays(-30) |
  where {[DateTime]::FromFileTime($_.LastLogonTimeStamp) -lt (get-date).AddDays(-30)} |
  Sort-Object LastLogonTimeStamp
  
$enabled | Set-AdUSer -WhatIf -Enabled $false