# This file
https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/AUsePerlAPIScripts.md

# One time Setup of the ActiveState State Tool Perl Environment.

## Download & Install Runtime

https://state-tool.s3.amazonaws.com/remote-installer/release/windows-amd64/state-remote-installer.exe

## Open a PowerShell Window and temporarily allow execution of remote Scripts in this process

`set-executionpolicy bypass -Scope Process`

## Download Powershell Perl environment setup Script

https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/carlxapienv.ps1

## Copy Environment Setup Script to Your Project Directory, e.g.

`cp $HOME/downloads/carlxapienv.ps1 $HOME/apiprojects`

## Change Directory to Run the environment setup script. It will create a directory named carlxapi for the perl files.


`cd $HOME/apiprojects`


`.\carlxapienv.ps1`


## environment setup script file
https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/carlxapienv.ps1

## Confirm that perl is installed and running.
Open a New PowerShell Session.
Change to the Project Directory
`cd $HOME/apiprojects/carlxapi`

## Run a smoke test to get the Perl version and check syntax of an API script

`perl -v`

`perl -c AddNoteGrad.pl`

## CarlX API Perl script file AddNoteGrad.pl
https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/AddNoteGrad.pl

# Running API commands after completion of one-time setup. 
Command Format to run API script. Done for any run of the script.

## Run a script using an input CSV file

`perl AddNoteGrad.pl -g wilAddNote.csv`


## Input CSV file example 

wilAddNote.csv 
has a single PatronID but it could have multiple, one PatronID per line.

11982021684457

# Scripts to use
## AddNoteGrad.pl 
adds General Note to Graduated Student patron account. Typically done after FCPS identifies graduated students in June or July.

## patronAllowEMailMCE.pl 
Allows patron account to receive email

patronSendHoldAvailable 
Allows patron account to receive hold available message

settleFinesAndFeesMCE.pl
Settles fines in a Patron account. Needs CSV input file with PatronID, Fine ID, and fine amount
