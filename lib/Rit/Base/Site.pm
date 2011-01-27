package Rit::Base::Site;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Rit::Base::Site

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Site );

use Carp qw( cluck confess croak carp );

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

use Rit::Base::Resource;
use Rit::Base::Constants qw( $C_language );


=head1 DESCRIPTION

Inherits from L<Para::Frame::Site>.

##############################################################################

=head2 languages_as_nodes

  Returns a L<Rit::Base::List> of language resources.

=cut

sub languages_as_nodes
{
    if( $_[0]->{'language_nodes'} )
    {
	return $_[0]->{'language_nodes'};
    }

    my $site = shift;
    my @list;
    foreach my $code (@{ $site->languages })
    {
	my $node = Rit::Base::Resource->get({(code=>$code, is=>$C_language)});
	push @list, $node;
    }
    return $site->{'language_nodes'} = Rit::Base::List->new(\@list);
}

##############################################################################


1;

=head1 SEE ALSO

L<Rit::Base>

=cut
