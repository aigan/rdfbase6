package RDF::Base::Translatable;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Translatable

=cut

use 5.010;
use strict;
use warnings;

use CGI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

##############################################################################

=head2 loc

Just an optimization for loc($node) or $node->has_translation->loc

=cut

sub loc
{
    return $Para::Frame::REQ->{'lang'}->maketext(@_);
}

##############################################################################

sub as_html
{
    return CGI->escapeHTML($Para::Frame::REQ->{'lang'}->maketext(@_));
}


##############################################################################

sub on_arc_add
{
    shift->clear_caches(@_);
}

##############################################################################

sub on_arc_del
{
    shift->clear_caches(@_);
}


##############################################################################

sub clear_caches
{
#    debug "Clear caches";
    %RDF::Base::L10N::TRANSLATION = ();
}

##############################################################################

1;
