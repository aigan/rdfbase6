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

our @got_warning;

BEGIN
{
    $SIG{__WARN__} = sub{ push @got_warning, shift() };

    open(SAVEOUT, ">&STDOUT");
#    open(SAVEERR, ">&STDERR");

    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use FindBin;
    open PF_LOC, "<$FindBin::Bin/../.paraframe_location" or die $!;
    $CFG->{'paraframe'} = <PF_LOC>;
    chomp( $CFG->{'paraframe'} );
    push @INC, $CFG->{'paraframe'}.'/lib';
    $CFG->{'rb_root'} = abs_path("$FindBin::Bin/../");
    push @INC, $CFG->{'rb_root'}."/lib";

    use_ok('RDF::Base');
    use_ok('Para::Frame::DBIx');
    use_ok('Para::Frame::Utils', 'datadump' );

    open STDOUT, ">&", SAVEOUT      or die "Can't restore STDOUT: $!";
}

sub capture_out
{
    $::OUT = "";
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
[ qr/^Registring ext tt to burner html$/,
  qr/^Registring ext html_tt to burner html$/,
  qr/^Registring ext xtt to burner html$/,
  qr/^Registring ext css_tt to burner plain$/,
  qr/^Registring ext js_tt to burner plain$/,
  qr/^Registring ext css_dtt to burner plain$/,
  qr/^Registring ext js_dtt to burner plain$/,
  ],
    "Configuring";

Para::Frame::Utils::create_dir($troot);

warning_like {
    Para::Frame::Site->add({
			    'code'       => 'rbtest',
			    'name'       => 'RB Test',
			   })
  } qr/^Registring site /, "Adding site";


#my $cfg = $Para::Frame::CFG;
my $burner = Para::Frame::Burner->get_by_type('html');



my $dbconnect = RDF::Base::Setup->dbconnect;

warnings_like
{
    $RDF::dbix = Para::Frame::DBIx ->
      new({
	   connect => $dbconnect,
	   import_tt_params => 0,
	  });
}[
#  qr/^DBIx uses package Para::Frame::DBIx::Pg$/,
  qr/^REGISTER MODULE Para::Frame::DBIx::Pg$/,
#  qr/^Reblessing dbix into Para::Frame::DBIx::Pg$/,
 ], "DBIx config";


warnings_like
{
    Para::Frame->startup;
}[
  qr/^Connected to port 9999$/,
  qr/^Setup complete, accepting connections$/,
 ], "startup";


ok( $::OUT =~ /STARTED/, "startup output" );
clear_out();


$RDF::dbix->connect;


# Ignoring lots of warning
{
    local $SIG{__WARN__} = sub {};
    RDF::Base::Setup->setup_db();
};


# Start by a sample test of the resulting DB
my $C = RDF::Base->Constants;
is($C->get('has_access_right')->is->label,'predicate', 'DB Setup ok');

$RDF::dbix->commit;

clear_out();
1;
