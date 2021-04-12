# 4729 - account removal from group
# 4728 - account add to group
# 4725 - account disabled
# 4722 - account enabled

# remove old input files
Remove-Item "events.csv"
Remove-Item "push_list.csv"
# get events since 30 min ago (-0.5):
$Begin = (Get-Date).AddHours(-0.5)
$Events = Get-EventLog -logname Security  -After $Begin | where {$_.eventID -eq 4728 -or $_.EventID -eq 4729 -or $_.EventID -eq 4722 -or $_.EventID -eq 4725}
$already_queried = @{}
$content = @{}
foreach($event in $Events){
  $dn = ($event | Select-Object @{Name="dn";Expression={$_.ReplacementStrings[0]}}).dn
  if ($already_queried.ContainsKey($dn)){
	  # this user was already queried, so pick the values from hash table
		$username = $already_queried.$dn.u
		$remaningGroups = $already_queried.$dn.g
  } else {  
		# change extracted Properties as needed
		$username =  Get-ADUser -Identity $dn -Properties ("mail",
								   "Country",
								   "sn",
								   "GivenName",
								   "UserPrincipalName",
								   "MemberOf",
								   "Enabled")

		$trgt = @()
		foreach ($g in $username.MemberOf){ $trgt += (Get-ADGroup $g -Properties "CN").CN }
		$remaningGroups = $trgt -join ","
		$content.u = $username
		$content.g = $remaningGroups
		$already_queried.$dn = $content
		}
  
  $eventID = $event.EventID
  if ($eventID -eq "4729"){
  $removedGroup = ($event | Select-Object @{Name="groupName";Expression={ $_.ReplacementStrings[2]}}).groupName
  } else { $removedGroup = "" }
  
  # if needed, change the values of the properties below to 
  # point to the right variable/value 
  # because Get-ADUser and Get-ADGroup happens only once per user expect
  # the output events file to contain the remainingGroup and enabled 
  # columns populated with whatever values were found at the moment of
  # the query for MemberOf and Enabled, and not the values at the time of event

  New-Object -TypeName PSCustomObject -Property @{
    eventID=$eventID
    timeWritten=$event.TimeWritten
    username=""
    country=$username.Country
    email=$username.mail
    lastname=$username.sn
    firstname=$username.GivenName
    domain=""
    enabled=$username.Enabled
    removedGroup=$removedGroup
    customAttribute1=""
    customAttribute2=""
    customAttribute3=""
    customAttribute4=""
    remaningGroups="'" + $remaningGroups + "'" } | Export-Csv "events.csv" -NoTypeInformation -Append
}

(Get-Content "events.csv").replace('"', '').replace("'",'"')| Set-Content "events.csv"

