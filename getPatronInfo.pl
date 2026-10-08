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
#   - Added _load_wsdl_xml(), which GETs the WSDL and returns the raw bytes#
#     successful calls. A successful record now logs a single summary line; the full dumps are
#     emitted only when the call fails (undef result, trace errors, or a non-zero
#     ResponseStatus/Code) or when -g is given.
#   - Added _call_failure()
#
# Usage: perl getPatronInfo.pl [-g] [-p] filename.csv
#
# Usage:  echo "11982022414417" | perl .\getPatronInfo.pl  -g
# -g Logging
# -p Production wsdl url and server (port 8080); without it the test instance (port 8081)
# filename.csv has Patron barcodes
# Only the patronid matters, other csv columns ignored
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

#Perl scripts mysteriously fails if the input file format is not ISO 8
#github

    
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


use constant OCCUR => 1;

    
our ($opt_g,$opt_p);
getopts('gp');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';


# -g also turns the per-record Data::Dumper traces back on.
# calls are dumped; successful calls log a one line summary instead.
my $verbose_dump = ( defined $opt_g ? 1 : 0);

$Data::Dumper::Indent   = 1;
$Data::Dumper::Sortkeys = 1;
# Useqq quotes control characters instead of emitting them raw, which keeps the
# CarlX text fields (notes especially) on one line each in the log.
$Data::Dumper::Useqq    = 1;

my $result ;
my $trace;

my $local_filename=$0;

$local_filename =~ s/.+\\([A-z]+.pl)/$1/;


# -p selects the production CarlX server (8080), otherwise the test instance (8081).
# Both serve a self contained document - every xs:schema is inlined and there are no
# xs:import/@schemaLocation references - so one HTTP GET is enough and no copy of the
# WSDL has to be kept on disk.
my $wsdlurl = ( defined $opt_p ? 'http://fcplapp.fcpl.org:8080/CarlXAPI/PatronAPI.wsdl' : 'http://fcplapp.fcpl.org:8081/CarlXAPI/PatronAPI.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlurl: $wsdlurl";

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

unless (defined $wsdl_xml)
  { die "[$local_filename" . ":" . __LINE__ . "]Failed wsdl load $wsdlurl \n"; }

# XML::Compile takes a plain string as a filename; a SCALAR ref is parsed as XML text,
    # which is what keeps the fetched WSDL in memory instead of on disk.
    $wsdl = XML::Compile::WSDL11->new(\$wsdl_xml);
    INFO "[$local_filename" . ":" . __LINE__ . "]wsdl source: $wsdlurl (in memory)";


unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}


my $call1 = $wsdl->compileClient('GetPatronInformation');

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdlurl \n" ;
}

my %ResponseStatus;
my %GetPatronInformationRequest;

%ResponseStatus = (
   Code=>0,
   Severity=>"None",
   ShortMessage=>"No Message",
   LongMessage=>"No Long Message",
   Resolution=>"none"
    );

%GetPatronInformationRequest =
 (
       SearchType=>'Patron ID',
       Modifiers => {
       DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
       ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
       StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
       EnvBranch =>FCPL_BRANCH
		    }
      ) ;

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

# Returns human readable reason when call did not succeed, undef when it did.
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


# Flat view of a GetPatronInformationResponse. Every key is filled in by
# _parse_patron_response(); fields the server omitted (all Patron elements are
# minOccurs=0) stay undef. Field names follow the Patron complexType in the WSDL.
#   ResponseStatusCode/Severity/ShortMessage  first ResponseStatus entry
#   Addresses  arrayref of { Type, Street, City, State, PostalCode }
#   UDFs       hashref of UserDefinedField Field => Value
#   Notes      arrayref of { NoteID, NoteType, NoteText, StaffID, NoteTimestamp }
sub _new_patron_response {
    return (
	ResponseStatusCode      => undef,
	ResponseStatusSeverity  => undef,
	ResponseStatusMessage   => undef,
	PatronID                => undef,
	AltId                   => undef,
	FirstName               => undef,
	MiddleName              => undef,
	LastName                => undef,
	SuffixName              => undef,
	FullName                => undef,
	LegalName               => undef,
	PatronType              => undef,
	PatronStatusCode        => undef,
	BirthDate               => undef,
	Phone1                  => undef,
	Phone2                  => undef,
	PhoneType               => undef,
	Email                   => undef,
	EmailNotices            => undef,
	EmailReceiptFlag        => undef,
	SendHoldAvailableFlag   => undef,
	SendComingDueFlag       => undef,
	CollectionStatus        => undef,
	LastActionLetterStatus  => undef,
	LoanHistoryOptInFlag    => undef,
	RegistrationDate        => undef,
	ExpirationDate          => undef,
	LastEditDate            => undef,
	LastEditedBy            => undef,
	LastActionDate          => undef,
	SelfServeActivityDate   => undef,
	Language                => undef,
	RegBranch               => undef,
	DefaultBranch           => undef,
	PreferredBranch         => undef,
	PreferredAddress        => undef,
	RegisteredBy            => undef,
	GeneralUserID           => undef,
	SponsorName             => undef,
	Addresses               => [],
	UDFs                    => {},
	Notes                   => [],
    );
}

# XML::Compile turns an xs:choice with maxOccurs>1 into
#   { cho_<Item> => [ { <Item> => {...} }, ... ] }
# (or a plain arrayref once flattened). Return the inner item hashrefs either way.
sub _choice_items {
    my ($container, $item) = @_;
    return () unless ref $container;
    my $entries = ref $container eq 'HASH' ? $container->{"cho_$item"} : $container;
    return () unless ref $entries eq 'ARRAY';
    return grep { ref $_ eq 'HASH' }
	   map  { ref $_ eq 'HASH' ? ( $_->{$item} || $_ ) : () } @$entries;
}

# Decode the SOAP response of GetPatronInformation into the flat hash described above.
# Returns an empty list when $res is not a decoded hashref.
sub _parse_patron_response {
    my ($res) = @_;
    my %r = _new_patron_response();
    return () unless ref $res eq 'HASH';

    my $body = _response_body($res);
    return %r unless ref $body eq 'HASH';

    my ($status) = _response_statuses($body);
    if ($status) {
	$r{ResponseStatusCode}     = $status->{Code};
	$r{ResponseStatusSeverity} = $status->{Severity};
	$r{ResponseStatusMessage}  = $status->{ShortMessage};
    }

    my $patron = $body->{Patron};
    return %r unless ref $patron eq 'HASH';

    # Scalar Patron elements are copied straight across.
    for my $key (grep { !ref $r{$_} && $_ !~ /^ResponseStatus/ } keys %r) {
	$r{$key} = $patron->{$key};
    }

    $r{Addresses} = [ _choice_items($patron->{Addresses}, 'Address') ];

    # Look UDFs up by name; the position of a field can differ between records.
    for my $udf (_choice_items($patron->{UserDefinedFields}, 'UserDefinedField')) {
	$r{UDFs}{ $udf->{Field} } = $udf->{Value} if defined $udf->{Field};
    }

    my $notes = $patron->{Notes};
    $r{Notes} = ref $notes eq 'ARRAY' ? [ grep { ref $_ eq 'HASH' } @$notes ]
	      : ref $notes eq 'HASH'  ? [ $notes ] : [];

    return %r;
}

# Raw SOAP envelope the server sent back, taken from the XML::Compile trace.
# This is the most readable view of a GetPatronInformation response when the
# shape of the decoded hash is in question. Returns undef when unavailable.
sub _response_xml {
    my ($trace) = @_;
    return undef unless $trace && $trace->can('response');
    my $http = $trace->response;
    return undef unless $http;
    my $xml = eval { $http->decoded_content };
    return $xml;
}

# Readable Data::Dumper rendering of one GetPatronInformation response.
# Data::Dumper->Dump labels each structure ($GetPatronInformationResponse,
# $PatronFields, ...) instead of the default $VAR1, so the log says what it is
# showing. The nested Addresses/UDFs/Notes are dumped separately because they are
# the parts that are easiest to lose inside the full response hash.
sub _dump_patron_response {
    my ($res, $patron, $trace) = @_;

    my @values = ($res);
    my @names  = ('GetPatronInformationResponse');

    if (ref $patron eq 'HASH') {
	push @values, $patron, $patron->{Addresses}, $patron->{UDFs}, $patron->{Notes};
	push @names,  qw( PatronFields PatronAddresses PatronUDFs PatronNotes );
    }

    my $dump = "\n" . Data::Dumper->Dump(\@values, \@names);

    my $xml = _response_xml($trace);
    $dump .= "\n--- raw SOAP response ---\n$xml\n--- end raw SOAP response ---\n"
	if defined $xml;

    return $dump;
}

# One line, human readable summary of a parsed response.
sub _patron_summary {
    my (%r) = @_;
    my $street = @{ $r{Addresses} } ? ( $r{Addresses}[0]{Street} // '' ) : '';
    return join ' | ',
	map { sprintf '%s=%s', $_->[0], ( $_->[1] // '' ) }
	( [ PatronID => $r{PatronID} ],
	  [ FullName => $r{FullName} ],
	  [ Status => $r{PatronStatusCode} ],
	  [ Type => $r{PatronType} ],
	  [ DefaultBranch => $r{DefaultBranch} ],
	  [ Registered => $r{RegistrationDate} ],
	  [ Expires => $r{ExpirationDate} ],
	  [ Street => $street ],
	  [ UDFs => join( ',', map { "$_:" . ( $r{UDFs}{$_} // '' ) } sort keys %{ $r{UDFs} } ) ] );
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

    my ($patronid)  = split(/,/, $line);

	    $GetPatronInformationRequest{SearchID}=$patronid;
	   ($result,$trace)=$call1->(%GetPatronInformationRequest);

    # The decoded response is always dumped in labelled, readable form; the (very
    # large) SOAP trace is dumped only on failure or when -g asked for it.
    my $failure = _call_failure($result, $trace);
    my %patron  = _parse_patron_response($result);

    if (defined $failure) {
	ERROR "[$local_filename" . ":" . __LINE__ . "]Record $line FAILED: $failure";
	ERROR "[$local_filename" . ":" . __LINE__ . "]Response for $line:"
	    . _dump_patron_response($result, (%patron ? \%patron : undef), $trace);
	ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace);
	INFO $trace->printErrors if $trace && $trace->errors;
    }
    else {
	INFO "[$local_filename" . ":" . __LINE__ . "]Record $line Call Completed: " . _patron_summary(%patron);
	# Labelled dump of the decoded GetPatronInformation response plus the raw
	# SOAP envelope it came from.
	INFO "[$local_filename" . ":" . __LINE__ . "]Response for $line:"
	    . _dump_patron_response($result, \%patron, $trace);
	DEBUG "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace) if $verbose_dump;
    }

   }
  } <> ;

MCE::Loop::finish;
