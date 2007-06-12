#  $Id$  -*-cperl-*-
package Rit::Base::Object;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Objects base class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Object

=cut

use strict;
use Carp qw( cluck confess carp croak );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use base qw( Rit::Base::Object::Compatible );


=head1 DESCRIPTION

Base class for L<Rit::Base::List> and L<Rit::Base::Node>.

These holds common methods. For getting specific types of
presentations of the object. There are quite a lot of them for getting
the value of an object.

=cut

#######################################################################

=head2 defined

  $o->defined

Returns true unless this is a L<Rit::Base::Undef>.

=cut

sub defined {1}


#######################################################################

=head2 is_true

  $o->is_true

Returns 1 if true and 0 if false.

=cut

sub is_true {1}


######################################################################

=head2 is_list

  $o->is_list

Returns true if this is a L<Rit::Base::List>.

=cut

sub is_list
{
    return 0;
}


#######################################################################

=head2 is_pred

  $o->is_pred

Returns true is this is a L<Rit::Base::Pred>.

=cut

sub is_pred { 0 };


#######################################################################

=head2 is_arc

  $o->is_arc

Returns true if object is an L<Rit::Base::Arc>.

=cut

sub is_arc { 0 };


#######################################################################

=head2 is_resource

  $o->is_resource

Returns true if object is a Resource.

=cut

sub is_resource { 0 };


#######################################################################

=head2 is_node

  $o->is_node

Returns true if object is a Node.

=cut

sub is_node { 0 };


#######################################################################

=head2 is_value_node

  $o->is_value_node

Returns true if this is a Literal Resource (aka value node).

Liuteral Resources are nodes representing a Literal. For example
Instead of

  $obj -name-> $name

we could have

  $obj -name-> $valobj,
  $valobj -value-> $name,
  $valobj -is_of_language-> $langobj.

=cut

sub is_value_node { 0 };


#######################################################################

=head2 desig

  $o->desig()

A general alfanumerical presentation of the designation of the
object. Intended for presentation and not for data manipulation.

=cut

sub desig
{
    confess "implement this";
}


#######################################################################

=head2 sysdesig

  $o->sysdesig()

The same as L</desig> but more suited for debugging. The alfanumerical
string will include the object id number or corresponding extra info
for identifying the object. Intended for presentation and not for data
manipulation.

=cut

sub sysdesig
{
    confess "Implement this";
}


#######################################################################

=head2 syskey

  $o->syskey

This will generate a unique alfanumerical string that cen be used for
discriminating this object from all other objects.  The alfanumerical
code returned will usually include the type of object and the object
id. Intended for data manipulation, such as caching.

=cut

sub syskey
{
    confess "Implement this";
}


#######################################################################

sub literal
{
    croak "Only used for Literal Resources!";
}


#######################################################################

=head2 loc

  $o->loc

  $o->loc(@args)

Similar to L</desig>, but will choose the most suitible name if there are
more than one to choose from. It will pick a name based on language or
priority.

Uses the args in L<Para::Frame::L10N/compile>.

=cut

sub loc
{
    confess "Implement this";
}


#######################################################################

=head2 plain

  $o->plain

This method converts objects to plain perl datatypes. It will convert
a Literal object to a perl string, an undef object to the undef value,
etc.

See L<Rit::Base::Resource/plain> et al.

=cut

sub plain
{
    confess "Implement this";
}


#######################################################################

=head2 clean

  $o->clean

Returns the clean version of the value as a Literal obj.

TODO: Only in Literal...

=cut

sub clean
{
    confess "Implement this";
}


#######################################################################

=head2 equals

  $obj1->equals( $obj2 )

Tests if two objects are the same object.

=cut

sub equals
{
    confess "Implement this";
}


#######################################################################

=head2 as_string

  $o->as_string

Not used. Please be more specific. What kind of string?

=cut

sub as_string
{
    croak "wrong turn";
}


#######################################################################

=head2 size

=cut

sub size
{
    return 1;
}

#######################################################################

=head2 get_first

  $literal->get_first()

Gets the first value from a list, or the value itselft if it's not a
list.

May return a second value with a error status code if the list is
empty. See L</get_first_nos>.

=cut

sub get_first
{
    return $_[0];
}

#######################################################################

=head2 get_first_nos

  $literal->get_first_nos()

Gets the first value from a list, or the value itselft if it's not a
list. Does not return a status code (get first with no status).

=cut

sub get_first_nos
{
    return $_[0];
}

#######################################################################

=head2 as_list

  $literal->as_list()

Returns a referens to a list. Not a List object. The list content are
materialized.

=cut

sub as_list
{
    return [$_[0]];
}

#######################################################################

=head2 nodes

  $literal->nodes()

Just as as_list but regards the SCALAR/ARRAY context.

=cut

sub nodes
{
    if( wantarray )
    {
	return $_[0];
    }
    else
    {
	return [$_[0]];
    }
}

#######################################################################

=head2 coltype

This node has the coltype C<obj>.

TODO: Should be called something else.  What to do about literals that
may be values?

=cut

sub coltype
{
    confess "Not implemented";
    'obj';
}


#######################################################################

=head2 meets_proplim

  $obj->meets_proplim( $proplim, \%args )

This is implemented for L<Rit::Base::Resource>. Other objects returns
false if proplim is defined and has content.

=cut

sub meets_proplim
{
    return 1 unless $_[1];
    return 1 unless keys %{$_[1]};
    return 0;
}


#######################################################################

=head2 has_value

  $literal->has_value( ... )

Returns: false

=cut

sub has_value
{
    return 0;
}


#######################################################################

=head2 has_pred

  $literal->has_pred( ... )

Returns: false

=cut

sub has_pred
{
    return 0;
}


#######################################################################

=head2 contains_any_of

  $obj->contains_any_of( $node, \%args )

  $obj->contains_any_of( $list, \%args )

See L<Rit::Base::List::contains_any_of>

Only checks this single object.

=cut

sub contains_any_of
{
    my( $obj, $tmpl, $args ) = @_;

    if( ref $tmpl )
    {
	if( ref $tmpl eq 'Rit::Base::List' )
	{
	    foreach my $val (@{$tmpl->as_list})
	    {
		debug 2, sprintf "  check list item %s", $val->sysdesig;
		return 1 if $obj->contains_any_of($val, $args);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'ARRAY' )
	{
	    foreach my $val (@$tmpl )
	    {
		debug 2, sprintf "  check array item %s", $val->sysdesig;
		return 1 if $obj->contains_any_of($val, $args);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'Para::Frame::List' )
	{
	    foreach my $val ($tmpl->as_list)
	    {
		debug 2, sprintf "  check list item %s", $val->sysdesig;
		return 1 if $obj->contains_any_of($val, $args);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'HASH' )
	{
	    die "Not implemented: $tmpl";
	}
    }

    # Default for simple values and objects:

    return $obj if $obj->equals($tmpl, $args);

    debug 2,"    failed";
    return undef;
}

######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Node>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
