package RDF::Base::Action::plugin_Blog_post;

use 5.010;
use strict;
use warnings;

use Para::Frame::L10N qw( loc );
use Para::Frame::Utils qw( throw debug );

use RDF::Base::Utils qw( parse_propargs parse_query_props parse_form_field_prop );
use RDF::Base::Constants qw( $C_plugin_blog_post );

sub handler
{
    my( $req ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $A = RDF::Base->Arc;
    my $R = RDF::Base->Resource;
    my $q = $req->q;
    my $u = $req->session->user;

    my $id = $q->param('id')
      or throw('incomplete', "Post id missing");

    my $post = RDF::Base::Resource->get( $id );
    my $blog;

    unless( $post->empty )
    {
	$blog = $post->plugin_blog_post_is_in_blog;
    }

    # Parse form fields, and check that nothing is odd...
    foreach my $param ($q->param) {
	next
	  unless( $param =~ /^(arc|prop|row|check|newsubj)/ );

	my $arg = parse_form_field_prop($param);

	my $subj_id;
	my $pred;

	if( $arg->{arc} ne '' )
	{
	    my $arc  = $A->get( $arg->{arc} );
	    my $subj = $arc->subj;
	    $subj_id = $subj->id;
	    $pred    = $arc->pred->label;
	}
	else
	{
	    $subj_id = $arg->{subj};
	    $pred    = $arg->{pred};
	}

	if ( $subj_id != $post->id )
	{
	    debug "Subj '". $subj_id ."' is not post!  Access denied.";
	    debug "  in param $param";
	    throw('denied', "Access denied");
	}

	if( not grep($pred, ('is', 'name', 'description', 'plugin_blog_post_is_in_blog')) )
	{
	    debug "Unknown predicate used: ". $arg->{pred};
	    throw('denied', "Access denied");
	}

	if( $pred eq 'plugin_blog_post_is_in_blog' ) {
	    debug "Blog ID is: ". $q->param( $param );
	    $blog = $R->get( $q->param( $param ));
	}

	if( $pred eq 'is' and $q->param( $param ) != $C_plugin_blog_post->id ) {
	    debug "Blog post is -> ". $q->param( $param );
	    throw('denied', "Access denied");
	}
    }

    throw( 'incomplete', "Missing blog id" )
      unless( $blog );

    # Check that blog -has_member->$u
    unless( $blog->has_member( $u ) or $u->has_cm_access )
    {
	debug $u->sysdesig ." is not a member of ". $blog->sysdesig;
	throw('denied', "Access denied");
    }

    # update by query
    $post->update_by_query( $args );

    $res->autocommit({ activate => 1 });

    if( $res->changes )
    {
	return loc("Changes saved");
    }
    else
    {
	return loc("No changes");
    }

}

1;
