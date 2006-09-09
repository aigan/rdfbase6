#  $Id$  -*-cperl-*-
package Rit::Base::Action::arc_add;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( trim );

use Rit::Base::Utils qw( parse_arc_add_box );

sub handler
{
    my( $req ) = @_;

    my $changed = 0;
    my $DEBUG = 0;

    my $q = $req->q;
    my $subj_id = $q->param('id');

    my $query = $q->param('query');
    $query .= "\n" . join("\n", $req->q->param('query_row') );

    my $props = parse_arc_add_box( $query );

    if( $subj_id )
    {
	my $subj = Rit::Base::Arc->get( $subj_id ); # Arc or node

	warn Dumper $props if $DEBUG;

	$changed += $subj->add( $props );
	return "Updated node $subj_id" if $changed;
	return "No changes to node $subj_id";
    }
    else
    {
	my $subj = Rit::Base::Resource->create( $props );
	$q->param('id', $subj->id);

	return sprintf("Created node %d", $subj->id);
    }
}


1;
