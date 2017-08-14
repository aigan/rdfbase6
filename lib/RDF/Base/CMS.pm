package RDF::Base::CMS;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <jonas@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2009-2017 Fredrik Liljegren.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Carp qw( confess );
use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug datadump deunicode );
use Para::Frame::L10N qw( loc );

use RDF::Base::Utils qw( valclean parse_propargs query_desig );


=head1 NAME

RDF::Base::CMS

  =cut

  =head1 DESCRIPTION

  This code requires the following nodes setup:

  label          => 'cms_page',
  is             => 'class',
  class_form_url => 'rb/cms/page.tt',

  label  => 'has_url',
  is     => 'predicate',
  domain => 'cms_page',
  range  => 'text',

  label  => 'is_view_for_node',
  is     => 'predicate',
  domain => 'cms_page',
  range  => 'resource',

  label  => 'uses_template',
  is     => 'predicate',
  domain => 'cms_page',
  range  => 'text',

  label       => 'message',
  is          => 'class',
  description => 'A message is a page_part, could be a forum-message.',

  label  => 'has_body',
  is     => 'predicate',
  domain => 'message',


=cut


##############################################################################

=head2 find

For finding which template to use for an URL.

Handling publish on demand.

=cut

sub find {
  my( $class, $p_in ) = @_;

  my $req = $Para::Frame::REQ;

  my( $args, $arclim, $res ) = parse_propargs('auto');
  my $p = $p_in->normalize;
  my $R = RDF::Base->Resource;

  my $path = $p->path_slash;

  # Firstly check for the common case
  #my $target_in = $p->target_with_lang;
  my $target_in = $p->target;
  my $target_path = $target_in->path_slash;

  if( $target_in->exist and not $target_in->is_dir )
  {
#       debug "  file exists";
    return $target_in;
  }

  debug "CMS: Looking for '$path'" if debug;

  my $page = $R->find(
    {
      is  => 'cms_page',
      has_url => $path,
    }, $args)->get_first_nos;

  if (not $page and $target_path =~ /^(.*)\/index.tt$/) {
    debug "CMS: No luck with '$path'.  Trying '$1'";
    $page = $R->find(
      {
        is  => 'cms_page',
        has_url => $1,
      }, $args)->get_first_nos;
  }

  if (not $page) {
    debug "CMS: Still no page.  Trying '$target_path'" if debug;
    $page = $R->find(
      {
        is  => 'cms_page',
        has_url => $target_path,
      }, $args)->get_first_nos
        if not $page;
  }

  if ($page) {
    debug "Found a page!  ID ". ref($page) if debug;
    my $end_target = $req->site->home->get_virtual( $page->uses_template );
    $req->q->param( id => $page->id);
    debug "  - Using end target: ". $end_target->sysdesig if debug;

    return $end_target;
  }
  else {
    debug "CMS: No page.  Giving up now, place your hope in paraframe..." if debug;
  }

  return;
}

1;

