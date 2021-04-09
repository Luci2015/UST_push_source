# 4729 - account removal from group
# 4728 - account add to group
# 4725 - account disabled
# 4722 - account enabled
Remove-Item "events.csv"

$Begin = Get-Date -Date '4/7/2021 08:00:00'
$Events = Get-EventLog -logname Security  -After $Begin | where {$_.eventID -eq 4728  -or $_.EventID -eq 4729  -or $_.EventID -eq 4722 -or $_.EventID -eq 4725}

foreach($event in $Events){

  $dn = ($event | Select-Object @{Name="dn";Expression={$_.ReplacementStrings[0]}}).dn
  $username =  Get-ADUser -Identity $dn -Properties ("mail","Country","sn","GivenName","UserPrincipalName", "MemberOf")
  $eventID = $event.EventID
  
  if ($eventID -eq "4729" -or $eventID -eq "4728"){
	$groupName = ($event | Select-Object @{Name="groupName";Expression={ $_.ReplacementStrings[2]}}).groupName
  } else {
    $trgt = @()
	$groupName = foreach ($g in $username.MemberOf){$trgt += (Get-ADGroup $g -Properties "CN").CN}
    $groupName = $trgt -join ","
  }
  
  New-Object -TypeName PSCustomObject -Property @{
	  eventID=$eventID
	  timeWritten=$event.TimeWritten
	  username=$username.UserPrincipalName
	  country=$username.Country
	  email=$username.mail
	  lastname=$username.sn
	  firstname=$username.GivenName
      type="federatedID"
      domain=""
	  groups="'" + $groupName + "'" } | Export-Csv "events.csv" -NoTypeInformation -Append
}
(Get-Content "events.csv").replace('"', '').replace("'",'"')| Set-Content "events.csv"

