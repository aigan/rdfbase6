#!perl
# -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;
$|=1;
our @got_warning;


use Test::Warn;
use Test::More tests => 10;


BEGIN
{
    $SIG{__WARN__} = sub{ push @got_warning, shift() };

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

    use_ok('RDF::Base');
    use_ok('RDF::Base::Utils', qw( is_undef parse_propargs ) );
    use_ok('RDF::Base::User::Meta');

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
 'user_class'      => 'RDF::Base::User::Meta',
};

warnings_like {Para::Frame->configure($cfg_in)}
[ qr/^Timezone set to /,
  qr/^Stringify now set$/,
  qr/^Registring ext tt to burner html$/,
  qr/^Registring ext html_tt to burner html$/,
  qr/^Registring ext xtt to burner html$/,
  qr/^Registring ext css_tt to burner plain$/,
  qr/^Registring ext js_tt to burner plain$/,
  qr/^Registring ext css_dtt to burner plain$/,
  qr/^Registring ext js_dtt to burner plain$/,
  ],
    "Configuring";

warning_like {
    Para::Frame::Site->add({
			    'code'       => 'rbtest',
			    'name'       => 'RB Test',
			   })
  } qr/^Registring site /, "Adding site";


my $cfg = $Para::Frame::CFG;

my $dbconnect = RDF::Base::Setup->dbconnect;

$RDF::dbix = Para::Frame::DBIx ->
  new({
       connect => $dbconnect,
       import_tt_params => 0,
      });

Para::Frame->add_hook('on_startup', sub
		      {
			  $RDF::dbix->connect;
		      });

warnings_like
{
    RDF::Base->init();
}[
  qr/^Adding hooks for RDF::Base$/,
  qr/^Registring ext js to burner plain$/,
  qr/^Done adding hooks for RDF::Base$/,
 ], "RB Init";


#open STDERR, ">/dev/null"       or die "Can't dup STDERR: $!";


Para::Frame->startup;
ok( $::OUT =~ /STARTED/, "startup output" );
clear_out();

###########



# [% propositions = find({ is => C.proposition }).sorted('has_predicted_resolution_date') %]

my $req = Para::Frame::Request->new_bgrequest();

my( $args, $arclim, $res ) = parse_propargs('auto');
$req->user->set_default_propargs({
				  %$args,
				  activate_new_arcs => 1,
				 });




my $R = RDF::Base->Resource;
my $L = RDF::Base->Literal;
my $C = RDF::Base->Constants;

my $Class = $C->get('class');
my $Pred = $C->get('predicate');
my $Date = $C->get('date');

my $d1 = RDF::Base::Literal::Time->parse('2010-03-01');
my $d2 = RDF::Base::Literal::Time->parse('2010-02-01');

my $MyThing =
  $R->find_set({
		label => 'MyThing',
		is => $Class,
	       });

$R->find_set({
	      label => 'has_some_date',
	      is => $Pred,
	      domain => $MyThing,
	      range => $Date,
	     });

my $a =
  $R->find_set({
		has_some_date => $d1,
		is => $MyThing,
		name => 'rbt-1a',
	       });

my $b =
  $R->find_set({
		is => $MyThing,
		name => 'rbt-1b',
	       });

my $c =
  $R->find_set({
		has_some_date => $d2,
		is => $MyThing,
		name => 'rbt-1c',
	       });

my $l1 = $R->find({ is => $MyThing })->sorted('has_some_date');

ok( "$l1" eq 'rbt-1c / rbt-1a / rbt-1b', "sort result" );

$req->done;

open STDERR, ">&", SAVEERR;
1;
