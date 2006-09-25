#  $Id$  -*-cperl-*-
package Rit::Base::Constant;

=head1 NAME

Rit::Base::Constant

=cut

use strict;
use Carp qw( croak cluck confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base;

### Inherit
#
use base qw( Rit::Base::Object );

sub label
{
    return $_[0]->{'label'};
}

sub node
{
    return $_[0]->{'node'};
}

sub node_id
{
    return $_[0]->{'sub'};
}

sub id
{
    return $_[0]->{'sub'};
}

sub sysdesig
{
    return "constant ".$_[0]->label;
}

sub desig
{
    return $_[0]->label;
}

1;
