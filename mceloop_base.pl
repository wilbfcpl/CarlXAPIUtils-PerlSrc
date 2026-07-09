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



# Use MCE::Loop::mce_loop_f to process lines in parallel
 MCE::Loop::init(
    max_workers => 8,
    chunk_size => 1,
    user_error => sub {
        my ($mce, $chunk_id, $error) = @_;
        ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
    );


# Use MCE::Loop::mce_loop to process lines in parallel
 MCE::Loop::init(
    max_workers => 8,
    chunk_size => 1,
    user_error => sub {
	my ($mce, $chunk_id, $error) = @_;
    ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
       );

# Loop until the end of the input file with the first line an assumed header.

mce_loop {
    my ($mce, $chunk_ref, $chunk_id) = @_;

    foreach my $line (@$chunk_ref) {
        chomp $line;
        next if $line eq '';  # Skip empty lines
	INFO "[$local_filename" . ":" . __LINE__ . "]\n" . "Record $_";

	($patronid)  = split(/,/,$line);

	$PatronUpdateRequest{SearchID}= $patronid;

	INFO "[$local_filename" . ":" . __LINE__ . "]PatronUpdateRequest " . Dumper(\%PatronUpdateRequest) ;

	my ($result1,$trace1)=$call1->(%PatronUpdateRequest);

	ERROR "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result1);
	ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace1);

	if ($trace1->errors) {
	    $trace1->printErrors;
	}
    }
	
} <>;


# Use MCE::Loop::mce_loop_f to process lines in parallel
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


