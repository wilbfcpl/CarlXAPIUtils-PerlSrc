*CarlX API Perl scripts*

Perl files in this repository provide command line use of the CarlXAPI to manipulate CarlX Patron account records or CarlX Item records. Other files in the repositoryprovide data for the CarlXAPI utilities (csv files, xlsx files), CarlXAPI SOAP support (wsdl files), and ActiveState Platform support (yaml files).

typical command line usage format :
`perl <scriptfile>.pl InputFile.csv`

For example to set the hold available flag true for patron ids in the file aftantest.csv:

`perl patronSetHoldAvailable.pl aftantest.csv`

Manifest of Perl Scripts.

SettleFinesAndFees
Accepts an input file of the Patron ID, Item Id starting with #177
PATRONID,HASH177,FINEAMOUNT,FINEDATE,ITEM,NAME,STATUS,BTYCODE,EDITDATE,ACTDATE

