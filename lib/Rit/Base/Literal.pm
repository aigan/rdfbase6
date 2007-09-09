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

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base::Utils qw( is_undef valclean truncstring parse_propargs );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time;
use Rit::Base::Literal::URL;
use Rit::Base::Literal::Email::Address;

### Inherit
#
use base qw( Rit::Base::Node );

use overload
  '""'   => 'literal',
  fallback => 1,
  ;

=head1 DESCRIPTION

Represents a Literal.

A literal can only exist in one arc.

L<Rit::Base::Literal::String>, L<Rit::Base::Literal::Time> and L<Rit::Base::Undef> are
Literals.

Inherits from L<Rit::Base::Object>.

Supported args:

  subj_new
  pred_new
  coltype
  valtype


=cut


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

=head2 new

  $class->new( \$val )

Implement in subclasses!

Identifies the format and makes the apropriate literal object of it.

=cut

sub new
{
    my( $this, $val_in ) = @_;

    confess "TODO: Develope Literal->new";

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
	return Rit::Base::Literal::String->new( $val_in );
    }
}


#######################################################################

=head2 new_from_db

=cut

sub new_from_db
{
    confess "implement this ".datadump(\@_,2);
}


#######################################################################

=head2 parse

=cut

sub parse
{
    confess "implement this".datadump(\@_,2);
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


#######################################################################

=head2 is_literal

See L</Rit::Base::Object/is_literal>

=cut

sub is_literal
{
    return 1;
}


#########################################################################
################################  Public methods  #######################

=head2 equals

  $literal->equals( $val )

If C<$val> is a scalar, converts it to a L<Rit::Base::Literal::String>
object. (Undefs will become a L<Rit::Base::Undef> via
L<Rit::Base::Literal::String>.)

Returns true if both are L<Rit::Base::Literal> and has the same
L<Rit::Base::Object/syskey>.

C<syskey> is implemented in the subclasses to this class. For example,
L<Rit::Base::Literal::String>, L<Rit::Base::Literal::Time> and L<Rit::Base::Undef>.

=cut

sub equals
{
    my( $lit, $val, $args ) = @_;

    $val = Rit::Base::Literal::String->new($val)
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


#######################################################################

=head3 this_valtype

  $lit->this_valtype()

This is like this C<is> property for literals. Defaults to
L</default_valtype>.

See also: L<Rit::Base::Resource/this_valtype>

=cut

sub this_valtype
{
    unless( ref $_[0] )
    {
	return $_[0]->default_valtype;
    }

    if( my $valtype = $_[0]->{'valtype'} )
    {
	return $valtype;
    }

    return $_[0]->default_valtype();
}

#######################################################################

=head3 this_coltype

  $lit->this_coltype()

This gives the coltype of the value of this literal.

returns: the plain string of table column name

See also: L<Rit::Base::Resource/this_coltype>

=cut

sub this_coltype
{
    return $_[0]->this_valtype->coltype;
}

#######################################################################

=head3 subj

Get existing or planned subj

=cut

sub subj
{
    my( $this, $args_in ) = @_;

    if( ref $this )
    {
	my $lit = $this;
	if( my $arc = $lit->arc )
	{
	    return $arc->subj;
	}
    }

    my $class = $this;
    my( $args ) = parse_propargs($args_in);
    if( my $arc = $args->{'arc'} )
    {
	return $arc->subj;
    }

    return $args->{'subj_new'} || is_undef;
}

#######################################################################

=head3 pred

Get existing or planned pred

=cut

sub pred
{
    my( $this, $args_in ) = @_;

    if( ref $this )
    {
	my $lit = $this;
	if( my $arc = $lit->arc )
	{
	    return $arc->pred;
	}
    }

    my $class = $this;
    my( $args ) = parse_propargs($args_in);
    if( my $arc = $args->{'arc'} )
    {
	return $arc->pred;
    }

    return $args->{'pred_new'} || is_undef;
}

#######################################################################

=head2 extract_string

  $class->extract_string( \$val, \%args )


Supported args are:
  valtype
  coltype
  arclim

For use in L</parse> methods.

Thre C<$retval> will either be a scalar ref of the plain value to
parse, or a L<Rit::Base::Literal> object.

Returns: The list ( $retval, $coltype, $valtype, $args )

=cut

sub extract_string
{
    my( $class, $val_in, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $valtype = $args->{'valtype'} || $class->default_valtype;
    my $coltype = $valtype->coltype;

    my $val;
    if( ref $val_in )
    {
	$val = $val_in;
    }
    else
    {
	$val = \$val_in;
    }

    if( ref $val eq 'SCALAR' )
    {
	return( $val, $coltype, $valtype, $args );
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal" )
    {
	# Validate below
    }
    elsif( (ref $val eq 'HASH') or
	   (ref $val eq 'ARRAY') or
	   (UNIVERSAL::isa $val, "Para::Frame::List")
	 )
    {
	$val = Rit::Base::Resource->get_by_anything( $val,
						     {
						      %$args,
						      valtype => $valtype,
						     });
	return( $val, $coltype, $valtype, $args );
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Resource" )
    {
	if( my $arc = $val->first_arc('value', $args) )
	{
	    $val = $arc->value;
	}
	else
	{
	    confess "$val->{id} is not a value node";
	}
    }
    else
    {
	confess "Can't parse $val";
    }

    # TODO: check for compatible valtype

    return( $val, $coltype, $valtype, $args );

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
