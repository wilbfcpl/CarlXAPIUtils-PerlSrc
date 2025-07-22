& "$HOME\downloads\state-remote-installer.exe"
start powershell {mkdir CarlXAPI; cd CarlXAPI; state checkout FredCoMdLib/CarlXAPIUtils-PerlEnv . ; state use FredCoMdLib/CarlXAPIUtils-PerlEnv  ;Read-Host}
