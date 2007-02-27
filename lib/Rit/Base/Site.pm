#  $Id$  -*-cperl-*-
package Rit::Base::Site;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Site class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Site

=cut

use Carp qw( cluck confess croak carp );
use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

use Rit::Base::Resource;
use Rit::Base::Constants qw( $C_language );

### Inherit
#
use base qw( Para::Frame::Site );

=head1 DESCRIPTION

Inherits from L<Para::Frame::Site>.

#######################################################################

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

#######################################################################


1;

=head1 SEE ALSO

L<Rit::Base>

=cut