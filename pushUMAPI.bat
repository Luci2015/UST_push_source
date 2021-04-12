
REM add below the full path to the folder location where extractADevents.ps1 is found
cd "C:\path\to\folder"

REM replace below with absolute path to the extractADevents.ps1 file itself:
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\path\to\folder\extractADevents.ps1'"

REM if python is installed and recognised as global command use below
REM if not, use abosolute path to python.exe
python prepare_push_list.py
REM the above should produce a 'push_list.csv'
REM deal its copy to UST folder, if all these files are not inside UST folder already

REM assuming the use of UST version >= 2.6.0, user-sync.exe is used
REM replace 'user-sync.exe' with 'python user-sync.pex' below if v<2.6.0
REM assuming the batch file and the push_list.csv are in same location as UST
user-sync.exe -t --strategy push --users file push_list.csv --process-groups
