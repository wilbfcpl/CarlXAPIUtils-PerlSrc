
use strict;
use warnings FATAL => 'all';
use diagnostics;

# See CPAN, web pages XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
use XML::Compile::WSDL11;      # use WSDL version 1.1
use XML::Compile::SOAP11;      # use SOAP version 1.1
use XML::Compile::Transport::SOAPHTTP;
use Data::Dumper;
use Getopt::Std;
use integer;
use Crypt::PBKDF2;

use MCE::Loop;  # Import the MCE::Loop module
use Data::Dumper;
use feature 'say';
use Log::Log4perl qw(:easy);

#TRACE,DEBUG,INFO,WARN,ERROR,FATAL
Log::Log4perl->easy_init($TRACE);

# Reduce number of magic values where possible
use constant PASSWORD_FILENAME => 'apiPass.txt';


my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;


my ($hash, $password);

open(my $fh, '<', PASSWORD_FILENAME) or die "[$local_filename" . ":" . __LINE__ . "]" . Cannot open file: PASSWORD_FILENAME $!\n";


my $line = <$fh> ;
chomp;
($hash,$password)   = split(/,/,$line) ;

close($fh);

INFO "[$local_filename" . ":" . __LINE__ . "]hash $hash password $password";

my $pbkdf2 = Crypt::PBKDF2->new;

if ($pbkdf2->validate($hash, $password)) {
    print "valid password\n";
   INFO "[$local_filename" . ":" . __LINE__ . "]Valid Password. hash $hash password $password";
}
