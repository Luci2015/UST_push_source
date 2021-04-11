# 4729 - account removal from group
# 4728 - account add to group
# 4725 - account disabled
# 4722 - account enabled

# remove old events file
Remove-Item "events.csv"

# get events since 30 min ago (-0.5):
$Begin = (Get-Date).AddHours(-0.5)
$Events = Get-EventLog -logname Security  -After $Begin | where {$_.eventID -eq 4728 -or $_.EventID -eq 4729 -or $_.EventID -eq 4722 -or $_.EventID -eq 4725}

foreach($event in $Events){
  $dn = ($event | Select-Object @{Name="dn";Expression={$_.ReplacementStrings[0]}}).dn

  # change properties list as needed (eg for custom attributes) and
  # update the object properties on line 35 to export them correctly to csv
  $username =  Get-ADUser -Identity $dn -Properties ("mail",
                           "Country",
                           "sn",
                           "GivenName",
                           "UserPrincipalName",
                           "MemberOf",
                           "Enabled")
  
  $eventID = $event.EventID
  if ($eventID -eq "4729"){
  $removedGroup = ($event | Select-Object @{Name="groupName";Expression={ $_.ReplacementStrings[2]}}).groupName
  } else { $removedGroup = "" }
  $trgt = @()
  foreach ($g in $username.MemberOf){ $trgt += (Get-ADGroup $g -Properties "CN").CN }
  $remaningGroups = $trgt -join ","
  # if needed, change the values of the properties below to 
  # point to the right variable/value 
  New-Object -TypeName PSCustomObject -Property @{
    eventID=$eventID
    timeWritten=$event.TimeWritten
    username=$username.UserPrincipalName
    country=$username.Country
    email=$username.mail
    lastname=$username.sn
    firstname=$username.GivenName
      domain=""
    enabled=$username.Enabled
    removedGroup=$removedGroup
    customAttrbute1=""
    customAttrbute2=""
    customAttrbute3=""
    customAttrbute4=""
    remaningGroups="'" + $remaningGroups + "'" } | Export-Csv "events.csv" -NoTypeInformation -Append
}
(Get-Content "events.csv").replace('"', '').replace("'",'"')| Set-Content "events.csv"

