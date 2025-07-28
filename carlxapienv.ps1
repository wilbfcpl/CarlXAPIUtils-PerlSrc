#

# Installer downloaded. Commented out because environment does not work.
#& "$HOME\downloads\state-remote-installer.exe"

# Another variation of installer, environment still does not work.
# powershell {. $([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://platform.activestate.com/dl/cli/install.ps1'))) ;
	      
start powershell {mkdir CarlXAPI; cd CarlXAPI; state checkout FredCoMdLib/CarlXAPIUtils-PerlEnv . ; state use FredCoMdLib/CarlXAPIUtils-PerlEnv ; state shell FredCoMdLib/CarlXAPIUtils-PerlEnv  ; Read-Host}
