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


