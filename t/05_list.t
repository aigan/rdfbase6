#!perl
# -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;

use Test::Warn;
use Test::More tests => 6;


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



# Capture STDOUT
$|=1;
my $stdout = "";
open my $oldout, ">&STDOUT"         or die "Can't save STDOUT: $!";
close STDOUT;
open STDOUT, ">:scalar", \$stdout   or die "Can't dup STDOUT to scalar: $!";


sub clear_stdout
{
    close STDOUT;
    $stdout="";
    open STDOUT, ">:scalar", \$stdout   or die "Can't dup STDOUT to scalar: $!";
}

use Para::Frame::DBIx;
use Para::Frame::Utils qw( debug );

use Rit::Base;
use Rit::Base::Utils qw( is_undef parse_propargs );
use Rit::Base::User::Meta;

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


Para::Frame->add_hook('on_startup', sub
		      {
			  $Rit::dbix->connect;
		      });

warnings_like
{
    Rit::Base->init();
}[
  qr/^Adding hooks for Rit::Base$/,
  qr/^Regestring ext js to burner plain$/,
  qr/^Done adding hooks for Rit::Base$/,
 ], "RB Init";

warnings_like
{
    Para::Frame->startup;
}[
  qr/^Connected to port 9999$/,
  qr/^Initiating valtypes$/,
  qr/^Initiating constants$/,
  qr/^Initiating key nodes$/,
  qr/^$/,
  qr/^1 Done in /,
  qr/^Setup complete, accepting connections$/,
 ], "startup";

is( $stdout, "MAINLOOP 1\nSTARTED\n", "startup output" );
clear_stdout();


###########



# [% propositions = find({ is => C.proposition }).sorted('has_predicted_resolution_date') %]

my $req = Para::Frame::Request->new_bgrequest();

my( $args, $arclim, $res ) = parse_propargs('auto');
$req->user->set_default_propargs({
				  %$args,
				  activate_new_arcs => 1,
				 });




my $R = Rit::Base->Resource;
my $L = Rit::Base->Literal;
my $C = Rit::Base->Constants;

my $Class = $C->get('class');
my $Pred = $C->get('predicate');
my $Date = $C->get('date');

my $d1 = Rit::Base::Literal::Time->parse('2010-03-01');
my $d2 = Rit::Base::Literal::Time->parse('2010-02-01');

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

diag($l1);

1;
