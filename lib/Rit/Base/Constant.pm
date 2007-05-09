#  $Id$  -*-cperl-*-
package Rit::Base::Constant;
#=====================================================================
#
# DESCRIPTION
#   Ritbase constant class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Constant

=cut

use strict;
use Carp qw( croak cluck confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
    die "DEPRECATED";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base;

### Inherit
#
use base qw( Rit::Base::Object );


#######################################################################

=head2 label

=cut

sub label
{
    return $_[0]->{'label'};
}


#######################################################################

=head2 node

=cut

sub node
{
    return $_[0]->{'node'};
}


#######################################################################

=head2 node_id

=cut

sub node_id
{
    return $_[0]->{'sub'};
}


#######################################################################

=head2 id

=cut

sub id
{
    return $_[0]->{'sub'};
}


#######################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    return "constant ".$_[0]->label;
}


#######################################################################

=head2 desig

=cut

sub desig
{
    return $_[0]->label;
}

#######################################################################

1;


=head1 SEE ALSO

L<Para::Frame>,
L<Rit::Base>

=cut
