package Rit::Base::CMS::Page;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <jonas@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2011 Fredrik Liljegren.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Carp qw( confess );
use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug datadump deunicode );
use Para::Frame::L10N qw( loc );

use Rit::Base::Utils qw( valclean parse_propargs query_desig );
use Rit::Base::Constants qw( $C_cms_page );


=head1 NAME

Rit::Base::CMS::Page

=cut

=head1 DESCRIPTION

=cut

sub get_feed_and_entries_info
{
    my( $class, $req ) = @_;

    my @post_entries;

    my $feed_info = {};

    my $R = Rit::Base->Resource;

    $feed_info->{title} = 'Pages on ' . $req->site->name; # .. ' on site ?'
    $feed_info->{link } = $req->site->home->url; # site base url
    $feed_info->{base } = $req->site->home->url; # site base url
#      if $class->has_plugin_blog_base_url;
#    $feed_info->{description} = $class->description if $class->description;
    $feed_info->{modified   } = $C_cms_page->arc( 'is' )->created;
#    $feed_info->{language   } = 'sv_SE'; #$class->is_in_language || 'sv_SE';
    

    my $pages = $C_cms_page->rev_is #({ has_url_exist => 1 })
      ->sorted('has_date', 'desc');

    push @post_entries, $feed_info;

    while( my $page = $pages->get_next_nos )
    {
	next unless $page->has_url;
	my $entry = {};
	$entry->{id      } = $req->site->home->get_virtual( $page->has_url )->url;
	$entry->{link    } = $req->site->home->get_virtual( $page->has_url )->url;
	$entry->{title   } = $page->desig;
	$entry->{summary } = $page->description->loc;
	$entry->{content } = $page->has_body->loc;
	$entry->{modified} = $page->has_date;

	my $is_arc = $page->arc_list( 'is' )->get_first_nos;

	if ($is_arc) {
	    #$entry->{modified} = $is_arc->created;

	    $entry->{modified} = $page->arc_list->sorted('created', 'desc')->get_first_nos->created;

	    $feed_info->{modified} = $entry->{modified}
                if( 0 and $entry->{modified} > $feed_info->{modified} );

	    my $author = $is_arc->created_by->get_first_nos;
	    my $email  = $author->has_email->literal;
	    $entry->{author} = $email .' ('. $author->desig .')'
		if $author and $email;
	}

	push @post_entries, $entry;

    }

    return \@post_entries;
}

1;
