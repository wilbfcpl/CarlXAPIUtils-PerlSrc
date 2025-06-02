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
#use constant USER_AUTH => 'frederick';
# use constant PASS_AUTH => 'SwV3QEtjMwSs7fuL';
use constant INSTITUTE_CODE => 1770;
use constant FCPL_BRANCH=>'HDQ';

use constant WAIVE_COMMENT => 'Processing Fee' ;
use constant SSC_PAYTYPE_WAIVE => 'Waive';
use constant SSC_PAYTYPE_PAY => 'Pay';
use constant SSC_PAYTYPE_CANCEL => 'Cancel';
use constant PAY_METHOD=>'Cash';
use constant PAY_AMOUNT=>23.93;
use constant OCCUR => 1;

our ($opt_g,$opt_r,$opt_x);
getopts('gdrx:');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

my $result ;
my $trace;

my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

my $PATRON_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

INFO "[$local_filename" . ":" . __LINE__ . "]$PATRON_FILE";

my $wsdlfile = 'PatronAPInew.wsdl';

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);

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
    
    #    $request->authorization_basic(USER_AUTH, PASS_AUTH);
   	
    $request->authorization_basic($user, $passwd);    
    $ua->request($request);
}

INFO "[$local_filename" . ":" . __LINE__ . "] compileClient";

my $call1 = $wsdl->compileClient('SettleFinesAndFees',  transport_hook => \&basic_auth);

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}

    
my ($patronid, $hashoneseven, $amount, $finedate,$itemid, $name, $status,$btycode,$street1,$notes,$regdate,$editdate,$actdate);

# # Read the header row
# $_ = <>;
# chomp;
# INFO "[$local_filename" . ":" . __LINE__ . "]Read Header Row Record $_";
# ;

my %ResponseStatus;
my %SettleFinesAndFeesRequest;
my %FineOrFee;

%ResponseStatus = (
   Code=>0,
   Severity=>"None",
   ShortMessage=>"No Message",
   LongMessage=>"No Long Message",
   Resolution=>"none"
    );

%FineOrFee = (
         Occur=>OCCUR,
         WaiveComment=>WAIVE_COMMENT,
 PayType =>SSC_PAYTYPE_WAIVE ,
 ResponseStatus=>\%ResponseStatus
 );

%SettleFinesAndFeesRequest =
 (
  SearchType=>'Patron ID',
       FineOrFee=> \%FineOrFee,
       Modifiers => {
       StaffID =>CARLX_ID_WB0,
       EnvBranch =>FCPL_BRANCH ,
      }
      ) ;

# Use MCE::Loop to process lines in parallel
MCE::Loop::init(
    max_workers => 4,
    chunk_size => 1,
    user_error => sub {
        my ($mce, $chunk_id, $error) = @_;
        ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
);


#INFO "[$local_filename" . ":" . __LINE__ . "]Lines array @lines";
mce_loop_f {
    

    chomp;
    
    INFO "[$local_filename" . ":" . __LINE__ . "]Record $_ ";
    my ($patronid, $hashoneseven, $amount, $finedate, $itemid, $name, $status, $btycode, $editdate, $actdate)  = split(/,/);

    $FineOrFee{ItemID}= $hashoneseven;
    $FineOrFee{Amount}= $amount;
    $SettleFinesAndFeesRequest{SearchID}=$patronid;

    my ($result1,$trace1)=$call1->(%SettleFinesAndFeesRequest);

    INFO "[$local_filename" . ":" . __LINE__ . "]Record $_" . " Call Completed";

    if ($trace1->errors) {
        INFO "[$local_filename" . ":" . __LINE__ . "]Trace print " && $trace1->printErrors;
    }
    
}  $PATRON_FILE ;

MCE::Loop::finish;
