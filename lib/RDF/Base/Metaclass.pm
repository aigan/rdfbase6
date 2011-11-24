package RDF::Base::Metaclass;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Metaclass

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( cluck confess croak carp );

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;


=head1 DESCRIPTION

This is a class for objects that inherits from more than one special
class. See L<Para::Frame::Resource/find_class>.

Those metaclasses inherits from this and the other classes.

If a class wants to reimplement a method existing
L<RDF::Base::Resource>, that method must be specially implemented
here, because only the first method will be found and if we inherit from
two classes and only one of them implements say C<desig>, it may be
the other class that gets tried first and then it will use
L<RDF::Base::Resource/desig>.

We may introduce class priority for determining which class is tried
first.

=cut

########################################################################

=head2 on_arc_add

  $node->on_arc_add( $arc, $pred_name )

Called by L<RDF::Base::Arc/create_check>

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

=head2 on_revarc_add

  $node->on_revarc_add( $arc, $pred_name )

Called by L<RDF::Base::Arc/create_check>

Distributes the calls over the classes

=cut

sub on_revarc_add
{
    my $n = shift;
    my $class = ref $n;
    no strict "refs";

    foreach my $sc (@{"${class}::ISA"})
    {
	next if $sc eq __PACKAGE__;
	if( my $method = $sc->can("on_revarc_add") )
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

Called by L<RDF::Base::Arc/remove_check>

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
#	$n->("${sc}::on_revarc_del")(@_);
    }

    return;
}


########################################################################

=head2 on_revarc_del

  $node->on_revarc_del( $arc, $pred_name )

Called by L<RDF::Base::Arc/remove_check>

Distributes the calls over the classes

=cut

sub on_revarc_del
{
    my $n = shift;
    my $class = ref $n;
    no strict "refs";

    foreach my $sc (@{"${class}::ISA"})
    {
	next if $sc eq __PACKAGE__;
	if( my $method = $sc->can("on_revarc_del") )
	{
	    &{$method}($n, @_);
	}
#	$n->("${sc}::on_revarc_del")(@_);
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
	debug "  Vacuum via $sc";
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

L<RDF::Base>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::List>,
L<RDF::Base::Search>,
L<RDF::Base::Literal::Time>

=cut
