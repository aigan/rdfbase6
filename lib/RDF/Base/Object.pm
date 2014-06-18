package RDF::Base::Object;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Object

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( cluck confess carp croak );
#use CGI;
use Text::WordDiff;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

### Those modules loaded by RDF::Base later...
#use RDF::Base::Undef;



=head1 DESCRIPTION

Base class for L<RDF::Base::List> and L<RDF::Base::Node>.

These holds common methods. For getting specific types of
presentations of the object. There are quite a lot of them for getting
the value of an object.

=head1 General syntax

See the respektive method for examples. The respective method usually
starts with a C<$pred> argument followed by a C<\%props> or
C<\@values> argument.  We will describe the syntax based on the method
C<$n-E<gt>list( $pred, @propargs )>.

C<$value> is anything that's not a hash- or arrayref and that's the
only (true) argument. It will return those nodes/arcs with a matching
value. For L</list>, it will return the value of the node C<$n>
property C<$pred> that equals C<$value>. That value may have to be
converted to the right object type before a vomparsion.

C<\@values> matches any value of the list. For example,
C<$nE<gt>list($pred, [$alt1, $alt2])> will return a list with zero or
more of the nodes C<$alt1> and C<$alt2> depending on if C<$n> has
those properties with pred C<$pred>.

C<\%props> holds key/value pairs of properties that the matches should
have. L<RDF::Base::List/find> is used to filter out the nodes/arcs
having those properties. For example, C<$n-E<gt>list('part_of', { name
=E<gt> 'Turk' }> will give you the nodes that C<$n> are C<part_of>
that has the C<name> C<Turk>.

C<\%args> holds any extra arguments to the method as name/value
pairs. The C<arclim> argument is always parsed and converted to a
L<RDF::Base::Arc::Lim> object. This will modify the args variable in
cases when arclim isn't already a valid object.

=cut

##############################################################################

=head2 defined

  $o->defined

Returns true unless this is a L<RDF::Base::Undef>.

=cut

sub defined {1}


##############################################################################

=head2 is_true

  $o->is_true

Returns 1 if true and 0 if false.

=cut

sub is_true {1}


######################################################################

=head2 is_list

  $o->is_list

Returns true if this is a L<RDF::Base::List>.

=cut

sub is_list
{
    return 0;
}


##############################################################################

=head2 is_pred

  $o->is_pred

Returns true is this is a L<RDF::Base::Pred>.

=cut

sub is_pred { 0 };


##############################################################################

=head2 is_arc

  $o->is_arc

Returns true if object is an L<RDF::Base::Arc>.

=cut

sub is_arc { 0 };


##############################################################################

=head2 is_resource

  $o->is_resource

Returns true if object is a Resource.

=cut

sub is_resource { 0 };


##############################################################################

=head2 is_literal

  $o->is_literal

Returns true if object is a L<RDF::Base::Literal>

=cut

sub is_literal { 0 };


##############################################################################

=head2 is_node

  $o->is_node

Returns true if object is a Node.

=cut

sub is_node { 0 };


##############################################################################

=head2 is_value_node

  $o->is_value_node

Returns true if this is a Literal Resource (aka value node).

Literal Resources are nodes representing a Literal.

=cut

sub is_value_node { 0 };


##############################################################################

=head2 as_html

  $o->as_html( \%args )

Preformatted text should use E<lt>preE<gt> to preserve indentation.

This default will only preserve linefeed.

Defaults to L</desig>

=cut

sub as_html
{
    my( $str ) = CGI->escapeHTML(shift->desig(@_));
    $str =~ s/\r?\n/<br\/>/g;
    return $str;
}


##############################################################################

=head2 diff_as_html

  $o->diff_as_html( \%args )

Uses L</desig> as base for displaying diffrence

See L<String::ShowHTMLDiff>

=cut

sub diff_as_html
{
    my( $o, $args ) = @_;

    $args ||= {};
    my $old = $args->{'old'} || '';
#    my $context = $args->{'context'} || qr/\w*/;
#    my $gap = $args->{'gap'} || ' ';

    if( ref $old )
    {
	$old = $old->desig;
    }

    my $new = $o->desig;

    my $out = "";

#"<style> div.file del {background-color:red} div.file ins {background-color:green}</style>";

#    $old =~ s/\n*$/\n/;
#    $new =~ s/\n*$/\n/;
#    debug "DIFFING STRINGS:";
#    debug "old:\n".$old."<<<";
#    debug "new:\n".$new."<<<";

    my $diff = word_diff(\$old, \$new, { STYLE => 'HTML' });

#    $diff =~ s/\n/<br\/>\n/g;

    return $out . "<pre>".$diff."</pre>";
}


##############################################################################

=head2 desig

  $o->desig()

A general alphanumerical presentation of the designation of the
object. Intended for presentation and not for data manipulation.

=cut

sub desig
{
    confess "implement this";
}


##############################################################################

=head2 longdesig

  $o->longdesig()

May give a longer name of the object. Defaults to L</desig>

=cut

sub longdesig
{
    my( $node, $args ) = @_;
    $args ||= {};
    $args->{desig_length_max} ||= 250;
    return $node->desig($args);
}


##############################################################################

=head2 shortdesig

  $o->shortdesig()

May give a longer name of the object. Defaults to L</desig>

=cut

sub shortdesig
{
    return shift->desig(@_);
}


##############################################################################

=head2 safedesig

  $o->safedesig()

=cut

sub safedesig
{
    return shift->sysdesig(@_);
}


##############################################################################

=head2 sysdesig

  $o->sysdesig()

The same as L</desig> but more suited for debugging. The alphanumerical
string will include the object id number or corresponding extra info
for identifying the object. Intended for presentation and not for data
manipulation.

=cut

sub sysdesig
{
    confess "Implement this";
}


##############################################################################

=head2 syskey

  $o->syskey

This will generate a unique alphanumerical string that cen be used for
discriminating this object from all other objects.  The alphanumerical
code returned will usually include the type of object and the object
id. Intended for data manipulation, such as caching.

=cut

sub syskey
{
    confess "Implement this";
}


##############################################################################

sub literal
{
    croak "Only used for Literal Resources!";
}


##############################################################################

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


##############################################################################

=head2 plain

  $o->plain

This method converts objects to plain perl datatypes. It will convert
a Literal object to a perl string, an undef object to the undef value,
etc.

See L<RDF::Base::Resource/plain> et al.

=cut

sub plain
{
    confess "Implement this";
}


##############################################################################

=head2 clean

  $o->clean

Returns the clean version of the value as a Literal obj.

TODO: Only in Literal...

=cut

sub clean
{
    confess "Implement this";
}


##############################################################################

=head2 equals

  $obj1->equals( $obj2 )

Tests if two objects are the same object.

=cut

sub equals
{
    confess "Implement this";
}


##############################################################################

=head2 matches

  $n->matches( $value, \%args )

Supported args are:

  match

Default match is C<eq>

C<%args> must be specified

Supported matches are:

  eq
  ne
  gt
  lt
  begins
  like

Returns: true if C<$n $match $value>

=cut

sub matches
{
    my( $obj, $val, $args ) = @_;
    return 0 unless defined $val;

    my $match = $args->{'match'} || 'eq';

    if( delete $args->{'clean'} )
    {
	$obj = $obj->clean;
	$val = $val->clean;
    }

    if( $match eq 'eq' )
    {
	return 1 if $obj->equals( $val, $args );
    }
    elsif( $match eq 'ne' )
    {
	return 1 unless $obj->equals( $val, {%$args,match=>'eq'} );
    }
    elsif( $match eq 'gt' )
    {
	my $coltype = $obj->this_coltype;
	if( $coltype eq 'valtext' )
	{
	    return 1 if $obj gt $val;
	}
	else # Anything else should have overloaded '>'
	{
	    return 1 if $obj > $val;
	}
    }
    elsif( $match eq 'lt' )
    {
	my $coltype = $obj->this_coltype;
	if( $coltype eq 'valtext' )
	{
	    return 1 if $obj lt $val;
	}
	else # Anything else should have overloaded '<'
	{
	    return 1 if $obj < $val;
	}
    }
    elsif( $match eq 'begins' )
    {
	return 1 if $obj =~ /^\Q$val/;
    }
    elsif( $match eq 'like' )
    {
	return 1 if $obj =~ /\Q$val/;
    }
    else
    {
	confess "Matchtype $match not implemented";
    }

    return 0;
}


##############################################################################

=head2 as_string

  $o->as_string

Not used. Please be more specific. What kind of string?

=cut

sub as_string
{
    confess "wrong turn";
}


##############################################################################

=head2 size

=cut

sub size
{
    return 1;
}

##############################################################################

=head2 empty

  $n->empty()

Returns true if this node has no properties.

Returns: 1

=cut

sub empty
{
    return 1;
}

##############################################################################

=head2 get_first

  $o->get_first()

Gets the first value from a list, or the value itselft if it's not a
list.

May return a second value with a error status code if the list is
empty. See L</get_first_nos>.

=cut

sub get_first
{
    return $_[0];
}

##############################################################################

=head2 get_first_nos

  $o->get_first_nos()

Gets the first value from a list, or the value itselft if it's not a
list. Does not return a status code (get first with no status).

=cut

sub get_first_nos
{
    return $_[0];
}

##############################################################################

=head2 uniq

  $o->uniq()

=cut

sub uniq
{
    return $_[0];
}

##############################################################################

=head2 sum

  $o->sum()

=cut

sub sum
{
    return $_[0];
}

##############################################################################

=head2 as_list

  $o->as_list()

Returns a referens to a list. Not a List object. The list content are
materialized. Compatible with L<Para::Frame::List/as_list>

=cut

sub as_list
{
    return [$_[0]];
}

##############################################################################

=head2 flatten

  $o->flatten()

=cut

sub flatten
{
    return $_[0]->list_class->new([$_[0]]);
}

##############################################################################

=head2 as_listobj

  $o->as_listobj()

Returns a L<RDF::Base::List>

=cut

sub as_listobj
{
    return $_[0]->list_class->new([$_[0]]);
}

#########################################################################

=head2 list_class

  $class->list_class

This will return which subclass of L<RDF::Base::List> to use for lits
of nodes blessed into this class.

Example:

  $pred->valtype->instance_class->list_class->new(\@nodes)

=cut

sub list_class
{
    return "RDF::Base::List";
}


##############################################################################

=head2 as_array

  $literal->as_array()

=cut

sub as_array
{
    return( $_[0] );
}

##############################################################################

=head2 as_arrayref

  $literal->as_arrayref()

=cut

sub as_arrayref
{
    return( [$_[0]] );
}

##############################################################################

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

##############################################################################

=head2 this_coltype

Returns: The coltype of the node

Must be implemented in a subclass

=cut

sub this_coltype
{
    confess "Not implemented";
}


##############################################################################

=head2 meets_proplim

  $obj->meets_proplim( $proplim, \%args )

Implements ne and exist => 0, otherwise false if proplim is defined
and has content.  This is re-implemented for L<RDF::Base::Resource>.

TODO: Generalize this

=cut

sub meets_proplim
{
    # Some quickening...
    return 1 unless $_[1];
    return 1 unless keys %{$_[1]};

    # Real checks; only matchtypes ne & exist can get through
    my $node = shift;
    my $proplim = shift;
    foreach my $pred_part ( keys %$proplim )
    {
	my $target_value =  $proplim->{$pred_part};

	#                      Regexp compiles once
	unless( $pred_part =~ m/^(rev_)?(\w+?)(?:_(@{[join '|', keys %RDF::Base::Arc::LIM]}))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/xo )
	{
	    $Para::Frame::REQ->result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	    unless( $pred_part )
	    {
		if( debug )
		{
		    debug "No pred_part?";
		    debug "Template: ".query_desig($proplim);
		    debug "For node ".$node->sysdesig;
		}
	    }
	    die "wrong format in object find: $pred_part\n";
	}

	my $rev    = $1;
#	my $pred   = $2;
#	my $arclim = $3 || $arclim_in;
#	my $clean  = $4 || $args_in->{'clean'} || 0;
	my $match  = $5 || 'eq';
#	my $prio   = $6; #not used

	return 0
	  if $rev;  # Not implemented at this level...

	if( $match eq 'ne' )
	{
	    next;
	}
	elsif( $match eq 'exist' )
	{
	    next
	      unless( $target_value );
	}

	# This node failed the test
	return 0;
    }

    # All properties good
    return 1;
}


##############################################################################

=head2 has_value

  $literal->has_value( ... )

Returns: false

=cut

sub has_value
{
    return RDF::Base::Undef->new();
}


########################################################################

=head2 sorted

  $n->sorted

This is not a list. Just give back the object!

Returns:

C<$n>

=cut

sub sorted
{
    return $_[0];
}


##############################################################################

=head2 has_pred

  $literal->has_pred( ... )

Returns: false

=cut

sub has_pred
{
    return RDF::Base::Undef->new();
}


##############################################################################

=head2 contains_any_of

  $obj->contains_any_of( $node, \%args )

  $obj->contains_any_of( $list, \%args )

See L<RDF::Base::List::contains_any_of>

Only checks this single object.

=cut

sub contains_any_of
{
    my( $obj, $tmpl, $args ) = @_;

    if( ref $tmpl )
    {
	if( ref $tmpl eq 'RDF::Base::List' )
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

##############################################################################

=head2 sort_arg

  $obj->sort_arg

Returns: an array ref of sortargs for the latest sorting on for the item

=cut

sub sort_arg
{
    return $_[0]->{'sort_arg'} || [];
}


##############################################################################

=head2 random

  $obj->random

Stores the number in memory until next reset. The point of this is to
keep the given order between reordering and page flipping of search
results.

Returns: an random number between 1 and 99

=cut

sub random
{
    $_[0]->{'random'} ||= int(rand(99)+1);
}


##############################################################################

=head2 per_node

  $obj->per_node( \%props, \%args )

Calls methods on nodes given by id. Example:

  $obj->per_node( { 123 => { add => { is => 124 } } }, \%args )

This will get node with id 123 and call
   $node->add( { is => 124 }, $args );

Returns: true if all methods returned true

=cut

sub per_node
{
    my( $obj, $props, $args ) = @_;

    my $res = 1;

    debug "per_node";

    foreach my $node_id ( keys %$props )
    {
	debug "  $node_id";
	my $node = RDF::Base::Resource->get( $node_id, $args );
	foreach my $meth ( keys %{$props->{$node_id}} )
	{
	    debug "    $meth";
	    my $respart = $node->$meth( $props->{$node_id}{$meth}, $args );
	    unless( $respart )
	    {
		$res = 0;
	    }
	}
    }

    return $res;
}


######################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Node>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
