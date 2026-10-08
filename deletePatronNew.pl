# Author:  <wblake@CB95043>
# Created: May 25, 2026
# Version: 0.05
#
# Changelog:
# 0.05 (2026-10-08):
#   - Added a DeletePatron response data structure (_new_delete_patron_response) plus the
#     Data::Dumper code to print what the server actually sent back
#     (_dump_delete_patron_response). The WSDL served at $wsdlurl declares the DeletePatron
#     operation with a wsdl:input only - there is no wsdl:output - so XML::Compile compiles it
#     as a one way call and $call1->() hands back no decoded body even though the server does
#     reply with a patronAPI:GenericResponse (ResponseStatuses only). _decode_generic_response()
#     therefore takes the raw envelope off the XML::Compile trace and decodes it with a reader
#     compiled from the same in-memory WSDL (sch0:GenericResponse); if that reader cannot be
#     built it falls back to pulling ResponseStatus elements out by local-name with XML::LibXML.
#   - DeletePatron now has its own success/failure path in the mce_loop
#     (_delete_patron_failure/_delete_patron_summary) instead of going through _call_failure(),
#     which would have flagged every one way call as 'no decoded result returned'.
# 0.04 (2026-09-18):
#   - The PatronAPI WSDL is now retrieved from the CarlX server over HTTP and parsed straight
#     out of memory;  -p keeps selecting production (port 8080)
#     versus test (port 8081). Previously $wsdl was assigned the URL as a bare string, so the
#     later $wsdl->compileClient() calls failed because a string is not an
#     XML::Compile::WSDL11 object. XML::Compile treats a plain string as a filename, so the
#     fetched document is handed to it as a SCALAR ref instead.
#   - Added _load_wsdl_xml(), which GETs the WSDL and returns the raw bytes, plus a fallback to
#     # 0.03 (2026-09-17):

#     ResponseStatus/Code) or when -g is given.
#   - Added _response_body(), _response_statuses(), _call_failure() and _transactions_summary()
#     helpers to classify a call as success/failure and to build the one-line summary.
# 0.02 (2026-09-17):

#     return value fell through to the last INFO() call in its success branch (a truthy
#     scalar, not the HTTP::Response), so XML::Compile::Transport::SOAPHTTP rejected it with
#     now flattened from XML::Compile's choice-group shape
#     ({ "cho_<ItemType>" => [ { <ItemType> => {...} } ] }) into plain arrayrefs of item
#     hashrefs via _flatten_choice_items().
#
# Usage: perl  deletePatronsNew.pl [-g] [-p] filename.csv
#
# Usage:  echo "11982022414417 | perl .\deletePatronNew.pl -g -u frederick -x mnXYEZYE%T5H7mlPEmgb -r
# -g Logging
# -p Production wsdl url, server (port 8080); without test instance (port 8081)
# -r read only
# filename.csv hasPatron 
# Only the patronid columns matter but the Input CSV file column order goes:
#$patronid
# 11982022317784#
# Debug mode- a lot more SOAP messages.
# MCE Loop has error if first line of in file has column label headings
# Fetches the CarlX PatronAPI.wsdl from server over HTTP and parses in memory; 
#
# SOAPUI tool can provide a sandbox for the WSDL file and PatronAPI requests.
# Note that API call and response return appear to take one second in real time.
#
# Basecamp links to the script development effort
# https://3.basecamp.com/4369994/buckets/14767943/card_tables/cards/8058857119#__recording_8438576637
# https://3.basecamp.com/3903967/buckets/17115720/messages/4834351264#__recording_8438291685


#github deletePatronNew.pl
#https://github.com/wilbfcpl/CarlXPatronAPI/blob/master/sscSettleFinesAndFees.pl


    
use strict;
use warnings FATAL => 'all';
use diagnostics;

use LWP::UserAgent;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;
use XML::Compile::Util qw/pack_type/;
use XML::LibXML;
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

# Target namespace of the PatronAPI schema inside the WSDL; needed to name the
# GenericResponse element that DeletePatron replies with.
use constant PATRON_API_NS => 'http://tlcdelivers.com/cx/schemas/patronAPI';


    
our ($opt_g,$opt_p,$opt_r);
getopts('gpr');

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


my $wsdlurl = ( defined $opt_p ? 'http://fcplapp.fcpl.org:8080/CarlXAPI/PatronAPI.wsdl' : 'http://fcplapp.fcpl.org:8081/CarlXAPI/PatronAPI.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlurl: $wsdlurl)";

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);#

# Fetch the WSDL document raw bytes. ->content rather than ->decoded_content is
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
    # XML::Compile takes a plain string filename; a SCALAR ref is parsed as XML text,
    # which is what keeps the fetched WSDL in memory instead of on disk.
    $wsdl = XML::Compile::WSDL11->new(\$wsdl_xml);
    INFO "[$local_filename" . ":" . __LINE__ . "]wsdl src: $wsdlurl (memory)";
}

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}


my $call1 = $wsdl->compileClient('DeletePatron');
my $call2 = $wsdl->compileClient('GetPatronInformation');

unless ( defined $call1 and defined $call2 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdlurl \n" ;
}



my %ResponseStatus;
my %DeletePatronRequest;
my %GetPatronInformationRequest;

%ResponseStatus = (
   Code=>0,
   Severity=>"None",
   ShortMessage=>"No Message",
   LongMessage=>"No Long Message",
   Resolution=>"none"
    );

%DeletePatronRequest =
 (
       SearchType=>'Patron ID',
       Modifiers => {
       DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
       ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
       StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
       EnvBranch =>FCPL_BRANCH
		    }
 ) ;

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


# XML::Compile::WSDL11 nests decoded body under the response message part name
# Return the inner hashref carrying ResponseStatuses.
sub _response_body {
    my ($res) = @_;
    return undef unless ref $res eq 'HASH';
    return $res if exists $res->{ResponseStatuses};
    for my $part (values %$res) {
	return $part if ref $part eq 'HASH' && exists $part->{ResponseStatuses};
    }
    return $res;
}

# ResponseStatuses either already flattend (arrayref) or still in XML::Compile's
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

# Returns a human readable reason when call did not succeed, undef when it did.
# A call is successful when decoded to hashref, the trace reports no errors and
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
# (or a plain arrayref once flattened). Return inner item hashrefs either way.
sub _choice_items {
    my ($container, $item) = @_;
    return () unless ref $container;
    my $entries = ref $container eq 'HASH' ? $container->{"cho_$item"} : $container;
    return () unless ref $entries eq 'ARRAY';
    return grep { ref $_ eq 'HASH' }
	   map  { ref $_ eq 'HASH' ? ( $_->{$item} || $_ ) : () } @$entries;
}

# Decode SOAP response of GetPatronInformation into flat hash described above.
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
# showing. The nested Addresses/UDFs/Notes are dumped separately because
# they are the parts that are easiest to lose inside the full response hash.
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

# ---------------------------------------------------------------------------
# DeletePatron response handling
#
# The WSDL at $wsdlurl declares <wsdl:operation name="DeletePatron"> with a
# wsdl:input only, so XML::Compile compiles a one way call: $call1->() returns no
# decoded body. The server nevertheless answers with
#   <GenericResponse><ResponseStatuses><ResponseStatus>...
# so the response has to be read off the trace instead of the return value.
# ---------------------------------------------------------------------------

# Flat view of a DeletePatron response. ResponseStatuses holds every
# ResponseStatus hashref the server sent ({ Code, Severity, ShortMessage,
# LongMessage, Resolution } per the response:ResponseStatus complexType); the
# ResponseStatus* scalars are a copy of the first one for convenience.
# PatronID is the SearchID that was submitted, not something the server returns.
sub _new_delete_patron_response {
    return (
	PatronID                   => undef,
	ResponseStatusCode         => undef,
	ResponseStatusSeverity     => undef,
	ResponseStatusShortMessage => undef,
	ResponseStatusLongMessage  => undef,
	ResponseStatusResolution   => undef,
	ResponseStatuses           => [],
    );
}

# Reader for the sch0:GenericResponse element, compiled out of the same in-memory
# WSDL that was fetched from $wsdlurl. Compiled once and cached; 0 means the
# compile failed and the XPath fallback in _decode_generic_response() is used.
my $generic_response_reader;
sub _generic_response_reader {
    return $generic_response_reader if defined $generic_response_reader;
    my $type = pack_type(PATRON_API_NS, 'GenericResponse');
    $generic_response_reader = eval { $wsdl->compile(READER => $type) };
    unless ($generic_response_reader) {
	WARN "[$local_filename" . ":" . __LINE__ . "]Could not compile a reader for $type: $@";
	$generic_response_reader = 0;
    }
    return $generic_response_reader;
}

# Decode the DeletePatron reply straight out of the raw SOAP envelope on the trace.
# Returns a hashref shaped like a decoded response body (i.e. carrying
# ResponseStatuses, either in XML::Compile's cho_ResponseStatus form or as a plain
# arrayref from the fallback), or undef when nothing usable came back.
sub _decode_generic_response {
    my ($trace) = @_;

    my $xml = _response_xml($trace);
    return undef unless defined $xml && length $xml;

    my $doc = eval { XML::LibXML->new->parse_string($xml) };
    unless ($doc) {
	WARN "[$local_filename" . ":" . __LINE__ . "]Could not parse the SOAP response: $@";
	return undef;
    }

    # First element child of soap:Body is the GenericResponse (or a soap:Fault).
    my ($body) = $doc->findnodes('/*[local-name()="Envelope"]/*[local-name()="Body"]');
    my ($payload) = $body ? grep { $_->isa('XML::LibXML::Element') } $body->childNodes : ();

    if ($payload && $payload->localname eq 'GenericResponse') {
	if (my $reader = _generic_response_reader()) {
	    my $data = eval { $reader->($payload) };
	    return $data if ref $data eq 'HASH';
	    WARN "[$local_filename" . ":" . __LINE__ . "]GenericResponse reader failed: $@" if $@;
	}
    }

    # Fallback: no schema, just lift every ResponseStatus out of the document.
    my @statuses;
    for my $node ($doc->findnodes('//*[local-name()="ResponseStatus"]')) {
	my %status;
	for my $field (grep { $_->isa('XML::LibXML::Element') } $node->childNodes) {
	    $status{ $field->localname } = $field->textContent;
	}
	push @statuses, \%status if %status;
    }

    return @statuses ? { ResponseStatuses => \@statuses } : undef;
}

# Build the flat DeletePatron response hash described above. $res is whatever
# $call1->() returned (normally nothing, see the note at the top of this section# ) so trace is the real source of the data.
sub _parse_delete_patron_response {
    my ($patronid, $res, $trace) = @_;

    my %r = _new_delete_patron_response();
    $r{PatronID} = $patronid;

    my $body = ref $res eq 'HASH' ? _response_body($res) : undef;
    $body = _decode_generic_response($trace)
	unless ref $body eq 'HASH' && exists $body->{ResponseStatuses};

    return %r unless ref $body eq 'HASH';

    $r{ResponseStatuses} = [ _response_statuses($body) ];

    if (my $first = $r{ResponseStatuses}[0]) {
	$r{ResponseStatusCode}         = $first->{Code};
	$r{ResponseStatusSeverity}     = $first->{Severity};
	$r{ResponseStatusShortMessage} = $first->{ShortMessage};
	$r{ResponseStatusLongMessage}  = $first->{LongMessage};
	$r{ResponseStatusResolution}   = $first->{Resolution};
    }

    return %r;
}

# Returns a human readable reason when the DeletePatron call did not succeed,
# undef when it did. _call_failure() cannot be used here: it treats a missing
# decoded result as a failure, which is the normal case for this one way call.
sub _delete_patron_failure {
    my ($r, $trace) = @_;
    return 'SOAP/transport errors reported in trace' if $trace && $trace->errors;
    return 'no ResponseStatus returned by the server' unless @{ $r->{ResponseStatuses} };
    my @bad = grep { defined $_->{Code} && $_->{Code} != 0 } @{ $r->{ResponseStatuses} };
    return undef unless @bad;
    return join '; ',
	map { sprintf '%s %s: %s', ( $_->{Severity} // 'ERROR' ), ( $_->{Code} // '?' ), ( $_->{ShortMessage} // '' ) } @bad;
}

# Readable Data::Dumper rendering of one DeletePatron response. As in
# _dump_patron_response(), Data::Dumper->Dump labels each structure instead of
# using the default $VAR1, and the raw envelope is appended because it is only
# complete view of what the server sent for this operation.
sub _dump_delete_patron_response {
    my ($res, $parsed, $trace) = @_;

    my @values = ($res);
    my @names  = ('DeletePatronResponse');

    if (ref $parsed eq 'HASH') {
	push @values, $parsed, $parsed->{ResponseStatuses};
	push @names,  qw( DeletePatronFields DeletePatronResponseStatuses );
    }

    my $dump = "\n" . Data::Dumper->Dump(\@values, \@names);

    my $xml = _response_xml($trace);
    $dump .= "\n--- raw SOAP response ---\n$xml\n--- end raw SOAP response ---\n"
	if defined $xml;

    return $dump;
}

# One line, human readable summary of a parsed DeletePatron response.
sub _delete_patron_summary {
    my (%r) = @_;
    return join ' | ',
	map { sprintf '%s=%s', $_->[0], ( $_->[1] // '' ) }
	( [ PatronID => $r{PatronID} ],
	  [ Code => $r{ResponseStatusCode} ],
	  [ Severity => $r{ResponseStatusSeverity} ],
	  [ ShortMessage => $r{ResponseStatusShortMessage} ],
	  [ LongMessage => $r{ResponseStatusLongMessage} ],
	  [ Resolution => $r{ResponseStatusResolution} ],
	  [ Statuses => scalar @{ $r{ResponseStatuses} } ] );
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


	if ($read_only_mode==0)
	{    $DeletePatronRequest{SearchID}=$patronid;
	   ($result,$trace)=$call1->(%DeletePatronRequest);

	    # DeletePatron is a one way operation in the WSDL, so the response has to be
	    # decoded from the trace rather than from $result.
	    my %deleted = _parse_delete_patron_response($patronid, $result, $trace);
	    my $delete_failure = _delete_patron_failure(\%deleted, $trace);

	    if (defined $delete_failure) {
		ERROR "[$local_filename" . ":" . __LINE__ . "]Record $line DeletePatron FAILED: $delete_failure";
		ERROR "[$local_filename" . ":" . __LINE__ . "]Response for $line:"
		    . _dump_delete_patron_response($result, \%deleted, $trace);
		INFO $trace->printErrors if $trace && $trace->errors;
	    }
	    else {
		INFO "[$local_filename" . ":" . __LINE__ . "]Record $line DeletePatron: "
		    . _delete_patron_summary(%deleted);
		DEBUG "[$local_filename" . ":" . __LINE__ . "]Response for $line:"
		    . _dump_delete_patron_response($result, \%deleted, $trace) if $verbose_dump;
	    }

	    next;
	}
	else {
	    $GetPatronInformationRequest{SearchID}=$patronid;
	   ($result,$trace)=$call2->(%GetPatronInformationRequest);
	}


    # Only dump the decoded result and (large) SOAP trace when the call
    # actually failed, or when -g asked for the verbose traces.
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
	INFO "[$local_filename" . ":" . __LINE__ . "]Record $line Call Completed";
	DEBUG "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result) if $verbose_dump;
	DEBUG "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace)   if $verbose_dump;
    }

       }
  } <> ;

MCE::Loop::finish;
