#  $Id$  -*-cperl-*-
package Rit::Base::Literal;
#=====================================================================
#
# DESCRIPTION
#   Ritbase node Literal class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal

=cut

use strict;
use Carp qw( cluck confess carp );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( debug );
use Para::Frame::Reload;

use Rit::Base::Utils qw( is_undef valclean truncstring );
use Rit::Base::String;

### Inherit
#
use base qw( Rit::Base::Node );

use overload
  '""'   => 'literal',
  ;

=head1 DESCRIPTION

Represents a Literal.

A literal can only exist in one arc.

L<Rit::Base::String>, L<Rit::Base::Time> and L<Rit::Base::Undef> are
Literals.

Inherits from L<Rit::Base::Object>.

=cut


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

=head2 new

Identifies the format and makes the apropriate literal object of it.

=cut

sub new
{
    my( $this, $val_in ) = @_;

    # Assume its string or undef

    if( not defined $val_in )
    {
	return is_undef;
    }
    elsif( ref $val_in )
    {
	die "Valformed value: $val_in";
    }
    else
    {
	return Rit::Base::String->new( $val_in );
    }
}


#######################################################################

=head2 as_list

Returns value as L<Rit::Base::List>

=cut

sub as_list
{
    # Used by List AUTOLOAD

    return Rit::Base::List->new([shift]);
}

#######################################################################

=head2 nodes

Just as L</as_list> but regards the SCALAR/ARRAY context.

=cut

sub nodes
{
    # Used by List AUTOLOAD
    if( wantarray )
    {
	return(shift);
    }
    else
    {
	return Rit::Base::List->new([shift]);
    }
}

#######################################################################

=head2 id

Literals has no id.  Retuns undef.

=cut

sub id
{
    return undef;
}


#######################################################################

=head2 arc

=head2 revarc

  $literal->arc

Return the arc for this literal

=cut

sub arc
{
    $_[0]->{'arc'} || is_undef;
}

sub revarc
{
    $_[0]->{'arc'} || is_undef;
}


#######################################################################

=head2 is_true

See L</Rit::Base::Object/is_true>

=cut

sub is_true
{
    return $_[0] ? 1 : 0;
}


#########################################################################
################################  Public methods  #######################

=head2 equals

  $literal->equals( $val )

If C<$val> is a scalar, converts it to a L<Rit::Base::String>
object. (Undefs will become a L<Rit::Base::Undef> via
L<Rit::Base::String>.)

Returns true if both are L<Rit::Base::Literal> and has the same
L<Rit::Base::Object/syskey>.

C<syskey> is implemented in the subclasses to this class. For example,
L<Rit::Base::String>, L<Rit::Base::Time> and L<Rit::Base::Undef>.

=cut

sub equals
{
    my( $lit, $val, $args ) = @_;

    $val = Rit::Base::String->new($val)
      unless( ref $val );

    if( ref $val and UNIVERSAL::isa($val, 'Rit::Base::Literal') )
    {
	if( $lit->syskey($args) eq $val->syskey($args) )
	{
	    return 1;
	}
    }

    return 0;
}


#######################################################################

=head2 update

The API is the same as for L<Rit::Base::Resource/update>.

This converts the literal to a value node.

Example:

  $node->name->update({ is_of_language => $C_swedish });

=cut

sub update
{
    my( $literal, $props, $args ) = @_;

    # Just convert to value node and forward the call.
    # But check if we realy have props to add

    if( keys %$props )
    {
	my $arc = $literal->arc or die "Literal has no defined arc";
	my $node = Rit::Base::Resource->create( $props, $args );
	Rit::Base::Arc->create({
				subj    => $node,
				pred    => 'value',
				value   => $literal,
				valtype => $arc->valtype,
			       }, $args);

	$arc = $arc->set_value( $node, $args );
    }

    return $literal;
}


#######################################################################

=head2 set_arc

  $literal->set_arc( $arc )

Bind Literal to arc.

=cut

sub set_arc
{
    my( $literal, $arc ) = @_;

#    carp "set_arc to $arc for $literal called by";
    $literal->{'arc'} = $arc;

    return $arc;
}


#######################################################################

=head2 initiate_cache

  $literal->initiate_cache( $arc )

Resets value metadata. But keeps the actual value.

=cut

sub initiate_cache
{
    my( $literal, $arc ) = @_;

    $literal->set_arc( $arc );

    return $literal;
}


#########################################################################
################################  Private methods  ######################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
