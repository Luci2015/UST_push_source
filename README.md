# UST push source
Obtain a csv list of accounts to use as source for 'push' stratergy of UST, by querrying the AD audit log for events like: add to group, remove from group, enable and disable account

## Requirements:
- at least Python 3 installed
- Python's PyYAML module installed (`pip install PyYAML`)
- access to run a PowerShell script on the AD machine
- resolve any permission needed to access the AD audit log for the running account

## Configuration
For the ease of this setup, the following setup assumes the scripts are going to reside inside User Sync Tool's folder, which runs on the AD machine.  
Files needed:  
- `extract-events-v2.ps1`
- `prepare_push_list.py`
- `pushUMAPI.bat` (optional, but handy to have) 
Copy the above files inside User Sync Tool's folder, next to the `user-sync-config.yml`. Below there are some pointers on how to edit these files.

### extract-events-v2.ps1
This script should manage events for users that are direct memebrs of UST's mapped group or their nested groups. Things to configure:
- modify how long in the past the script should look for events (below, the '-0.5' means half an hour ago); of course it should cover any time interval between two consecutive runs, so that all events are captured at the moment of the run   
```powershell
$Begin = (Get-Date).AddHours(-0.5)
```
- if default filenames mentioned in the script will not work for you, make sure you adapt both the .ps1 file and the .py one to match
- this parameter should be used in accordance with UST's mapped groups: are they flat or do they contain nested groups inside? ( 0 = disabled, 1 = enabled )
```powershell
$nested_group_lookup = 0
```
- if the nested_group_lookup line is enabled, the `$mapped_groups` variable/line should be uncommented and populated with the exact `DistinguishedName` values for all LDAP groups that are declared in UST's config file. Here is a sample for 2 groups:
```powershell
$mapped_groups = @("CN=group1,OU=wwds,DC=cbart,DC=local","CN=group2,OU=wwds,DC=cbart,DC=local")
```
- modify which properties should be extracted for the user identified in the event, in case the provided list is not sufficient. The last 3 are required in the script, the rest need to be preserved/replaced with the exact attribue that contains the needed value. Add customAttributes if necessary  
```text
"mail", "c", "sn", "GivenName", "UserPrincipalName", "MemberOf", "Enabled", "DistinguishedName"
```
- the last `PSCustomObject` contains a mapping of the csv export file columns and the values it should pick from each variable. As a 'default' the script contains the `username` and `domain` values initialised as empty strings. For UST sync, this means Username=Email field value in Admin Console. If these need to be different, make sure `email` and `username` point to the correct variables. You will also notice the *customAttribute1-2*, which do not have proper mapping - use them in conjunction with any custom attribute you might need extracted (see previous bullet-point).
- the ps script hardcodes the resulting csv events file to `events.csv`; if you require a different file name, change the values in the last 2 lines of the script  

### prepare_push_list.py  
- if you modified the *events.csv* file name in the ps script, make the same change for `EVENTS_FILE_PATH`
- `PUSH_FILE_PATH` is initialised to `push_list.csv` as name of the output csv file of this script, which will be used as the source for UST later
- `UST_FILE_PATH` is targeting the `user-sync-config.yml`; as mentioned, this script file is in the same folder as UST, so there is no need to use the absolute path
- `LOGS_FOLDER` is not initialised with a name, but since this runs on a Windows machine, it could be modified to UST's usual logs folder, in this format: `'C:\\path_to_UST_folder\\logs\\'`; use the double backslashes!

This Python script will filter the accounts appearing in the events, so that they are the only ones that need a change in Admin Console.

### pushUMAPI.bat  
This is a sample file that contains the suite of scripts to be run in order to have full automation:  
- line 3: input the path where the UST folder containing the ps script is located
- line 6: document the full path to the `extract-events-v2.ps1` file
- line 10: if *Python* is installed and recognised as a global command, it does not need any change, otherwise full path to `python.exe` is required
- line 17: for version of UST >= 2.6.0, the provided command line and arguments (`user-sync.exe -t --strategy push --users file push_list.csv --process-groups`) runs a test-mode instance of the UST, targeting the `push_list.csv` file. Remove *-t* for a live run and for changes to be applied in Admin Console. Replace `push_list.csv` with the actual push list csv file name if you modified it in the `prepare_push_list.py` script.  

### What will happen
- the PS script will extract events 4722, 4725, 4728, 4729, 4756 and 4757 from AD's audit logs (enable/disable account, add/remove to/from global/universal security group) for the provided past X hours
- the PS script will produce an `events csv` file that will serve as input for the `prepare_push_list` Python script
- `prepare_push_list.py` will run and filter the resulting accounts some more, so that only the ones that need to be modified in the Admin Console are part of the resulting csv file. These accounts suffered a group change and that group is also mentioned as a User Sync Tool mapped LDAP group name. Disabling or enabling the account can also make it appear or disappear in/from one of the LDAP mapped groups and the script accounts for this scenario as well.
- with the resulting `push_list.csv` file, UST is run and the changes are pushed in the Admin Console: new accounts get added to mapped groups, old accounts get added or removed from mapped groups, suspended accounts get removed from all mapped groups.  
 No account removal from Admin Console's Users menu happens, just group membership processing.
 
## Limitations
 - the PowerShell script only works with events for Global and Universal Security groups only; those groups are also mapped in UST's `user-sync-config.yml` file
 - the script was tested for an AD forest with one domain tree; for more complicated scenarios one could take into account running this script on multiple AD forests and uniting the results in one csv file for feed to UST
 - if nested group lookup is required, the script contains dedicated Active Directory queries, so it will fail for other LDAP servers.  



