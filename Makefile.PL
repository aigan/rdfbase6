# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

BEGIN { require 5.008 }
use ExtUtils::MakeMaker;

use FindBin;

my $pf;
if( open PF_LOC, "<$FindBin::Bin/.paraframe_location" )
{
    $pf = <PF_LOC>;
    chomp $pf;
}

$pf ||= "/usr/local/paraframe";

print "Where is Para::Frame installed?\n";
print "[$pf] ";
my $pf_in = <STDIN>;
$pf_in =~ s/\/?\s*\n*$//;
$pf_in =~ s/^\s+//;
$pf_in ||= $pf;

push @INC, $pf_in.'/lib';

if( $pf ne $pf_in )
{
    open OUT, ">.paraframe_location" or die $!;
    print OUT $pf_in."\n";
    close OUT;
}

WriteMakefile(
	      'NAME'	       => 'Rit::Base',
	      'PMLIBDIRS'      => [],
	      'SKIP'           => ['all','install'],
 	      'VERSION_FROM'   => 'lib/Rit/Base.pm', # finds $VERSION
	      'ABSTRACT_FROM'  => 'lib/Rit/Base.pm',
	      'AUTHOR'         => 'Jonas Liljegren <jonas@paranormal.se>',
 	      'PREREQ_PM'      =>
	      {
		  'Para::Frame'                => 1.04,
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
