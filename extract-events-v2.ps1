# followed events
# 4729 - account removal from Global Security group
# 4728 - account add to Global Security group
# 4725 - account disabled
# 4722 - account enabled
# 4756 - account removal from Universal Security group
# 4757 - account add to Universal Security group

# Import-Module ActiveDirectory

# get events since 30 min ago (-0.5):
$Begin = (Get-Date).AddHours(-0.5)
$Events = Get-EventLog -logname Security  -After $Begin | where { $_.eventID -eq 4728 -or $_.EventID -eq 4729 -or $_.EventID -eq 4722 -or $_.EventID -eq 4725 -or $_.EventID -eq 4756 -or $_.EventID -eq 4757}

#------------------------------
# MODIFY INPUT VALUES HERE
#------------------------------
Remove-Item "events.csv"
Remove-Item "push_list.csv"
$ignore_list = @{}
$content = @{}
$already_queried = @{}
$output_file = "events.csv"
# use 0 to disable 1 to enable nested group membership look-up
$nested_group_lookup = 0
# next variable needs to be uncommented if $nested_group_lookup = 1
# list all LDAP groups that contain nested groups and are declared in UST's config:
#$mapped_groups = @("CN=group1,OU=some_ou,DC=domain,DC=local","CN=group2,OU=some_ou,DC=domain,DC=local","CN=group3,OU=some_ou,DC=domain,DC=local")
#
#------------------------------


function ListMappedGroups($mapped_groups){
    $key_groups = @()
    foreach ($group_dn in $mapped_groups) {
        $nestedGroups = @()
        $u_list=@()
        $query1 = ("(&(objectClass=user)(memberOf:1.2.840.113556.1.4.1941:=" + $group_dn + "))")
        $u_list = Get-ADUser -LDAPFilter $query1 | foreach  {$_.DistinguishedName}
        $query2 = ("(&(objectClass=group)(memberOf:1.2.840.113556.1.4.1941:=" + $group_dn + "))")
        $nestedGroups = Get-ADGroup -LDAPFilter $query2 | foreach  {$_.DistinguishedName}
        
        $obj = New-Object -TypeName PSCustomObject -Property @{
            key=$group_dn
            u_list=$u_list
            nested_groups=$nestedGroups
        }
        $key_groups += $obj
    }
    return $key_groups
}

function RegexpFirstMatch($start, $end, $string){
    $regEx = "$start(.*?)$end"
    $res = [regex]::Match($string,$regEx).Groups[1].Value
    return $res
}

function ResolveRemovedGroups($event, $key_groups, $qnesting_active){
    #$key_groups object:

    # key            u_list            nested_groups
    #-----------     -------------     -------------------------------
    #mapped_Grp_DN   u1_DN, u2_DN..    nested_grp1_DN, nested_Grp2_DN...

    $gn = ($event | Select-Object @{Name="groupName";Expression={ $_.ReplacementStrings[2]}}).groupName
    if ($qnesting_active){
        $remg = @()
        $gr_info = Get-ADGroup $gn -Properties "DistinguishedName","MemberOf"
        $removed_group_dn = $gr_info.DistinguishedName
        $rem_gr_memberOf = $gr_info.MemberOf
        $r_groups = @()
        $removed_groups = @()
        foreach ($line in $key_groups){
            if ($username.DistinguishedName -in $line.u_list){
                $r_groups += $line.key
            }   
        }
        # return at least one removed mapped group
        foreach($line in $key_groups){
            if ($removed_group_dn -in $line.nested_groups){
                if($line.key -notin $r_groups){
                      #return (Get-ADGroup $line.key -Properties "CN").CN 
                      return RegexpFirstMatch "CN=" "," $line.key
                  }
               }
            }
    } else { return $gn }
    
}

if ($nested_group_lookup){
    $g_listing = ListMappedGroups $mapped_groups
}

foreach($event in $Events){
  $remainingGroups = @()
  $removedGroup = ""
  $dn = ($event | Select-Object @{Name="dn";Expression={$_.ReplacementStrings[0]}}).dn
  if ($ignore_list.ContainsKey($dn)) {
      # not an AD User object
      Continue
  }

  if ($already_queried.ContainsKey($dn)){
        # this user was already queried, so pick the values from hash table
        $username = $already_queried.$dn.u
        $remainingGroups = $already_queried.$dn.g
        Continue
  } else {
        try {  
            # change extracted Properties as needed
            $username =  Get-ADUser -Identity $dn -Properties ("mail",
                                                               "c",
                                                           "sn",
                                                           "GivenName",
                                                           "UserPrincipalName",
                                                           "MemberOf",
                                                           "Enabled",
                                                           "DistinguishedName")
        } catch {
                 # not an AD User object, so skip it
                 $ignore_list.Add($dn, "ignored")
                 Continue
        }

        $trgt = @()
        if ($nested_group_lookup){
            foreach ($line in $g_listing){
                if ($username.DistinguishedName -in $line.u_list){
                    $trgt += $line.key
                }
                
            }
        }

        else { 
            foreach ($group in $username.MemberOf){
                $trgt += $group
            }
        }
        
        $eventID = $event.EventID

        if ($eventID -eq "4729" -or $eventID -eq "4757"){
            $removedGroup =  ResolveRemovedGroups $event $g_listing $nested_group_lookup
        }

        $remGroup = @()
        foreach ($group_dn in $trgt){
            $remGroup += RegexpFirstMatch "CN=" "," $group_dn
        }
        $remainingGroups = $remGroup -join(",")
        $content.u = $username
        $content.g = $remainingGroups
        $already_queried.$dn = $content
    }
        # if needed, change the values of the properties below to point to the right variable
        # "remainingGroup" and "enabled" properties get the latest 'MemberOf' 
        # and 'Enabled' attribute values of each account affected by the event, NOT  
        # what values were at the moment of the event

        New-Object -TypeName PSCustomObject -Property @{
            eventID=$eventID
            timeWritten=$event.TimeWritten
            username=""
            country=$username.c
            email=$username.mail
            lastname=$username.sn
            firstname=$username.GivenName
            domain=""
            enabled=$username.Enabled
            removedGroup=$removedGroup
            customAttribute1=""
            customAttribute2=""
            remainingGroups="'" + $remainingGroups + "'" } | Export-Csv $output_file -NoTypeInformation -Append
}

try {
    (Get-Content $output_file).replace('"', '').replace("'",'"')| Set-Content $output_file
    } catch { Write-Warning "No events found" }


