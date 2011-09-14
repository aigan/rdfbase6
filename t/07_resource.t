#!perl
# -*-cperl-*-

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );

our $CFG;
$|=1;

use Test::Warn;
use Test::More tests => 27;


BEGIN
{
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


    use_ok('Para::Frame::DBIx');
    use_ok('Para::Frame::Utils', 'datadump' );

    use_ok('Rit::Base');
    use_ok('Rit::Base::Utils', qw( is_undef parse_propargs query_desig ) );
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
#open STDERR, ">/dev/null"       or die "Can't dup STDERR: $!";

our @got_warning;
local $SIG{__WARN__} = sub{ push @got_warning, shift() };


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
my $Ls = 'Rit::Base::Literal::String';
my $C = Rit::Base->Constants;

my $Class = $C->get('class');
my $Pred = $C->get('predicate');
my $Date = $C->get('date');


###### $R->get()
#
#
{
    my $a1 = $Pred->first_arc('is',undef,'adirect');
    is( $R->get($a1)->{ioid}, $a1->{ioid}, "get by resource" );

    ## get by new
    #
    my $Email = $C->get('email');
    my $n1 = $R->get('new');
    $n1->add({ is => $Email }, $args);
    my $a2 = $n1->first_arc('is',undef,$args); #auto includes new
    ok( $a2->inactive, "Arc is new" );
    is( ref($n1), 'Rit::Base::Resource', "new node just Resource" );

    $res->autocommit();
    ok( $a2->active, "arc is active" );
    is( ref($n1), 'Rit::Base::Metaclass::Rit::Base::Email', "new node now an Email" );

    ## get by new with class
    #
    my $n2 = $R->get('new', {new_class=>$Email});
    is( ref($n2), 'Rit::Base::Metaclass::Rit::Base::Email', "new node is an Email" );

    ## get by constant
    #
    my $n3 = $R->get('predicate');
    is($n3->{label}, 'predicate', "get by label");

    ## get by anything
    #
    my $n4 = $R->get('rbt-1a'); # Get by name (not label)
    is($n4->name->plain, 'rbt-1a', "get by anything");

    ## get by id
    #
    my $n5 = $R->get($n4->id);
    is( $n5->id, $n4->id, "get by id" );
}

###### $R->get_by_node_rec()

###### $R->get_by_arc_rec()

###### $R->get_by_id() Uses $R->get()

###### $R->find_by_anything()
#
#
{
    my $Email = $C->get('email');
    my $n1 = $R->get('new');
    $n1->add({ is => $Email }, $args);
    $res->autocommit();


    ## find obj as object resource
    #
    my $l1 = $R->find_by_anything($n1);
    is( $l1->get_first_nos->id, $n1->id, "find obj as object resource" );

    ## find obj as object literal
    #
    my $lit1 = $Ls->parse('hello world');
    $n1->add({description => $lit1}, $args);
    $lit1->add({is_of_language => $C->get('english')}, $args);
    $res->autocommit();
    my $a2 = $n1->first_arc('description');
    my $n6 = $a2->obj;
    is(ref($n6),'Rit::Base::Resource::Literal', "new resource literal");
    my $valtext = $C->get('valtext');
    my $literal = $C->get('literal');
    is($n6->this_valtype->id, $literal->id, "resource valtype literal");
    is($lit1->this_valtype->id, $valtext->id, "literal valtype valtext");
    my $l2 = $R->find_by_anything($n6,{valtype=>$valtext});
    my $o1 = $l2->get_first_nos;
    is(ref($o1),'Rit::Base::Literal::String', "find obj as object literal by valtype valtext");
    my $l3 = $R->find_by_anything($n6);
    my $o2 = $l3->get_first_nos;
    is(ref($o2),'Rit::Base::Resource::Literal', "find obj as literal resource without given valtype");

    ## find obj as literal
    #
    my $l4 = $R->find_by_anything($lit1);
    my $lit2 = $l4->get_first_nos;
    is($lit1, $lit2, "find obj as literal");

    ## find obj as subquery
    #
    my $l5 = $R->find_by_anything({ has_some_date => '2010-02-01' });
    my $n7 = $l5->get_first_nos;
    is($n7->name->plain, 'rbt-1c', "find obj as subquery");

    ## find obj is not an obj
    #
    my $lit3 = $R->find_by_anything('Spagetti',{valtype=>$valtext})->
      get_first_nos;
    is(ref($lit3), 'Rit::Base::Literal::String', "find non-obj");
    my $lit4 = $R->find_by_anything(\ 'Spagetti',{valtype=>$valtext})->
      get_first_nos;
    is(ref($lit4), 'Rit::Base::Literal::String', "find non-obj by scalar ref");

    ## find obj as list
    #
    my $l6 = $R->find_by_anything($l5);
    is($l5->get_first_nos, $l6->get_first_nos, "find obj as list");

    my $l7 = Rit::Base::List->new([undef,$l4]);
    my $l8 = Rit::Base::List->new([$l5,undef,$l7,$n1]);
    my $l9 = $R->find_by_anything( $l8 );
    is($l9->desig, 'rbt-1c / hello world / <deleted>', "find obj as list - flattened");
}

#diag( $l2->get_first_nos->sysdesig );

#diag($lit1->this_valtype->sysdesig);
#diag($n6->this_valtype->sysdesig);



#diag( $n4->sysdesig );

#diag(datadump($o2,2));

#diag( $R->get($a1)->{ioid} );

#diag($a1->sysdesig);

#diag(datadump($a1,1));

$req->done;

#open STDERR, ">&", SAVEERR      or die "Can't restore STDERR: $!";

1;
