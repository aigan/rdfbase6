#!perl
# -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;
$|=1;

use Test::Warn;
use Test::More tests => 11;


BEGIN
{
    open(SAVEOUT, ">&STDOUT");
    open(SAVEERR, ">&STDERR");

    open STDOUT, ">/dev/null"       or die "Can't dup STDOUT: $!";

    use FindBin;
    open PF_LOC, "<$FindBin::Bin/../.paraframe_location" or die $!;
    $CFG->{'paraframe'} = <PF_LOC>;
    chomp( $CFG->{'paraframe'} );
    push @INC, $CFG->{'paraframe'}.'/lib';
    $CFG->{'rb_root'} = abs_path("$FindBin::Bin/../");
    push @INC, $CFG->{'rb_root'}."/lib";


    use_ok('Para::Frame::DBIx');
    use_ok('Para::Frame::Utils', 'datadump' );

    use_ok('Rit::Base');
    use_ok('Rit::Base::Utils', qw( is_undef parse_propargs ) );
    use_ok('Rit::Base::User::Meta');

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

###########################
open STDERR, ">/dev/null"       or die "Can't dup STDERR: $!";



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
 'user_class'      => 'Rit::Base::User::Meta',
};

Para::Frame->configure($cfg_in);
Para::Frame::Site->add({
                        'code'       => 'rbtest',
                        'name'       => 'RB Test',
                       });

my $cfg = $Para::Frame::CFG;

my $dbconnect = Rit::Base::Setup->dbconnect;

$Rit::dbix = Para::Frame::DBIx ->
  new({
       connect => $dbconnect,
       import_tt_params => 0,
      });

Para::Frame->add_hook('on_startup', sub
		      {
			  $Rit::dbix->connect;
		      });

Rit::Base->init();
Para::Frame->startup;
ok( $::OUT =~ /STARTED/, "startup output" );
clear_out();

###########


# [% propositions = find({ is => C.proposition }).sorted('has_predicted_resolution_date') %]

my $req = Para::Frame::Request->new_bgrequest();

my( $args, $arclim, $res ) = parse_propargs('auto');

my $R = Rit::Base->Resource;
my $L = Rit::Base->Literal;
my $C = Rit::Base->Constants;

my $Class = $C->get('class');
my $Pred = $C->get('predicate');
my $Date = $C->get('date');


###### $R->get()
#
#
my $a1 = $Pred->first_arc('is',undef,'adirect');
my $a1ioid = $a1->{ioid};
is( $R->get($a1)->{ioid}, $a1->{ioid}, "get by resource" );

## get by new
#
my $Email = $C->get('email');
my $n1 = $R->get('new');
$n1->add({ is => $Email }, $args);
my $a2 = $n1->first_arc('is',undef,$args); #auto includes new
ok( $a2->inactive, "Arc is new" );
is( ref($n1), 'Rit::Base::Resource', "New node just Resource" );

$res->autocommit();
ok( $a2->active, "Arc is active" );
is( ref($n1), 'Rit::Base::Metaclass::Rit::Base::Email', "New node now an Email" );


## get by new with class
#






#diag(datadump($n1,2));

#diag( $R->get($a1)->{ioid} );

#diag($a1->sysdesig);

#diag(datadump($a1,1));

$req->done;

open STDERR, ">&", SAVEERR      or die "Can't restore STDERR: $!";
1;
