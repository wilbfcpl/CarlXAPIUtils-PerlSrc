#!/s/sirsi/Unicorn/Bin/perl
# Author:  <wblake@CB95043>
# Created: Dec 17 2021
# Version: 0.01
# Note that the Git Project Name is PatronLoader while the Komodo Project Name is FCPSStudentData
#Usage MSDXlat.pl -l -d "2021-12-02" infile >outfile
# MSD Data expected by this utility
# $last,$first,$middle,$grade,$studentid
#School Addrss 101 Clark PL, Frederick MD 21701
#Status assumed Good
# options
# header line -l: writes a header output, skips the header input
# Registration Date -d "2021-12-02T00:00:00"
# Input Lines
#$campus, $studentid,$first,$middle,$last,$grade
# $studentid,$first,$middle,$last,$grade,$building,$school,$street,$citystate,$zip,$status)
# FCPS Student Data
# Output Lines

#ToDo Copy the output file to the CarlX Soap Project directory
use strict;
use diagnostics;
use Switch;
use Getopt::Std;
use Text::Unidecode;

use constant SOFTBLOCK => 'S';
use constant GOOD => 'G';

#MSD Specific values
use constant MSD_ID_PREFIX_FREDERICK => "119829219";
use constant MSD_ID_PREFIX_COLUMBIA =>"3";
use constant MSD_ID_LEN => 5;
use constant MSD_SCHOOL => "Maryland School for Deaf";
use constant MSD_FREDERICK_ADDRESS => "101 Clarke Place";
use constant MSD_FREDERICK_CITY => "Frederick";
use constant MSD_COLUMBIA_ADDRESS => "8169 Old Montgomery Rd";
use constant MSD_COLUMBIA_CITY =>"Ellicott City";
use constant MSD_STATE => "MD";
use constant MSD_COLUMBIA_ZIP => "21043";
use constant MSD_FREDERICK_ZIP => "21701";

#options l print header , d: date for the EditDate
our ($opt_l,$opt_d, $opt_h);
getopts("ld:h");



my $SavedOFS = $,;
$,= ",";

my $editdate = "";
my $todaydate = "";


# Use today if date option not provided

my ($day,$month,$year) = (localtime) [3,4,5];
$year+= 1900;
$month += 1;

$todaydate = "$year-$month-$day";

if (defined $opt_h){
	die ("Usage: MSDXlat.pl -l -d '2021-12-02' infile >outfile\n");
}
if (!defined $opt_d) {
    $editdate = $todaydate;
} 
else {
    $editdate = $opt_d . "T00:00:00";
}

my ($campus, $studentid,$first,$middle,$last,$grade,$building,$school,$street,$citystate,$zip,$status);
my ($studentpatronid, $state);
my ($idprefix);


    # $zip = MSD_ZIP ;
    # $citystate= MSD_CITY;
    $state = MSD_STATE;
    # $street = MSD_ADDRESS;
    $school = MSD_SCHOOL;
    $status = "G";
    # $middle = '' ;

# Print new header row if option l, ignore input header. 
if (defined $opt_l) {
      print "patronid,first,middle,last,grade,schooladdr,city,state,zip,status,regdate"," \n";
     $_ = <>;
     chomp;
      ($campus,$studentid,$first,$middle,$last,$grade) = split (/,/);
      
    }


    while (<>) {
	chomp;
	($campus,$studentid,$first,$middle,$last,$grade) = split (/,/);

      # Expect ID to have at least 5 digits.
      # MSD Student IDs have varying length so add 0 where they have four digits
      # Truncate longer IDs to 5 digits.
      
      $studentid =~ s/\s+// ;

       switch(uc($campus))
	{
	  case "COLUMBIA"
	    {
      	       $idprefix=MSD_ID_PREFIX_COLUMBIA;
	       $zip = MSD_COLUMBIA_ZIP ;
	       $citystate= MSD_COLUMBIA_CITY;
	       $street = MSD_COLUMBIA_ADDRESS;
	       }
	   case "FREDERICK"
	   {
	       $idprefix=MSD_ID_PREFIX_FREDERICK;
	       $zip = MSD_FREDERICK_ZIP ;
	       $citystate= MSD_FREDERICK_CITY;
	       $street = MSD_FREDERICK_ADDRESS;
	     
	    }
	}

      my $padlen=MSD_ID_LEN-length($studentid);
      
      if ($padlen==0)
	{
	  $studentpatronid = $idprefix . substr($studentid,0,5);
	}
      else
	{
	  my $padded = sprintf("%05s",substr($studentid,0,5));
	  #print "Pad len: $padlen. Padded: $padded\n";
	 $studentpatronid= $idprefix . $padded;
	}

      #print "\n" . "Campus " . $campus . " Patron ID " . $studentpatronid . " Grade " . $grade . " Name " . $first . " " . $last .  " \n" ;
      
    # Some manipulation for MSD
      #  K and PK grades, pad single digit with leading 0.


      
    switch ($grade)
      {
	case "Infants"  {$grade = "PK"}
	case "Toddlers"  {$grade = "PK"}       
	case "PreK"  {$grade = "PK"}
	case "PreSchool"  {$grade = "PK"}
	case "PK"  {$grade = "PK"}
	case  "K"  {$grade = "K"}
	case  "1"  {$grade = "01"}
	case  "2"  {$grade = "02"}
	case  "3"  {$grade = "03"}
	case  "4"  {$grade = "04"}
	case  "5"  {$grade = "05"}
	case  "6"  {$grade = "06"}
	case  "7"  {$grade = "07"}
	case  "8"  {$grade = "08"}
	case  "9"  {$grade = "09"}
	
      }
      

      foreach my $thename ($first,$last)
      {
	$thename = unidecode($thename);
      }

      print $studentpatronid, $first, $middle, ,$last,$grade, $school . " " . $street, $citystate , $state , $zip, $status , $editdate . "," . "\n";
    }
$,= $SavedOFS;
