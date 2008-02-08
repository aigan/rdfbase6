#!perl
#  $Id$  -*-cperl-*-

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
  qr/^Regestring ext css to burner plain$/,
  ],
    "Configuring";

my $cfg = $Para::Frame::CFG;

is( $cfg->{'approot'}, '/tmp/approot', 'approot');
is_deeply( $cfg->{'appfmly'}, [], 'appfmly');
is( $cfg->{'dir_log'}, '/var/log', 'dir_log');
is( $cfg->{'logfile'}, '/var/log/paraframe_7788.log', 'logfile');

my $burner = Para::Frame::Burner->get_by_type('html');
isa_ok( $burner, 'Para::Frame::Burner', 'burner html' );

is_deeply( $cfg->{'appback'}, [], 'appback');
is( $cfg->{'dir_var'}, '/var', 'dir_var');
is( $cfg->{'port'}, 7788, 'port');
is( $cfg->{'paraframe'}, '/usr/local/paraframe', 'paraframe');
isa_ok($cfg->{'bg_user_code'}, 'CODE', 'bg_user_code');
is( $cfg->{'ttcdir'}, '/var/ttc', 'ttcdir');
is( $cfg->{'dir_run'}, '/var/run', 'dir_run');
is( $cfg->{'pidfile'}, '/var/run/parframe_7788.pid', 'pidfile');
is( $cfg->{'paraframe_group'}, 'staff', 'paraframe_group');
is( $cfg->{'time_zone'}, 'local', 'time_zone');
is( $cfg->{'umask'}, 7, 'umask');
is( $cfg->{'user_class'}, 'Para::Frame::User', 'user_class');
