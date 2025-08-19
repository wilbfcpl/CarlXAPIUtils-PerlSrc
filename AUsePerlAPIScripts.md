# Overview
## Setup CarlX API scripting Windows PowerShell environment built on [ActiveState Platform State Tool](https://docs.activestate.com/platform/state/). Active State Platform and state tool maintain the security and validity of the script components - a useful feature among scripting environments. These CarlX API based scripts use the ActiveState Perl programming lanuage run from Windows CMD or Powershell. Goal: make CarlXAPI functions available to CarlX library staff having access to the CarlX API and Windows command line. No need to install or learn Perl, the State Tool behind the curtain does it for you. Just find the name of the desired function like PatronAllowEmail or PatronSendHoldAvailable and provide a csv file with the PatronIDs.



[CarlXAPI Perl Source Github](https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/tree/master)

[ActiveState Platform](https://www.activestate.com/platform/)

[ActiveState Perl](https://www.activestate.com/platform/supported-languages/perl/)

## Note that under Windows the ActiveState Platform State Tool can conflict with tools like mingw, cygwin, and Strawberry Perl. After one-time installation, a CarlX library staff person will run a CarlX API perl script with an input csv file. This example adds a standard note to every patron account with patronID present in the first column of file wilAddNote.csv. 
`perl AddNoteGrad.pl -g wilAddNote.csv`
## Note that the CSV file coding must use iso-latin-1-dos / ISO 8859 1  or the perl script will fail
# [Active State State Tool Background](https://docs.activestate.com/platform/state/)

# [This file](https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/AUsePerlAPIScripts.md)

# One time Setup of the ActiveState State Tool Perl Environment.

## [Download & Install Runtime](https://state-tool.s3.amazonaws.com/remote-installer/release/windows-amd64/state-remote-installer.exe)

## Open a PowerShell Window and temporarily allow execution of remote Scripts

`set-executionpolicy bypass -Scope Process`

## [Download Powershell Perl environment setup Script](https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/carlxapienv.ps1)

## Copy Environment Setup Script to Your Project Directory, e.g.

`cp $HOME/downloads/carlxapienv.ps1 $HOME/apiprojects`

## Change Directory to Run the environment setup script. It will create a directory named carlxapi for the perl files.


`cd $HOME/apiprojects`


`.\carlxapienv.ps1`


## [Environment setup script file](https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/carlxapienv.ps1)

## Confirm that perl is installed and running.
Open a New PowerShell Session.
Change to the Project Directory
`cd $HOME/apiprojects/carlxapi`

## Run a smoke test to get the Perl version and check syntax of an API script

`perl -v`

`perl -c AddNoteGrad.pl`

## [CarlX API Perl script file AddNoteGrad.pl](https://github.com/wilbfcpl/CarlXAPIUtils-PerlSrc/blob/master/AddNoteGrad.pl)

# Running API commands after completion of one-time setup. 
Command Format to run API script. Done for any run of the script.

## Run a script using an input CSV file. Use your own CSV with parameters like PatronID, ItemID, Call Number, and NoteID. Should add a Standard Note to the Patron Accounts in the file, in this case a single patron.

`perl AddNoteGrad.pl -g wilAddNote.csv`


## Input CSV file example 

wilAddNote.csv 
has a single PatronID but it could have multiple, one PatronID per line.

11982021684457

## [Carl Connect view of the above PatronID](https://fcpl.carlconnect.com/Circulation/UserServices/userInformation.html?Barcode=11982021684457&keyword=&searchbutton=Search&FromSearch=true)

# Uninstall steps PowerShell
`state clean uninstall -a`

`rmdir CarlXAPI`

# Scripts to use
## AddNoteGrad.pl 
adds General Note to Graduated Student patron account. Typically done after FCPS identifies graduated students in June or July.

## patronAllowEMailMCE.pl 
Allows patron account to receive email

patronSendHoldAvailable 
Allows patron account to receive hold available message

settleFinesAndFeesMCE.pl
Settles fines in a Patron account. Needs CSV input file with PatronID, Fine ID, and fine amount
