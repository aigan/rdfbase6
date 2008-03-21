#  $Id$  -*-cperl-*-
package Rit::Base::Metaclass;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Metaclass

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


=head1 DESCRIPTION

This is a class for objects that inherits from more than one special
class. See L<Para::Frame::Resource/find_class>.

Those metaclasses inherits from this and the other classes.

If a class wants to reimplement a method existing
L<Rit::Base::Resource>, that method must be specially implemented
here, because only the first method will be found and if we inherit from
two classes and only one of them implements say C<desig>, it may be
the other class that gets tried first and then it will use
L<Rit::Base::Resource/desig>.

We may introduce class priority for determining which class is tried
first.

=cut

########################################################################

=head2 on_arc_add

  $node->on_arc_add( $arc, $pred_name )

Called by L<Rit::Base::Arc/create_check>

Distributes the calls over the classes

=cut

sub on_arc_add
{
    my $n = shift;
    my $class = ref $n;
    no strict "refs";

    foreach my $sc (@{"${class}::ISA"})
    {
	next if $sc eq __PACKAGE__;
	if( my $method = $sc->can("on_arc_add") )
	{
	    &{$method}($n, @_);
	}
#	$n->("${sc}::on_arc_add")(@_);
    }

    return;
}


########################################################################

=head2 on_arc_del

  $node->on_arc_del( $arc, $pred_name )

Called by L<Rit::Base::Arc/remove_check>

Distributes the calls over the classes

=cut

sub on_arc_del
{
    my $n = shift;
    my $class = ref $n;
    no strict "refs";

    foreach my $sc (@{"${class}::ISA"})
    {
	next if $sc eq __PACKAGE__;
	if( my $method = $sc->can("on_arc_del") )
	{
	    &{$method}($n, @_);
	}
#	$n->("${sc}::on_arc_del")(@_);
    }

    return;
}


########################################################################
#
#=head2 desig
#
#  $n->desig()
#
#Calls first desig
#
#=cut
#
#sub desig
#{
#}
#
#
########################################################################
#
#=head2 sysdesig
#
#  $n->sysdesig()
#
#Calls first sysdesig
#
#=cut
#
#sub sysdesig  # The designation of obj, including node id
#{
#}
#
#
########################################################################

=head2 vacuum

  $n->vacuum()

Distributes calls over classes

=cut

sub vacuum
{
    my $n = shift;
    my $class = ref $n;
    no strict "refs";

    foreach my $sc (@{"${class}::ISA"})
    {
	next if $sc eq __PACKAGE__;
	if( my $method = $sc->can("vacuum") )
	{
	    &{$method}($n, @_);
	}
    }

    return $n;
}


########################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>,
L<Rit::Base::Literal::Time>

=cut
