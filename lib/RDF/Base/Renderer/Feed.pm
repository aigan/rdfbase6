package RDF::Base::Renderer::Feed;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2010-2017 Fredrik Liljegren.  All Rights Reserved.
#
#		This module is free software; you can redistribute it and/or
#		modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;
use utf8;
use base 'Para::Frame::Renderer::Custom';

use CGI::Carp qw(fatalsToBrowser);
use DateTime;
use XML::Feed;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw datadump
			   trim package_to_module compile );
use Para::Frame::L10N qw( loc );

use RDF::Base::Utils qw( arc_lock arc_unlock );

use RDF::Base::CMS::Page;

=head1 Usage

This should be set as renderer for url's ending in .rss or .atom, with
a node ID as query parameter.  The node should be handled by a module
giving the method get_feed_and_entries_info, returning a list of
hashes with info for the feed, the first hash containing the feed
info.  See XML::Feed for field names.

<FilesMatch ".atom$|.rss$|^feed$">
  SetHandler perl-script
  PerlSetVar renderer RDF::Base::Renderer::Feed
  PerlSetVar loadpage no
</FilesMatch>

=cut

sub render_output
{
    my( $rend ) = @_;

    debug "Rendering Feed response.";

    my $req = $rend->req;
    my $q = $req->q;
    my $R = RDF::Base->Resource;

    my $id   = $q->param('id')
      or die('No ID'); # Should give error as Feed...

    my $feed_and_entries_info;

    if ($id eq 'pages') {
      # hack, until I get to making cms_page NODE handled by perl module...
      debug('getting pages?');
      $feed_and_entries_info
        = RDF::Base::CMS::Page->get_feed_and_entries_info( $req );
    }
    else {
      my $node = $R->get($id)
        or die('Bad ID'); # Should give error as Feed...

      eval {
        $feed_and_entries_info
          = $node->get_feed_and_entries_info( $req );
      };
    }

    my $format
      = $q->param('format')             ? $q->param('format')
      : ( $rend->url_path =~ /\.rss$/ ) ? 'RSS'
                                        : 'Atom'
      ;


    my @feed_args = ( $format );
    push @feed_args, ( version => $q->param('version') )
      if( $q->param('version') );

    my $feed = new XML::Feed( @feed_args );

    my $feed_id = $req->site->home->get_virtual( $rend->url_path )->url .'?id='. $id;
    $feed->self_link( $feed_id );
    $feed->id       ( $feed_id );
    my $feed_info = shift @{$feed_and_entries_info};

    foreach my $feed_info_key (keys %{$feed_info})
    {
	$feed->$feed_info_key( $feed_info->{$feed_info_key} );
    }

    foreach my $entry_info (@{$feed_and_entries_info})
    {
	my $entry = XML::Feed::Entry->new();

	foreach my $entry_info_key (keys %{$entry_info})
	{
	    $entry->$entry_info_key( $entry_info->{$entry_info_key} );
	}

	$feed->add_entry($entry);
    }

    $rend->{'ctype'} = $format;

    my $out = $feed->as_xml;

    return \$out;
}


##############################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    if( $rend->{'ctype'} eq 'Atom' )
    {
	$ctype->set("application/atom+xml");
    }
    else
    {
	$ctype->set("application/rss+xml");
    }
}


##############################################################################

1;
