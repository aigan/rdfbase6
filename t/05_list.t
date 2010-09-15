#!perl
#  $Id$  -*-cperl-*-

use 5.010;
use strict;
use warnings;

use Test::Warn;
use Test::More tests => 20;


BEGIN
{
    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use FindBin;
    open PF_LOC, "<$FindBin::Bin/../.paraframe_location" or die $!;
    my $pf = <PF_LOC>;
    chomp( $pf );
    push @INC, $pf.'/lib';

    use_ok('Rit::Base');

    open STDOUT, ">&", $oldout      or die "Can't dup \$oldout: $!";
}

warning_like {Para::Frame::Site->add({})} qr/^Registring site [\w\.]+$/, "Adding site";

my $cfg_in =
{
    approot => '/tmp/approot',
    appbase => 'Para::MyTest',
};
warnings_like {Para::Frame->configure($cfg_in)}
[ qr/^Timezone set to /,
  qr/^Stringify now set$/,
  qr/^Regestring ext tt to burner html$/,
  qr/^Regestring ext html_tt to burner html$/,
  qr/^Regestring ext css_tt to burner plain$/,
  qr/^Regestring ext js_tt to burner plain$/,
  qr/^Regestring ext css_dtt to burner plain$/,
  qr/^Regestring ext js_dtt to burner plain$/,
  ],
    "Configuring";

my $cfg = $Para::Frame::CFG;
my $burner = Para::Frame::Burner->get_by_type('html');

my $d1 = Rit::Base::Literal::Time->parse('2010-02-01');
my $d2 = Rit::Base::Literal::Time->parse('2010-03-01');

my $l1 = Rit::Base::List->new($d1,$d2);

diag($d1);
