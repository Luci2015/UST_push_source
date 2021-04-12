# UST_push_source
obtain a csv list of accounts to use as source for 'push' stratergy of UST, by querrying the AD adudit log for events like: add to group, remove from group, enable and disable account

## Requirements:
- at least Python 3 installed
- PyYaml module installed (pip install pyyaml)
- access to run a PowerShell script on the AD machine
- any permission to access the AD audit log needs to be resolved
