$group = "group_name"
Get-ADGroupMember $group | ForEach-Object {Remove-ADGroupMember $group $_ -Confirm:$false}