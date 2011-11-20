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
use Test::More tests => 42;


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
    is( ref($n1), 'RDF::Base::Resource', "new node just Resource" );

    $res->autocommit();
    ok( $a2->active, "arc is active" );
    is( ref($n1), 'RDF::Base::Metaclass::RDF::Base::Email', "new node now an Email" );

    ## get by new with class
    #
    my $n2 = $R->get('new', {new_class=>$Email});
    is( ref($n2), 'RDF::Base::Metaclass::RDF::Base::Email', "new node is an Email" );

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
    is( $l1->get_first_nos->id, $n1->id, "find obj by object resource" );

    ## find obj as object literal
    #
    my $lit1 = $Ls->parse('hello world');
    $n1->add({description => $lit1}, $args);
    $lit1->add({is_of_language => $C->get('english')}, $args);
    $res->autocommit();
    my $a2 = $n1->first_arc('description');
    my $n6 = $a2->obj;
    is(ref($n6),'RDF::Base::Resource::Literal', "new resource literal");
    my $valtext = $C->get('valtext');
    my $literal = $C->get('literal');
    is($n6->this_valtype->id, $literal->id, "resource valtype literal");
    is($lit1->this_valtype->id, $valtext->id, "literal valtype valtext");
    my $l2 = $R->find_by_anything($n6,{valtype=>$valtext});
    my $o1 = $l2->get_first_nos;
    is(ref($o1),'RDF::Base::Literal::String', "find obj by object literal with valtype valtext");
    my $l3 = $R->find_by_anything($n6);
    my $o2 = $l3->get_first_nos;
    is(ref($o2),'RDF::Base::Resource::Literal', "find obj by literal resource without given valtype");

    ## find obj as literal
    #
    my $l4 = $R->find_by_anything($lit1);
    my $lit2 = $l4->get_first_nos;
    is($lit1, $lit2, "find obj as literal");

    ## find obj as subquery
    #
    my $l5 = $R->find_by_anything({ has_some_date => '2010-02-01' });
    my $n7 = $l5->get_first_nos;
    is($n7->name->plain, 'rbt-1c', "find obj by subquery");

    ## find obj is not an obj
    #
    my $lit3 = $R->find_by_anything('Spagetti',{valtype=>$valtext})->
      get_first_nos;
    is(ref($lit3), 'RDF::Base::Literal::String', "find non-obj");
    my $lit4 = $R->find_by_anything(\ 'Spagetti',{valtype=>$valtext})->
      get_first_nos;
    is(ref($lit4), 'RDF::Base::Literal::String', "find non-obj by scalar ref");

    ## find obj as list
    #
    my $l6 = $R->find_by_anything($l5);
    is($l5->get_first_nos, $l6->get_first_nos, "find obj as list");

    my $l7 = RDF::Base::List->new([undef,$l4]);
    my $l8 = RDF::Base::List->new([$l5,undef,$l7,$n1]);
    my $l9 = $R->find_by_anything( $l8 );
    is($l9->desig, 'rbt-1c / hello world / <deleted>', "find obj by list - flattened");

    my $l10 = $R->find_by_anything([$l5,undef,$n1,[undef,$l4]]);
    is($l10->desig, 'rbt-1c / <deleted> / hello world', "find obj by list - array flattened");

    ## find obj as name with criterions
    #
    my $l11 = $R->find_by_anything('2010-02-01 (has_some_date)');
    is( $l11->get_first_nos->name->plain, 'rbt-1c', "find obj having value with given pred" );
#    diag( $l11->get_first_nos->sysdesig );

    my $n8 = $R->find_set({name_short => 'rbt-2a',
                           member_of => 'rbt-1a' }, $args);
    my $n9 = $R->find_set({name_short => 'rbt-2a',
                           member_of => 'rbt-1b' }, $args);
    $res->autocommit();
    my $l12 = $R->find_by_anything('rbt-2a (member_of rbt-1b)');
    is( $l12->size, 1, "find obj having desig and with given prop" );

    # This form not supported...
    # my $l13 = $R->find_by_anything('rbt-2a (member_of rbt-1b, member_of rbt-1a)');

    # Croaking...
    #my $l14 = $R->find_by_anything('rbt-2a (member_of rbt-1c)');
    #is( $l14->defined, 0, "find obj having desig and with given prop -- undef" );

    ## find obj as obj id and name
    #
    my $l15 = $R->find_by_anything($n9->id.': '.$n9->desig);
    is( $l15->desig, 'rbt-2a', "find obj by id and desig" );


    ## find obj as obj id with prefix '#'
    #
    my $l16 = $R->find_by_anything('#'.$n9->id);
    is( $l16->desig, 'rbt-2a', "find obj by hash id" );

    ## find no value
    #
    my $l17 = $R->find_by_anything('');
    is( $l17->size, 0, "find no value" );

    ## find obj as label of obj
    #
    my $l18 = $R->find_by_anything('MyThing');
    is( $l18->desig, $C->get('MyThing')->desig, "find obj by label" );

    ## find obj as name of obj
    #
    my $l19 = $R->find_by_anything('rbt1a'); # cleaned
    is( $l19->desig, 'rbt-1a', "find obj by name" );

    my $l20 = $R->find_by_anything('rbt1a',
                                   {valtype=>$C->get('MyThing')});
    is( $l20->desig, 'rbt-1a', "find obj by name with valtype" );

    my $l21 = $R->find_by_anything($n9->id);
    is( $l21->desig, 'rbt-2a', "find obj by id" );
}

###### $R->get_id()
#
#
{
    my $i1 = $R->get_id('MyThing');
    is( $i1, $C->get('MyThing')->id, "get id by label" );
}


###### $R->find()
#
#
{
    my $l1 = $R->find('rbt-1a');
    is($l1->desig, 'rbt-1a', "find by implicit name");

    my $l2 = $R->find({name_short => 'rbt-2a'});
    is($l2->size, 2, "find by query - 2 results");

    my $l3 = $R->find({name_short => 'rbt-2a'},
                      {
                       default => {member_of => 'rbt-1a'},
                      }
                     );
    is( $l3->size, 1, "find by query with default" );
    my $n1 = $l3->get_first_nos;

    my $l4 = $l2->find({member_of => 'rbt-1a'});
    is( $l4->get_first_nos->id, $n1->id, "find by query from list" );

    my $l5 = $n1->find({member_of => 'rbt-1a'});
    is( $l5->get_first_nos->id, $n1->id, "find by query from resource" );

#    my $l6 = $R->find({is => 'MyThing'});
}

###### $R->find_simple()

###### $R->find_one()

###### $R->find_set()

###### $R->set_one()

###### $R->create()

###### $R->Form_url()

###### $R->empty()

###### $n->list()

###### $n->list_preds()

###### $n->revlist()

###### $n->revlist_preds()

###### $n->first_prop()

###### $n->first_revprop()

###### $n->has_value()

###### $n->count()

###### $n->revcount()

###### $n->set_label()

###### $n->desig

###### $n->safedesig()

###### $n->sysdesig()

###### $n->arc_list()

###### $n->revarc_list()

###### $n->first_arc()

###### $n->first_revarc()

###### $n->arc()

###### $n->revarc()

###### $n->add()

###### $n->update()

###### $n->equals()

###### $n->vacuum()

###### $n->merge_node()

###### $n->link_paths()

###### $n->wd()

###### $n->wn()

###### $n->display()

###### $n->wdirc()

###### $n->wu()

###### $n->wuh()

###### $n->register_ajax_pagepart()

###### $n->wuirc()

###### $n->arcversions()

###### $n->tree_select_widget()

###### $n->tree_select_data()

###### $n->find_class()

###### $n->first_bless()

###### $n->on_class_perl_module_change()

###### $n->rebless()

###### $n->get_by_anything()

###### $n->get_by_label()

###### $n->reset_cache

###### $n->initiate_cache()

###### $n->initiate_node()

###### $n->create_rec()

###### $n->mark_updated()

###### $n->commit()

###### $n->rollback()

###### $n->save()

###### $n->initiate_rel()

###### $n->initiate_rev()

###### $n->initiate_prop()

###### $n->initiate_revprop()

###### $n->populate_rel()

###### $n->populate_rev()

###### $n->session_history_add()

###### $n->this_valtype()

###### $n->instance_class()

###### $n->update_seen_by()

###### $n->update_valtype()

###### $n->update_unseen_by()

###### $n->update_by_query_arc()

###### $n->handle_query_newsubjs()




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
