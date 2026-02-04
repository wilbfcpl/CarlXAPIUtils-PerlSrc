# Author:  <wblake@3C5XT34>
# Created: Feb 02, 2026
# Version: 0.01
#
# Usage: perl [-d] isbn2bid.pl [-r ] [-x] [-g] filename.csv
# -d Debug/verbose captured by perl exe, remaining options left for this script
# -g Logging
# checked but not used: -r, -x
# filename.csv is a file ISBN numbers
# Warning.
# Input file filename.csv should only have ISBN values that exist in the CarlX catlog
# isbn2bid will report the bid and other CarlX Catalog fields to every account listed.
# Only the isbn column really matters but the Input CSV file column order goes:
# $isbn,$title, $author, $callnuber
#
#Debug mode- a lot more SOAP messages.=
#
# Assumes first line of in file has column label headings
# Uses local copy of CarlX WSDL file Catalog.wsdl for interface to CatalogAPI requests getCatalogInformation
#
# A tool like SOAPUI can provide a sandbox for the WSDL file and PatronAPI requests.
#
# Note that API call and response return appear to take one second in real time.
# 
# An SQL Query to provide the title records

#select bib.bid, books.isbn,bib.CALLNUMBER, bib.title
#from SCIENCE_TECH_BOOKS_2025 books
#     inner join bbibmap_v2 bib  on (bib.isbn = books.isbn)
;
#expected csv file columns:   
#$isbn
#

use strict;
use warnings FATAL => 'all';
use diagnostics;

use LWP::UserAgent;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;
use Data::Dumper;
use Getopt::Std;
use integer;
use MCE::Loop;  # Import the MCE::Loop module
use feature 'say';
use Log::Log4perl qw(:easy);
use IO::Prompt::Tiny qw/prompt/;

Log::Log4perl->easy_init($DEBUG);


use constant CARLX_ID_WB0=> 'wb0';

use constant INSTITUTE_CODE => 1770;
use constant FCPL_BRANCH=>'HDQ';



our ($opt_g,$opt_r,$opt_x);
getopts('gdrx:');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

my $result ;
my $trace;

my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

my $ISBN_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

INFO "[$local_filename" . ":" . __LINE__ . "]$ISBN_FILE";

my $wsdlfile = 'CatalogAPI.wsdl';

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}




my $call1 = $wsdl->compileClient('GetCatalogInformation');

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}



my %getCatalogInformation;
my %ResponseStatuses;
my %ResponseStatus;
my %titleRec;


# %titleRec = {
#         BibID,
# 	Isbn,
# 	Author,
# 	DisplayTitle,
# 	PublicationYear,
# 	CallNumber,
# 	Format,
# 	HiddenType,
# 	HoldCount,
# 	EResource
# };

# %getCatalogInformationResponse = (
#     ResponseStatus=>\%ResponseStatus,
#     Title=>\%titleRec
# );



# Use MCE::Loop to process lines in parallel
 MCE::Loop::init(
    max_workers => 8,
    chunk_size => 1,
    user_error => sub {
        my ($mce, $chunk_id, $error) = @_;
        ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
       );

# Save OFS and set it to comma to generate a csv

my $SavedOFS = $,;
$,= ",";

# Loop until the end of the input file with the first line an assumed header.
mce_loop_f {


  chomp;
  #INFO "[$local_filename" . ":" . __LINE__ . "]Record $_";

  my  ($isbn)  = split(/,/);
  
  INFO "[$local_filename" . ":" . __LINE__ . "]ISBN $isbn";

  %getCatalogInformation= (   SearchField=>'ISBN',
			      SearchFieldValue => $isbn ,
			      Modifiers=> { DebugMode=>1,
			      ReportMode=>1});
  
  my ($result1,$trace1)=$call1->(%getCatalogInformation);
  if ($trace1->errors) {
    $trace1->printErrors;
  }

  # [TODO] Figure out where server places the response status 
  #  %ResponseStatuses = %{$result1->{GetCatalogInformationResponse}->{ResponseStatuses}->{ResponseStatus}}  ;
  %ResponseStatus = %{$result1->{GetCatalogInformationResponse}->{ResponseStatuses}->{cho_ResponseStatus}[0]->{ResponseStatus}} ;

  INFO "[$local_filename" . ":" . __LINE__ . "]ResponseStatus{ShortMessage}: ".  $ResponseStatus{ShortMessage};
  
 # INFO "[$local_filename" . ":" . __LINE__ . "]ResponseStatusCode $ResponseStatus{Code}";
  
    %titleRec =     %{$result1->{GetCatalogInformationResponse}->{Title}} ;
  
  INFO "[$local_filename" . ":" . __LINE__ . "]Bid $titleRec{BibID}";
  
  print  $titleRec{BibID}, $titleRec{Isbn}, '"' .  $titleRec{Author} . '"', '"' . $titleRec{DisplayTitle} . '"', $titleRec{PublicationYear}, $titleRec{CallNumber}, $titleRec{Format}, $titleRec{EResource} . "\n"

  } $ISBN_FILE ;

MCE::Loop::finish;
#restore OFS 
$,= $SavedOFS; 

