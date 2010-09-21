#!perl
#  $Id$  -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;

use Test::Warn;
use Test::More tests => 20;


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

use Para::Frame::DBIx;
use Rit::Base;

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

###########


my $d1 = Rit::Base::Literal::Time->parse('2010-02-01');
my $d2 = Rit::Base::Literal::Time->parse('2010-03-01');

my $l1 = Rit::Base::List->new($d1,$d2);

diag($d1);
