# Author:  <wblake@CB95043>
# Created: April 28, 2025
# Version: 0.01
#
# Usage: perl [-g] [-r ] [-x] [-i] UpdateItem.pl item_file.csv
# -g Debug/verbose -r read only , no update, -i in
# input file example
# BID, ITEM,OLDCN,NEWCN,[TITLE,AUTHOR,BRANCHCODE,LOCCODE...]
#65661m21982030613321,E SCOTTON - BEGINNING TO READ,ER SCOTTON,Splat the cat makes dad glad /,"Heyman, Alissa",BRU,EPRDR

use strict;
use warnings FATAL => 'all';
use diagnostics;

# See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
use XML::Compile::WSDL11;      # use WSDL version 1.1
use XML::Compile::SOAP11;      # use SOAP version 1.1
use XML::Compile::Transport::SOAPHTTP;
use Data::Dumper;
use Getopt::Std;
use integer;

use MCE::Loop;  # Import the MCE::Loop module
use Data::Dumper;
use feature 'say';
use Log::Log4perl qw(:easy);

#TRACE,DEBUG,INFO,WARN,ERROR,FATAL
Log::Log4perl->easy_init($TRACE);

#Command line input variable handling
our ($opt_g,$opt_r,$opt_x);
getopts('gdrx:');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

# Results and trace from XML::Compile::WSDL et al.
my $result ;
my $trace;

#Instrumentation for Print Messages
# Local filename is the name of this script

my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

#$ITEMID_FILE is the input file having the ItemIDs for update
my $ITEMID_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

INFO "[$local_filename" . ":" . __LINE__ . "]$ITEMID_FILE";
             
#See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
my $wsdlfile = 'ItemAPI.wsdl';

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $call1 = $wsdl->compileClient('UpdateItem');
 
unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}

my ($bid, $itemid,$old_callnumber,$new_callnumber);

my %ItemRec;
my %UpdateItemRequest;

%ItemRec = (
         #itemid=> $itemid,
         # bid=> $bid ,
        CallNumber=>''
         );

%UpdateItemRequest = (
 ItemID => '',
 Item => \%ItemRec,
     Modifiers=> {
        DebugMode=>1,
        ReportMode=>0,}
             );

# Use MCE::Loop to process lines in parallel
 MCE::Loop::init(
    max_workers => 8,
    chunk_size => 1,
    user_error => sub {
        my ($mce, $chunk_id, $error) = @_;
        ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
       );

# Loop until the end of the input file with the first line an assumed header.

mce_loop_f {

  chomp;
  INFO "[$local_filename" . ":" . __LINE__ . "]Record $_";

  ($bid,$itemid,$old_callnumber,$new_callnumber)  = split(/,/);

  $UpdateItemRequest{ItemID}= $itemid;
  $ItemRec{CallNumber}= $new_callnumber;
  
  my ($result1,$trace1)=$call1->(%UpdateItemRequest);
  if ($trace1->errors) {
    $trace1->printErrors;
  }
} $ITEMID_FILE ;

MCE::Loop::finish;


