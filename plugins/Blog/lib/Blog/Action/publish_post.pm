package RDF::Base::Action::plugin_Blog_publish_post;

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

    my $u = $req->session->user;
    my $q = $req->q;

    my $id = $q->param('id')
      or throw('incomplete', "Post id missing");

    my $post = RDF::Base::Resource->get( $id );

    throw( 'incomplete', "Missing post id" )
      unless( $post );

    my $blog = $post->plugin_blog_post_is_in_blog;

    # Check that blog -has_member->$u
    unless( $blog->has_member( $u ) or $u->level >= 20 )
    {
	debug $u->sysdesig ." is not a member of ". $blog->sysdesig;
	throw('denied', "Access denied");
    }

    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $url = $post->publish( $args );

    $res->autocommit({ activate => 1 });

    return "Published to $url";
}

1;
