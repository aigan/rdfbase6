package RDF::Base::Action::node_multi;

use 5.010;
use strict;
use warnings;

use Para::Frame;
use Para::Frame::Utils qw( throw debug );

#use RDF::Base::Constants qw( );
use RDF::Base::Utils qw( parse_propargs );
use RDF::Base::Literal::Time qw( now );

sub handler
{
    my( $req ) = @_;

    $req->require_root_access;

    my $q = $req->q;
    my $R = RDF::Base->Resource;
    my $m = $req->user;
    if( my $mid = $q->param('mid') )
    {
        $m = $R->get($mid);
    }

    my( $args, $arclim, $res ) = parse_propargs('solid');
    $args->{activate_new_arcs} = 1;
    $args->{created} = now();

    my( @items ) = $q->param('do_item');

    my( $do ) = $q->param('do');

    foreach my $id ( @items )
    {
        $req->may_yield;

        my $node = $R->get($id);

        $req->note("Doing ".$node->sysdesig);

        given ( $do )
        {
            when('mark_unseen'){
                $node->add({unseen_by => $m}, $args);
            }
            when('mark_seen'){
                $node->update_seen_by($m, $args);
            }
            when('mark_dirty'){
                $node->update({is_dirty=>1}, $args);
            }
            when('mark_clean'){
                $node->update({is_dirty=>0}, $args);
            }
            when('mark_weight'){
                $node->update({weight=>1}, $args);
            }
            when('mark_unweight'){
                $node->update({weight=>0}, $args);
            }
            when('mark_reconsiled'){
                $node->update({reconsiled=>$args->{created}}, $args);
            }
            when('mark_unreconsiled'){
                $node->arc_list('reconsiled')->remove($args);
            }
            when('delete'){
                $node->remove($args);
            }
        }
    }

    my $cnt = scalar(@items) || 0;

    return "Did $cnt nodes";
}

1;
