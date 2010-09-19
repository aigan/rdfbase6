#!perl
#  $Id$  -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;

use Test::Warn;
use Test::More tests => 4;

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
 'port'            => 9999,
 'debug'           => 1,
};

#Para::Frame->configure($cfg_in); ## TEST
warnings_like {Para::Frame->configure($cfg_in)}
[ qr/^Timezone set to /,
  qr/^Stringify now set$/,
  qr/^Regestring ext tt to burner html$/,
  qr/^Regestring ext html_tt to burner html$/,
  qr/^Regestring ext xtt to burner html$/,
  qr/^Regestring ext css_tt to burner plain$/,
  qr/^Regestring ext js_tt to burner plain$/,
  qr/^Regestring ext css_dtt to burner plain$/,
  qr/^Regestring ext js_dtt to burner plain$/,
  ],
    "Configuring";

Para::Frame::Utils::create_dir($troot);

warning_like {
    Para::Frame::Site->add({
			    'code'       => 'rbtest',
			    'name'       => 'RB Test',
			   })
  } qr/^Registring site RB Test$/, "Adding site";


my $cfg = $Para::Frame::CFG;
my $burner = Para::Frame::Burner->get_by_type('html');



my $dbconnect = Rit::Base::Setup->dbconnect;

warnings_like
{
    $Rit::dbix = Para::Frame::DBIx ->
      new({
	   connect => $dbconnect,
	   import_tt_params => 0,
	  });
}[
  qr/^DBIx uses package Para::Frame::DBIx::Pg$/,
  qr/^Reblessing dbix into Para::Frame::DBIx::Pg$/,
 ], "startup";


warnings_like
{
    Para::Frame->startup;
}[
  qr/^Connected to port 9999$/,
  qr/^Setup complete, accepting connections$/,
 ], "startup";


$Rit::dbix->connect;


# Ignoring lots of warning
{
    local $SIG{__WARN__} = sub {};
    Rit::Base::Setup->setup_db();
};

#warnings_exist
#{
#    Rit::Base::Setup->setup_db();
#}[
#  qr/^NOTICE:  ALTER TABLE/,
#  qr/^Reading Nodes$/,
#  qr/^\d+ = \w+$/,
#  qr/^Reading Arcs$/,
#  qr/^Planning /,
#  qr/^Bootstrapping literals$/,
#  qr/^Literal \w+ is a scof/,
#  qr/^Adding nodes$/,
#  qr/^Extracting valtypes$/,
#  qr/^Valtype \w+ = \d+$/,
#  qr/^Adding arcs$/,
#  qr/^Initiating valtypes$/,
#  qr/^\s*Initiating constants$/,
#  qr/^Initiating key nodes$/,
#  qr/^Setting bg_user_code to \d+$/,
#  qr/^\s+$/,
#  qr/^\s+Infering arcs$/,
#  qr/^\s+Updating arcs for the new range$/,
#  qr/^\s+Pred \d+ coltype set to '\d+'$/,
#  qr/^\s+Changing coltype id from 5 to 1!!!$/,
#  qr/^\s+EXISTING ARCS MUST BE VACUUMED$/,
#  qr/^\s+Created arc id /,
#  qr/^\s+on_class_perl_module_change for \d+: /,
#  qr/^\s+TODO: rebless literals for \d+: /,
#  qr/^\s+Adding valtype \d+ -> \w+ in coltype cache$/,
#  qr/^\s+Initiating constants again$/,
#  qr/^\s+Initiating key nodes$/,
#  qr/^\s+Done!$/,
#  qr/.*/,
# ], "DB Setup";


$Rit::dbix->commit;


#my $dbh = $Rit::dbix->dbh;
#print $dbh;

#print "EOT\n";

1;
