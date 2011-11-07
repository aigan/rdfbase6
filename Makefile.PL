# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

BEGIN { require 5.010 }

use strict;
use warnings;


use ExtUtils::MakeMaker;
use FindBin;

##########

umask 07; # Secret files

my $pf;
if( open PF_LOC, "<$FindBin::Bin/.paraframe_location" )
{
    $pf = <PF_LOC>;
    chomp $pf;
}

my $pf_empty = $pf ? 0 : 1;
$pf ||= "/usr/local/paraframe";

print "Where is Para::Frame installed?\n";
print "[$pf] ";
my $pf_in = <STDIN>;
$pf_in =~ s/\/?\s*\n*$//;
$pf_in =~ s/^\s+//;
$pf_in ||= $pf;

push @INC, $pf_in.'/lib';

if( $pf_empty or $pf ne $pf_in )
{
    open OUT, ">.paraframe_location" or die $!;
    print OUT $pf_in."\n";
    close OUT;
}

##########

print "\nRB database connection\n";
print "See doc/INSTALL for details\n";

my( $db_connect, $db_host, $db_name, $db_port, $db_user, $db_pass );
if( open RB_DB, "<$FindBin::Bin/.rb_dbconnect" )
{
    $db_connect = join "", <RB_DB>;

    $db_connect =~ /host=(.*)\nport=(.*)\nname=(.*)\nuser=(.*)\npass=(.*)\n/;

    $db_host = $1;
    $db_port = $2;
    $db_name = $3;
    $db_user = $4;
    $db_pass = $5;

}

my $db_connect_empty = $db_connect ? 0 : 1;

$db_host ||= 'localhost';
print "DB host?\n";
print "[$db_host] ";
my $db_host_in = <STDIN>;
$db_host_in =~ s/\/?\s*\n*$//;
$db_host_in =~ s/^\s+//;
$db_host_in ||= $db_host;

$db_port ||= 5432;
print "DB port?\n";
print "[$db_port] ";
my $db_port_in = <STDIN>;
$db_port_in =~ s/\/?\s*\n*$//;
$db_port_in =~ s/^\s+//;
$db_port_in ||= $db_port;

$db_name ||= 'rb-test';
print "DB name for the test and demo?\n";
print "[$db_name] ";
my $db_name_in = <STDIN>;
$db_name_in =~ s/\/?\s*\n*$//;
$db_name_in =~ s/^\s+//;
$db_name_in ||= $db_name;

$db_user ||= 'rb';
print "DB user?\n";
print "[$db_user] ";
my $db_user_in = <STDIN>;
$db_user_in =~ s/\/?\s*\n*$//;
$db_user_in =~ s/^\s+//;
$db_user_in ||= $db_user;

$db_pass ||= '';
print "DB password for user $db_user_in? (user - for no password)\n";
my $db_pass_in = '';
while(not $db_pass_in )
{
    my $db_pass_show = '*'x length($db_pass);
    print "[$db_pass_show] ";
    $db_pass_in = <STDIN>;
    $db_pass_in =~ s/\/?\s*\n*$//;
    $db_pass_in =~ s/^\s+//;
    $db_pass_in ||= $db_pass;
}

my $db_connect_in = sprintf "host=%s\nport=%d\nname=%s\nuser=%s\npass=%s\n",
  $db_host_in, $db_port_in, $db_name_in, $db_user_in, $db_pass_in;


if( $db_connect_empty or $db_connect ne $db_connect_in )
{
    open OUT, ">.rb_dbconnect" or die $!;
    print OUT $db_connect_in;
    close OUT;
}

print "\n";

##########

WriteMakefile(
	      'NAME'	       => 'RDF::Base',
	      'PMLIBDIRS'      => [],
	      'SKIP'           => ['all','install'],
 	      'VERSION_FROM'   => 'lib/RDF/Base.pm', # finds $VERSION
	      'ABSTRACT_FROM'  => 'lib/RDF/Base.pm',
	      'AUTHOR'         => 'Jonas Liljegren <jonas@paranormal.se>',
 	      'PREREQ_PM'      =>
	      {
		  'Para::Frame'                => 1.21,
	          'Template::PopupTreeSelect'  => 0.90,
	          'Clone'                      => 0.18,
	          'DBD::Pg'                    => 1.49,
	          'List::Util'                 => 1.18,
	          'JSON'                       => 2.04,
	          'GraphViz'                   => 2.02,
	          'DateTime::Incomplete'       => 0.02,
	          'Email::Classifier'          => 0.01,
		  'Text::WordDiff'             => 0.04,
		  'File::MMagic::XS'           => 0.09,
	          'Email::MIME'                => 1.902,
                  'HTML::FormatText'           => 2.04,
	          'IMAP::BodyStructure'        => 1.01,
	          'Mail::IMAPClient'           => 3.25,
	          'URI::imap'                  => 1.01,
	      },
	      'dist'          =>
	      {
		  'COMPRESS' => 'gzip',
		  'SUFFIX'   => 'gz',
	      }
);

package MY; # so that "SUPER" works right
sub test
{
    my $inherited = shift->SUPER::test(@_);
    $inherited =~ s/test_dynamic :: pure_all/test_dynamic ::/;
    return $inherited;
}

sub test_via_harness
{
    my($self, $perl, $tests) = @_;

    return qq{\t$perl "-MExtUtils::Command::MM" }.
           qq{"-e" "test_harness(\$(TEST_VERBOSE), 'lib')" $tests\n};
}


1;
