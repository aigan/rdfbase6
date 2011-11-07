package RDF::Base::Plugins::Blog::Type;

use strict;

use Para::Frame::Reload;
use Para::Frame::Widget qw( jump );
use Para::Frame::Utils qw( debug datadump );

sub get_url
{
    my( $type ) = @_;

    my $page = $type->revlist('is_view_for_node')->get_first_nos;

    return $Para::Frame::REQ->site->home->get_virtual( $page->has_url )->url
      if $page;
    return;
}


sub get_feed_and_entries_info
{
    my( $type, $req ) = @_;

    my @post_entries;

    my $feed_info = {};

    my $tpage = $type->rev_is_view_for_node->get_first_nos;

    $feed_info->{title      } = $type->name        if $type->name;
    $feed_info->{link       } = $req->site->home->get_virtual( $tpage->has_url )->url
      if $tpage and $tpage->has_url;

#    $feed_info->{base       } = 'http://ydalaby.se/'#$req->site->home->get_virtual( $blog->has_plugin_blog_base_url )
#      if $blog->has_plugin_blog_base_url;
    $feed_info->{description} = $type->description if $type->description;
    $feed_info->{modified   } = $type->created;
#    $feed_info->{language   } = 'sv_SE'; #$blog->is_in_language || 'sv_SE';

    my $posts = $type->rev_is->revlist('plugin_blog_post_is_in_blog',
				       { has_url_exist => 1 })
      ->flatten->sorted('has_date', 'desc')->limit(10);

    push @post_entries, $feed_info;

    while( my $post = $posts->get_next_nos )
    {
	my $entry = {};
	$entry->{id      } = $req->site->home->get_virtual( $post->has_url )->url;
	$entry->{link    } = $req->site->home->get_virtual( $post->has_url )->url;
	$entry->{title   } = $post->desig;
	$entry->{summary } = $post->description->loc;
	$entry->{content } = $post->has_body->loc;
	$entry->{modified} = $post->has_date;

	# Get author from is-arc
	my $author = $post->arc( 'is' )->created_by->get_first_nos;
	my $email  = $author->has_email->literal || 'dummy@ydalaby.se';
	$entry->{author} = $email .' ('. $author->desig .')';

	push @post_entries, $entry;

	$feed_info->{modified} = $entry->{modified}
	  if( $entry->{modified} > $feed_info->{modified} );
    }

    return \@post_entries;
}


1;
