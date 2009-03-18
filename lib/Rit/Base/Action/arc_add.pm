package Rit::Base::Action::arc_add;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use 5.010;
use strict;
use warnings;
use strict;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( parse_arc_add_box parse_propargs );

=head1 DESCRIPTION

Ritbase Action for adding arcs

=cut

sub handler
{
    my( $req ) = @_;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $q = $req->q;
    my $subj_id = $q->param('id');

    my $query = $q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );

    if( $subj_id )
    {
	my $subj = Rit::Base::Arc->get( $subj_id ); # Arc or node
	$args->{'subj_new'} = $subj;
	my $props = parse_arc_add_box( $query, $args );

	$subj->add( $props, $args );
	$subj->session_history_add('updated');
	$res->autocommit;
	return "Updated node $subj_id" if $res->changes;
	return "No changes to node $subj_id";
    }
    else
    {
	my $props = parse_arc_add_box( $query, $args );
	my $subj = Rit::Base::Resource->create( $props, $args );
	$subj->session_history_add('updated');
	$q->param('id', $subj->id);
	$res->autocommit;

	return sprintf("Created node %d", $subj->id);
    }
}


1;
