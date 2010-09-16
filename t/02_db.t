#!perl
#  $Id$  -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;

#use Test::Warn;
#use Test::More tests => 20;

BEGIN
{
    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use FindBin;
    open PF_LOC, "<$FindBin::Bin/../.paraframe_location" or die $!;
    $CFG->{'paraframe'} = <PF_LOC>;
    chomp( $CFG->{'paraframe'} );
    push @INC, $CFG->{'paraframe'}.'/lib';
    $CFG->{'rb_root'} = abs_path("$FindBin::Bin/../");
    push @INC, $CFG->{'rb_root'}."/lib";

#    use_ok('Rit::Base');

    open STDOUT, ">&", $oldout      or die "Can't dup \$oldout: $!";
}

use Para::Frame::DBIx;
use Rit::Base; ## TEST


#warning_like {Para::Frame::Site->add({})} qr/^Registring site [\w\.]+$/, "Adding site";

my $troot = '/tmp/rbtest';
my $cfg_in =
{
 'paraframe'       => $CFG->{'paraframe'},
 'rb_root'         => $CFG->{'rb_root'},
 approot           => $troot.'/approot',
 appbase           => 'Para::MyTest',
 dir_var           => $troot.'/var',
 'debug'           => 1,
};

Para::Frame->configure($cfg_in); ## TEST
#warnings_like {Para::Frame->configure($cfg_in)}
#[ qr/^Timezone set to /,
#  qr/^Stringify now set$/,
#  qr/^Regestring ext tt to burner html$/,
#  qr/^Regestring ext html_tt to burner html$/,
#  qr/^Regestring ext css_tt to burner plain$/,
#  qr/^Regestring ext js_tt to burner plain$/,
#  qr/^Regestring ext css_dtt to burner plain$/,
#  qr/^Regestring ext js_dtt to burner plain$/,
#  ],
#    "Configuring";

Para::Frame::Utils::create_dir($troot);

Para::Frame::Site->add({
			'code'       => 'rbtest',
			'name'       => 'RB Test',
		       });


my $cfg = $Para::Frame::CFG;
my $burner = Para::Frame::Burner->get_by_type('html');


# Configure database
#

my $dbconnect = Rit::Base::Setup->dbconnect;

$Rit::dbix = Para::Frame::DBIx ->
  new({
       connect => $dbconnect,
       import_tt_params => 1,
      });

Para::Frame->startup;

$Rit::dbix->connect;

Rit::Base::Setup->setup_db();
$Rit::dbix->commit;


my $dbh = $Rit::dbix->dbh;
print $dbh;

print "EOT\n";
