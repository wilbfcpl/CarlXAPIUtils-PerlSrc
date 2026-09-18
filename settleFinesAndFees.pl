# Author:  <wblake@CB95043>
# Created: May 25, 2026
# Version: 0.04
#
# Changelog:
# 0.04 (2026-09-18):
#   - The PatronAPI WSDL is now retrieved from the CarlX server over HTTP and parsed straight
#     out of memory; no copy is written to disk. -p keeps selecting production (port 8080)
#     versus test (port 8081). Previously $wsdl was assigned the URL as a bare string, so the
#     later $wsdl->compileClient() calls failed because a string is not an
#     XML::Compile::WSDL11 object. XML::Compile treats a plain string as a filename, so the
#     fetched document is handed to it as a SCALAR ref instead.
#   - Added _load_wsdl_xml(), which GETs the WSDL and returns the raw bytes, plus a fallback to
#     the local WSDL file (PatronAPI.wsdl with -p, otherwise PatronAPInew.wsdl) when the fetch
#     fails, so a network outage does not stop the script from running.
#   - Both CarlX servers now declare ItemBranch in the transaction:Transaction complexType
#     themselves, so the hand-edit described under 0.02 is obsolete. Nothing has to be
#     patched into the fetched WSDL; GetPatronTransactionsResponse items carrying ItemBranch
#     decode straight out of the served schema.
# 0.03 (2026-09-17):
#   - Suppressed the per-record Data::Dumper output of the decoded result, the
#     XML::Compile::SOAP::Trace object and the whole %GetPatronTransactionsResponse hash for
#     successful calls. A successful record now logs a single summary line; the full dumps are
#     emitted only when the call fails (undef result, trace errors, or a non-zero
#     ResponseStatus/Code) or when -g is given.
#   - Added _response_body(), _response_statuses(), _call_failure() and _transactions_summary()
#     helpers to classify a call as success/failure and to build the one-line summary.
# 0.02 (2026-09-17):
#   - Fixed basic_auth() transport_hook to explicitly `return $res;`. Previously the sub's
#     return value fell through to the last INFO() call in its success branch (a truthy
#     scalar, not the HTTP::Response), so XML::Compile::Transport::SOAPHTTP rejected it with
#     "transport_hook must produce a HTTP::Response, got 1" and every SettleFinesAndFees
#     call silently returned an undef result.
#   - Added ItemBranch (xs:short, minOccurs=0) to the transaction:Transaction complexType in
#     PatronAPInew.wsdl/PatronAPI.wsdl, between Title and TransactionBranch, matching the field
#     actually returned by the live CarlX server. Without it, XML::Compile refused to decode
#     any GetPatronTransactionsResponse item (e.g. LostItem) that included ItemBranch.
#     (Superseded in 0.04: the server now declares ItemBranch itself, so this local edit only
#     still matters for the offline fallback copies.)
#   - GetPatronTransactionsResponse item collections (ChargeItems, ClaimedItems, FineItems,
#     HoldItems, LostItems, OverdueItems, ReserveItems, TraceItems, UnavailableHoldItems) are
#     now flattened from XML::Compile's choice-group shape
#     ({ "cho_<ItemType>" => [ { <ItemType> => {...} } ] }) into plain arrayrefs of item
#     hashrefs via _flatten_choice_items().
#
# Usage: perl  settleFinesAndFees.pl [-g] [-p] filename.csv
#
# Usage:  echo "11982022414417,#1770000158859,15.41" | perl .\settleFinesAndFees.pl -g -u frederick -x mnXYEZYE%T5H7mlPEmgb -r
# -g Logging
# -p Production wsdl url and server (port 8080); without it the test instance (port 8081)
# -r read only
# filename.csv hasPatron barcode, hash177 value, fineamount,finedate,item,name,status,btycode,editdate,actdate
##177XXXXX itemid generated after the item goes lost
# Only the patronid and hashoneseven columns matter but the Input CSV file column order goes:
#$patronid, $hashoneseven, $amount, $finedate,$itemid, $name, $status,$btycode,$street1,$notes,$regdate,$editdate
# from file testSettleFinesAndFees.csv
# 11982022317784,#1770000148013,4,2024-02-12,41982017659293,ALMAZAN NATALIE,*,PUBLIC,2024-04-10,2024-04-08
#
# Debug mode- a lot more SOAP messages.
# MCE Loop has error if first line of in file has column label headings
# Fetches the CarlX PatronAPI.wsdl from the server over HTTP and parses it in memory; the local
# copies (PatronAPI.wsdl / PatronAPInew.wsdl) are only used if that fetch fails
#
# SOAPUI tool can provide a sandbox for the WSDL file and PatronAPI requests.
# Note that API call and response return appear to take one second in real time.
#
# Basecamp links to the script development effort
# https://3.basecamp.com/4369994/buckets/14767943/card_tables/cards/8058857119#__recording_8438576637
# https://3.basecamp.com/3903967/buckets/17115720/messages/4834351264#__recording_8438291685

#Fee Settlement via API Patron API settleFinesAndFees
# needs authentication like CirculationAPI

#Perl script sscSettleFinesAndFees fails if the file format is not ISO 8
#github sscSettleFinesAndFees
#https://github.com/wilbfcpl/CarlXPatronAPI/blob/master/sscSettleFinesAndFees.pl
#needs #177 item numbers to work, old item numbers removed after lost status do not work but are good for tracking in CarlX Clients and Discovery
#    $4.00 credits to the accounts.
    
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
Log::Log4perl->easy_init($DEBUG);

use constant PATRON_MODIFIERS_DEBUG_MODE_ON => 1;
use constant PATRON_MODIFIERS_REPORT_MODE_ON => 1;
use constant PATRON_MODIFIERS_STAFFID_WIL => 'wb0';


use constant INSTITUTE_CODE => 1770;
use constant FCPL_BRANCH=>'HDQ';

#Command line input variable handling g debug, p production mode server
# -u user -x password

use constant WAIVE_COMMENT => 'Processing Fee' ;
use constant SSC_PAYTYPE_WAIVE => 'Waive';
use constant SSC_PAYTYPE_PAY => 'Pay';
use constant SSC_PAYTYPE_CANCEL => 'Cancel';
use constant PAY_METHOD=>'Cash';
use constant PAY_AMOUNT=>23.93;
use constant OCCUR => 1;

    
our ($opt_u,$opt_x,$opt_g,$opt_p,$opt_r);
getopts('u:x:gpr');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

my $read_only_mode = ( defined $opt_r ? 1 : 0);

# -g also turns the per-record Data::Dumper traces back on. Without it only failed
# calls are dumped; successful calls log a one line summary instead.
my $verbose_dump = ( defined $opt_g ? 1 : 0);

$Data::Dumper::Indent   = 1;
$Data::Dumper::Sortkeys = 1;

my $result ;
my $trace;

my $local_filename=$0;

$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

# Only used as a fallback when the live WSDL cannot be fetched.
my $wsdlfile =  ( defined $opt_p ?  'PatronAPI.wsdl' : 'PatronAPInew.wsdl');

# -p selects the production CarlX server (8080), otherwise the test instance (8081).
# Both serve a self contained document - every xs:schema is inlined and there are no
# xs:import/@schemaLocation references - so one HTTP GET is enough and no copy of the
# WSDL has to be kept on disk.
my $wsdlurl = ( defined $opt_p ? 'http://fcplapp.fcpl.org:8080/CarlXAPI/PatronAPI.wsdl' : 'http://fcplapp.fcpl.org:8081/CarlXAPI/PatronAPI.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlurl: $wsdlurl (fallback wsdlfile: $wsdlfile)";

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);#

# Fetch the WSDL document as raw bytes. ->content rather than ->decoded_content is
# deliberate: the document carries its own <?xml ... encoding="..."?> declaration and
# XML::LibXML wants the undecoded octets so that declaration stays truthful.
# Returns undef (after logging) when the server cannot be reached.
sub _load_wsdl_xml {
    my ($url) = @_;
    INFO "[$local_filename" . ":" . __LINE__ . "]Fetching WSDL from $url";
    my $res = $ua->get($url);
    unless ($res->is_success) {
	WARN "[$local_filename" . ":" . __LINE__ . "]WSDL fetch failed: " . $res->status_line;
	return undef;
    }
    return $res->content;
}

my $wsdl;
my $wsdl_xml = _load_wsdl_xml($wsdlurl);

if (defined $wsdl_xml) {
    # XML::Compile takes a plain string as a filename; a SCALAR ref is parsed as XML text,
    # which is what keeps the fetched WSDL in memory instead of on disk.
    $wsdl = XML::Compile::WSDL11->new(\$wsdl_xml);
    INFO "[$local_filename" . ":" . __LINE__ . "]wsdl source: $wsdlurl (in memory)";
}
else {
    WARN "[$local_filename" . ":" . __LINE__ . "]Falling back to local wsdlfile: $wsdlfile";
    $wsdl = XML::Compile::WSDL11->new($wsdlfile);
}

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

# my $user = prompt("Username:") ;

my $user = $opt_u ;
my $passwd = $opt_x;


# my $passwd = prompt ("Password:") ;

unless ( (defined $user) and (defined $passwd))
    {
	 die "[$local_filename" . ":" . __LINE__ . "]usage: settleFees -u user  -x passwd \n"
    }


INFO "[$local_filename" . ":" . __LINE__ . "]user $user passwd $passwd\n" ;


sub basic_auth($$)
{
  my ($request, $trace) = @_;
    
   	
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

  # transport_hook must return the HTTP::Response object, otherwise
  # XML::Compile::Transport::SOAPHTTP fails with
  # "transport_hook must produce a HTTP::Response, got {resp}".
  return $res;
}

my $call1 = $wsdl->compileClient('SettleFinesAndFees',  transport_hook => \&basic_auth);
my $call2 = $wsdl->compileClient('GetPatronTransactions');

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdlurl \n" ;
}



my %ResponseStatus;
my %SettleFinesAndFeesRequest;
my %FineOrFee;
my %GetPatronTransactionsRequest;
my %GetPatronTransactionsResponse;

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
       DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
       ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
       StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
       EnvBranch =>FCPL_BRANCH
		    }
      ) ;


%GetPatronTransactionsRequest =
 (

  SearchType=>'Patron ID',
  Modifiers => {
      DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
      ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
      StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
      EnvBranch =>FCPL_BRANCH		    }
      ) ;

# Mirrors the GetPatronTransactionsResponse element from the CarlX PatronAPI WSDL
# (patronAPI:GetPatronTransactionsResponse extends transaction:PatronTransactionSummary).
# ResponseStatuses is an arrayref of response:ResponseStatus hashrefs.
# Each *Items key is an arrayref of the corresponding transaction:*Item hashrefs
# (ChargeItem, ClaimedItem, FineItem, HoldItem, LostItem, OverdueItem, ReserveItem,
# TraceItem, UnavailableHoldItem), each of which extends transaction:Transaction.
# transaction:Transaction includes ItemBranch (xs:short, between Title and
# TransactionBranch) natively in the served WSDL, so every flattened item hashref below
# carries an ItemBranch field alongside Branch.
%GetPatronTransactionsResponse = (
    ResponseStatuses      => [],    # response:ResponseStatus[]
    PatronID              => undef,
    AlternateID           => undef,
    GUID                  => undef,
    ChargedItemsCount     => undef,
    ClaimedItemsCount     => undef,
    FineItemsCount        => undef,
    HoldItemsCount        => undef,
    LostItemsCount        => undef,
    OverdueItemsCount     => undef,
    ReserveItemsCount     => undef,
    TraceItemsCount       => undef,
    UnavailableHoldsCount => undef,
    FineTotal             => undef,
    LostItemFeeTotal      => undef,
    ChargeItems           => [],    # transaction:ChargeItem[]
    ClaimedItems          => [],    # transaction:ClaimedItem[]
    FineItems             => [],    # transaction:FineItem[]
    HoldItems             => [],    # transaction:HoldItem[]
    LostItems             => [],    # transaction:LostItem[]
    OverdueItems          => [],    # transaction:OverdueItem[]
    ReserveItems          => [],    # transaction:ReserveItem[]
    TraceItems            => [],    # transaction:TraceItem[]
    UnavailableHoldItems  => [],    # transaction:UnavailableHoldItem[]
    );

# XML::Compile decodes each *Items choice group (maxOccurs="unbounded" xs:choice) as
# { "cho_<ItemType>" => [ { <ItemType> => {...} }, ... ] } rather than a plain array.
# Unwrap that into a flat arrayref of the inner item hashrefs (each including the
# transaction:Transaction fields, e.g. ItemBranch, TransactionBranch, ItemNumber, etc.)
sub _flatten_choice_items {
    my ($group, $item_name) = @_;
    return [] unless ref $group eq 'HASH';
    my $entries = $group->{"cho_$item_name"};
    return [] unless ref $entries eq 'ARRAY';
    return [ map { $_->{$item_name} } @$entries ];
}

# XML::Compile::WSDL11 nests the decoded body under the response message part name
# (e.g. GetPatronTransactionsResponse). Return the inner hashref carrying ResponseStatuses.
sub _response_body {
    my ($res) = @_;
    return undef unless ref $res eq 'HASH';
    return $res if exists $res->{ResponseStatuses};
    for my $part (values %$res) {
	return $part if ref $part eq 'HASH' && exists $part->{ResponseStatuses};
    }
    return $res;
}

# ResponseStatuses is either already flattened (arrayref) or still in XML::Compile's
# choice shape: { cho_ResponseStatus => [ { ResponseStatus => {...} }, ... ] }.
sub _response_statuses {
    my ($body) = @_;
    return () unless ref $body eq 'HASH';
    my $statuses = $body->{ResponseStatuses};
    return grep { ref $_ eq 'HASH' } @$statuses if ref $statuses eq 'ARRAY';
    if (ref $statuses eq 'HASH') {
	my $entries = $statuses->{cho_ResponseStatus};
	return () unless ref $entries eq 'ARRAY';
	return grep { ref $_ eq 'HASH' }
	       map  { ref $_ eq 'HASH' ? ( $_->{ResponseStatus} || $_ ) : () } @$entries;
    }
    return ();
}

# Returns a human readable reason when a call did not succeed, undef when it did.
# A call is successful when it decoded to a hashref, the trace reports no errors and
# every ResponseStatus carries Code 0.
sub _call_failure {
    my ($res, $trace) = @_;
    return 'no decoded result returned' unless ref $res eq 'HASH';
    return 'SOAP/transport errors reported in trace' if $trace && $trace->errors;
    my @bad = grep { defined $_->{Code} && $_->{Code} != 0 } _response_statuses(_response_body($res));
    return undef unless @bad;
    return join '; ',
	map { sprintf '%s %s: %s', ( $_->{Severity} // 'ERROR' ), ( $_->{Code} // '?' ), ( $_->{ShortMessage} // '' ) } @bad;
}

# One line replacement for the full Dumper(%GetPatronTransactionsResponse) output.
sub _transactions_summary {
    my ($data) = @_;
    return 'no transaction data' unless ref $data eq 'HASH';
    return sprintf(
	'PatronID %s GUID %s fines %s/%s lost %s/%s charged %s overdue %s holds %s',
	$data->{PatronID}          // '?',
	$data->{GUID}              // '?',
	$data->{FineItemsCount}    // 0,
	$data->{FineTotal}         // 0,
	$data->{LostItemsCount}    // 0,
	$data->{LostItemFeeTotal}  // 0,
	$data->{ChargedItemsCount} // 0,
	$data->{OverdueItemsCount} // 0,
	$data->{HoldItemsCount}    // 0,
	);
}

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
mce_loop {
    
    my ($mce, $chunk_ref, $chunk_id) = @_;

       foreach my $line (@$chunk_ref) {
        chomp $line;
        next if $line eq '';  # Skip empty lines
	INFO "[$local_filename" . ":" . __LINE__ . "]Record $line";

    my ($patronid, $hashoneseven, $amount)  = split(/,/, $line);


	if ($read_only_mode==0)
	{   $FineOrFee{ItemID}= $hashoneseven;
	    $FineOrFee{Amount}= $amount;
	    $SettleFinesAndFeesRequest{SearchID}=$patronid;
	   ($result,$trace)=$call1->(%SettleFinesAndFeesRequest);
	}
	else {
	    $GetPatronTransactionsRequest{SearchID}=$patronid;
	    ($result,$trace)=$call2->(%GetPatronTransactionsRequest);

	    if (ref $result eq 'HASH') {
		# XML::Compile::WSDL11 returns the decoded body nested under a key
		# matching the response message part name (GetPatronTransactionsResponse)
		# rather than flattened, so unwrap it before merging into our flat hash.
		my $response_data = (ref $result->{GetPatronTransactionsResponse} eq 'HASH')
		    ? $result->{GetPatronTransactionsResponse}
		    : $result;
		%GetPatronTransactionsResponse = (
		    %GetPatronTransactionsResponse,
		    %$response_data,
		    ChargeItems          => _flatten_choice_items($response_data->{ChargeItems}, 'ChargeItem'),
		    ClaimedItems         => _flatten_choice_items($response_data->{ClaimedItems}, 'ClaimedItem'),
		    FineItems            => _flatten_choice_items($response_data->{FineItems}, 'FineItem'),
		    HoldItems            => _flatten_choice_items($response_data->{HoldItems}, 'HoldItem'),
		    LostItems            => _flatten_choice_items($response_data->{LostItems}, 'LostItem'),
		    OverdueItems         => _flatten_choice_items($response_data->{OverdueItems}, 'OverdueItem'),
		    ReserveItems         => _flatten_choice_items($response_data->{ReserveItems}, 'ReserveItem'),
		    TraceItems           => _flatten_choice_items($response_data->{TraceItems}, 'TraceItem'),
		    UnavailableHoldItems => _flatten_choice_items($response_data->{UnavailableHoldItems}, 'UnavailableHoldItem'),
		    );
		INFO "[$local_filename" . ":" . __LINE__ . "]GetPatronTransactions: "
		    . _transactions_summary(\%GetPatronTransactionsResponse);
		DEBUG "[$local_filename" . ":" . __LINE__ . "]GetPatronTransactionsResponse: "
		    . Dumper(\%GetPatronTransactionsResponse)
		    if $verbose_dump;
	    }
	}

    # Only dump the decoded result and the (very large) SOAP trace when the call
    # actually failed, or when -g asked for the verbose traces.
    my $failure = _call_failure($result, $trace);

    if (defined $failure) {
	ERROR "[$local_filename" . ":" . __LINE__ . "]Record $line FAILED: $failure";
	ERROR "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result);
	ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace);
	INFO $trace->printErrors if $trace && $trace->errors;
    }
    else {
	INFO "[$local_filename" . ":" . __LINE__ . "]Record $line Call Completed";
	DEBUG "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result) if $verbose_dump;
	DEBUG "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace)   if $verbose_dump;
    }
       }

    } <> ;

MCE::Loop::finish;
