# Author:  <wblake@3C5XT34>
# Created: Feb 02, 2026
# Version: 0.01
#
# Usage: perl [-d] isbn2bid.pl [-r ] [-x] [-g] filename.csv
# -d Debug/verbose captured by perl exe, remaining options left for this script
# -g Logging
# -p Production. Default is Test.
# checked but not used: -r,
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
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for interface to PatronAPI requests AddPatronNote
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

#TRACE,DEBUG,INFO,WARN,ERROR,FATAL
Log::Log4perl->easy_init($TRACE);

# Reduce number of magic values where possible
use constant SEARCHTYPE_PATRONID => 'Patron ID';

use constant PATRON_MODIFIERS_DEBUG_MODE_ON => 1;
use constant PATRON_MODIFIERS_REPORT_MODE_ON => 1;
use constant PATRON_MODIFIERS_STAFFID_WIL => 'wb0';


use constant INSTITUTE_CODE => 1770;
use constant FCPL_BRANCH=>'HDQ';

our ($opt_g,$opt_p);
getopts('gp');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

my $result ;
my $trace;

my $local_filename=$0;

$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

my $PATRON_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

INFO "[$local_filename" . ":" . __LINE__ . "]$PATRON_FILE";

my $wsdlfile =  ( defined $opt_p ?  'PatronAPI.wsdl' : 'PatronAPInew.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlfile: $wsdlfile";

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);#

my $user = prompt("Username:") ;
my $passwd = prompt ("Password:") ;

unless ( (defined $user) and (defined $passwd))
    {
	 die "[$local_filename" . ":" . __LINE__ . "]Failed user $user passwd $passwd\n"
    }


INFO "[$local_filename" . ":" . __LINE__ . "]user $user passwd $passwd\n" ;


sub basic_auth($$)
{
  my ($request, $trace) = @_;
    
#$request->authorization_basic(USER_AUTH, PASS_AUTH);
   	
  $request->authorization_basic($user, $passwd);
  my $res=$ua->request($request);

  # Handle the response
  if ($res->is_success) {
    INFO  "[$local_filename" . ":" . __LINE__ . "]Auth Success. status: $res->status_line \n";
    INFO  "[$local_filename" . ":" . __LINE__ . "]Auth Success. content: $res->decoded_content \n";
  } else {
      INFO "[$local_filename" . ":" . __LINE__ . "]Auth Fail. status: $res->status_line \n";
     die  "[$local_filename" . ":" . __LINE__ . "]Auth fail. content: $res->decoded_tontent \n";
}

}

INFO "[$local_filename" . ":" . __LINE__ . "] compileClient";
