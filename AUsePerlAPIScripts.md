
Download & Install Runtime

https://state-tool.s3.amazonaws.com/remote-installer/release/windows-amd64/state-remote-installer.exe

Open a PowerShell Window and allow execution of Scripts

`set-executionpolicy bypass`

Download Powershell Perl environment setup Script

https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/carlxapienv.ps1

Copy Environment Setup Script to Your Project Directory, e.g.

`cp $HOME/downloads/carlxapienv.ps1 $HOME/apiprojects`

Change Directory to Run the environment setup script

`cd $HOME/apiprojects`

`./carlxapienv.ps1`


Running a script using an input CSV file

`perl AddNoteGrad.pl -g wilAddNote.csv`


wilAddNote.csv has a single  PatronID but it could have more, one PatronID per line.

11982021684457

Scripts to use
AddNoteGrad.pl 
adds General Note to Graduated Student patron account. Typically done after FCPS identifies graduated students in June or July.

patronAllowEMailMCE.pl 
Allows patron account to receive email

patronSendHoldAvailable 
Allows patron account to receive hold available message

settleFinesAndFeesMCE.pl
Settles fines in a Patron account. Needs CSV input file with PatronID, Fine ID, and fine amount
