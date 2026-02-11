$all      = Get-ADUser -Filter * -Properties enabled, LastLogon, LastLogonTimestamp, whenCreated
$disabled = $all | Where-Object Enabled -eq $false |
  Where-Object SamAccountName -ne "ets" | Where-Object SamAccountName -ne "administrator" |
  Where-Object whenCreated -lt (get-date).AddDays(-90) |
  where {[DateTime]::FromFileTime($_.LastLogonTimeStamp) -lt (get-date).AddDays(-90)} |
  Sort-Object LastLogonTimeStamp

$disabled | Remove-AdUsers -WhatIf