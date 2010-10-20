#!perl
# -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;
$|=1;

use Test::Warn;
use Test::More tests => 9;

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

    open STDOUT, ">&", $oldout      or die "Can't dup \$oldout: $!";
}

use_ok('Rit::Base');
use_ok('Para::Frame::DBIx');
use Para::Frame::Utils qw( datadump );

sub capture_out
{
    $::OUT = "";
    open my $oldout, ">&STDOUT"         or die "Can't save STDOUT: $!";
    close STDOUT;
    open STDOUT, ">:scalar", \$::OUT   or die "Can't dup STDOUT to scalar: $!";
}

sub clear_out
{
    close STDOUT;
    $::OUT = "";
    open STDOUT, ">:scalar", \$::OUT   or die "Can't dup STDOUT to scalar: $!";
}

capture_out();


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


#my $cfg = $Para::Frame::CFG;
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
 ], "DBIx config";


warnings_like
{
    Para::Frame->startup;
}[
  qr/^Connected to port 9999$/,
  qr/^Setup complete, accepting connections$/,
 ], "startup";


is( $::OUT, "STARTED\n", "startup output" );
clear_out();


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


# Start by a sample test of the resulting DB
my $C = Rit::Base->Constants;
is($C->get('has_access_right')->is->label,'predicate', 'DB Setup ok');

$Rit::dbix->commit;

is( $::OUT, "", "end output" );
clear_out();
1;
