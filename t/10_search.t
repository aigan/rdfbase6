#!perl
# -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

$|=1;
our $CFG;
our @got_warning;

use Test::Warn;
use Test::More tests => 5;


BEGIN
{
    $SIG{__WARN__} = sub{ push @got_warning, shift() };

    open(SAVEOUT, ">&STDOUT");
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
    use_ok('RDF::Base::Utils', qw( is_undef parse_propargs query_desig ) );
    use_ok('RDF::Base::User::Meta');

#    open STDOUT, ">&", SAVEOUT      or die "Can't restore STDOUT: $!";
}


###########################


my $troot = '/tmp/rbtest';
my $cfg_in =
{
 'paraframe'       => $CFG->{'paraframe'},
 'rb_root'         => $CFG->{'rb_root'},
 approot           => $troot.'/approot',
 appbase           => 'Para::MyTest',
 dir_var           => $troot.'/var',
 'port'            => 9999,
 'debug'           => 0,
 'user_class'      => 'RDF::Base::User::Meta',
};

Para::Frame->configure($cfg_in);
Para::Frame::Site->add({
                        'code'       => 'rbtest',
                        'name'       => 'RB Test',
                       });

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

RDF::Base->init();
Para::Frame->startup;

###########


# [% propositions = find({ is => C.proposition }).sorted('has_predicted_resolution_date') %]

my $req = Para::Frame::Request->new_bgrequest();

my( $args, $arclim, $res ) = parse_propargs('auto');

my $R = RDF::Base->Resource;
my $Ls = 'RDF::Base::Literal::String';
my $C = RDF::Base->Constants;

my $Class = $C->get('class');
my $Pred = $C->get('predicate');
my $Date = $C->get('date');


###### $R->get()
#
#
#{
#}



#diag( $l2->get_first_nos->sysdesig );
#diag($lit1->this_valtype->sysdesig);
#diag($n6->this_valtype->sysdesig);
#diag( $n4->sysdesig );
#diag(datadump($o2,2));
#diag( $R->get($a1)->{ioid} );
#diag($a1->sysdesig);
#diag(datadump($a1,1));

$req->done;
END
{
    Para::Frame->kill_children;
}

1;
