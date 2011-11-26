package RDF::Base::Literal;
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

RDF::Base::Literal

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Node );
use overload
  '""'   => 'literal',
  fallback => 1,
  ;

use Carp qw( cluck confess carp croak shortmess longmess );
use Scalar::Util qw( refaddr blessed );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Widget qw( label_from_params );

use RDF::Base::Resource::Literal;
use RDF::Base::Literal::String;
use RDF::Base::Literal::Time;
use RDF::Base::Literal::URL;
use RDF::Base::Literal::Email::Address;
use RDF::Base::Arc::Lim;
use RDF::Base::Pred;
use RDF::Base::List;

use RDF::Base::Utils qw( is_undef valclean truncstring parse_propargs
                         convert_query_prop_for_creation query_desig );


=head1 DESCRIPTION

Represents a Literal.

A literal can only exist in one arc.

L<RDF::Base::Literal::String>, L<RDF::Base::Literal::Time> and L<RDF::Base::Undef> are
Literals.

Inherits from L<RDF::Base::Object>.


The standard XML schema datatypes are described in
http://www.w3.org/TR/xmlschema11-2/#built-in-datatypes


Supported args:

  subj_new
  pred_new
  coltype
  valtype


=head2 notes

121[122] 123 -name-> [124]"Apa"
125[126] 124 -is_of_language-> sv
127[122] 123 -name-> [124]"Bepa"

"Apa" isa RDF::Base::Literal
[124] isa RDF::Base::Resource::Literal

$nlit = $R->get(124);
$lit = $nlit->value('active');
$nlit = $lit->node;
print $lit->plain; # Bepa

=cut


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any List object.

=cut

##############################################################################

=head2 new

  $class->new( \$val, $valtype )

Implement in subclasses!

Identifies the format and makes the apropriate literal object of it.

=cut

sub new
{
    my( $this, $val_in, $valtype_in ) = @_;

    unless( $valtype_in )
    {
	confess "valtype missing";
    }

    my $valtype = RDF::Base::Resource->get($valtype_in);
    unless( $valtype->UNIVERSAL::isa('RDF::Base::Literal::Class') )
    {
	my $valtype_desig = $valtype->desig;
	confess "valtype $valtype_desig is not a literal class";
    }

    my $class_name = $valtype->instance_class;

    return $class_name->new( $val_in, $valtype );
}


##############################################################################

=head2 new_from_db

  $this->new_from_db( $value, $valtype)

=cut

sub new_from_db
{
    my( $this, $val_in, $valtype ) = @_;

    # This should reset the node based on the DB content. But the
    # content is dependant of the arc. An init of the arc will call
    # this with the new data. We will never drop the C<arc>
    # connection.
    #
    # An init without C<$valtype> will use the C<arc> if
    # existing. If not, it will keep existing data.


    unless( $valtype )
    {
 	confess "valtype missing";
    }

    unless( $valtype->UNIVERSAL::isa('RDF::Base::Literal::Class') )
    {
	my $valtype_desig = $valtype->desig;
	confess "valtype $valtype_desig is not a literal class";
    }

    my $class_name = $valtype->instance_class;

    return $class_name->new_from_db( $val_in, $valtype );
}


##############################################################################

=head2 get_by_arc_rec

  $n->get_by_arc_rec( $rec, $valtype )

This will B<allways> re-init the literal object. It will usually be
called from the arc holding the literal. The init or reinit of the arc
should also reinit the literal. Thus, we will find the literal in the
cache, but init with the rec, even if found.

Returns: a literal

Exceptions: see L</init>.

=cut

sub get_by_arc_rec
{
    my( $this, $rec, $valtype ) = @_;
    my $coltype = $valtype->coltype;
    return $this->new_from_db($rec->{$coltype}, $valtype, $rec->{'ver'});
}


#########################################################################

=head2 reset_cache

  $node->reset_cache()

Does nothing here...

=cut

sub reset_cache
{
    return $_[0];
}


##############################################################################

=head2 parse

=cut

sub parse
{
    my( $this, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $this->extract_string($val_in, $args_in);

    my $class_name = $valtype->instance_class;

    return $class_name->new( $val_in, $valtype );
}


##############################################################################

=head2 as_list

Returns value as L<RDF::Base::List>

=cut

sub as_list
{
    # Used by List AUTOLOAD

    return RDF::Base::List->new([shift]);
}

##############################################################################

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
	return RDF::Base::List->new([shift]);
    }
}

##############################################################################

=head2 lit_revarc

  $literal->lit_revarc

Return the arc this literal is a part of.

See also: L</arc> and L</revarc>

=cut

sub lit_revarc
{
    # Try to handle arc list method calls on return value...
    return($_[0]->{'arc'} || RDF::Base::Arc::List->new_empty());
}


##############################################################################

=head2 is_true

See L</RDF::Base::Object/is_true>

Should this theck the truthiness of the plain value?

Returns: 1 if plain value is true in perl boolean context

=cut

sub is_true
{
    return $_[0]->plain ? 1 : 0;
}


##############################################################################

=head2 is_literal

See L</RDF::Base::Object/is_literal>

=cut

sub is_literal
{
    return 1;
}


##############################################################################

=head2 node

  $lit->node

=cut

sub node
{
    return( $_[0]->{'node'} ||= $_[0]->{'arc'} ?
	    $_[0]->{'arc'}->value_node : is_undef );
}


##############################################################################

=head2 set_arc

  $lit->set_arc( $arc )

Bind Literal to arc.

=cut

sub set_arc
{
    my( $lit, $arc ) = @_;

    $lit->{'arc'} = $arc;
    $lit->{'node'} = undef;
    # Called from RDF::Base::Arc/register_with_nodes

    return $arc;
}


##############################################################################

=head2 node_set

  $lit->node_set

  $lit->node_set( $node )

Will create a node if not existing

Exceptions: If trying to explicitly set a node on a literal belonging
to an arc

Returns: the node

=cut

sub node_set
{
    if( not($_[0]->{'node'}) or $_[1] )
    {
#	debug "  setting vnode";
	my( $lit, $node ) = @_;
	if( my $arc = $lit->{'arc'} )
	{
	    if( $node )
	    {
		if( my $old_node = $arc->value_node )
		{
		    if( $old_node->equals($node) )
		    {
#			debug "  no change in value_node";
			# No change...
			return $old_node;
		    }
		    confess "Can't set node for lit belonging to an arc: ".
		      $lit->sysdesig;
		}

		confess "CHECKME: ".$lit->sysdesig." / ".$arc->sysdesig;
	    }

	    if( $node = $arc->value_node )
	    {
#		debug "  set by arc value_node";
		$lit->{'node'} = $node;
	    }
	    else
	    {
#		debug "  set to new value_node for arc";
		$lit->{'node'} = $arc->set_value_node();
	    }
	}
	elsif( $node )
	{
#	    debug "  set to given value";
	    $lit->{'node'} = $node;
	}
	else
	{
#	    debug "  Creating a new value_node for literal";
	    $lit->{'node'} = RDF::Base::Resource::Literal->get('new');
	}
    }
#    else
#    {
#	debug "vnode initialized and no new vnode given (@_)";
#    }

    return $_[0]->{'node'};
}


#########################################################################
################################  Public methods  #######################

=head2 equals

  $literal->equals( $val )

If C<$val> is a scalar, converts it to a L<RDF::Base::Literal::String>
object. (Undefs will become a L<RDF::Base::Undef> via
L<RDF::Base::Literal::String>.)

Returns true if both are L<RDF::Base::Literal> and has the same
L<RDF::Base::Object/syskey>.

C<syskey> is implemented in the subclasses to this class. For example,
L<RDF::Base::Literal::String>, L<RDF::Base::Literal::Time> and L<RDF::Base::Undef>.

=cut

sub equals
{
    my( $lit, $val, $args ) = @_;

    $val = RDF::Base::Literal::String->new($val)
      unless( ref $val );

    if( ref $val and UNIVERSAL::isa($val, 'RDF::Base::Literal') )
    {
	if( $lit->syskey($args) eq $val->syskey($args) )
	{
	    if( my $lit_id = $lit->id )
	    {
		if( $val->id and ($lit_id == $val->id) )
		{
		    return 1;
		}
		# Values equals. But diffrent value nodes
		return 0;
	    }
	    elsif( $val->id )
	    {
		# Values equals. But diffrent value nodes
		return 0;
	    }

	    return 1;
	}
    }

    return 0;
}


##############################################################################

=head2 update

The API is the same as for L<RDF::Base::Resource/update>.

The prop C<value> will update the literal. If the literal is not bound
to an arc, it may be updated to any type of literal or resource.

Supported args are teh same as for
L<RDF::Base::Resource/find_by_anything>.

Returns:

  The value node created for representing the literal

Example:

  $node->name->update({ is_of_language => $C_swedish });

=cut

sub update
{
    my( $lit, $props, $args ) = @_;

    # Just convert to value node and forward the call.
    # But check if we realy have props to add

    debug "Update in literal ".$lit->sysdesig ." ".refaddr($lit);
    debug query_desig($props);
#    debug "With args ".query_desig($args);
#    cluck "GOT HERE";
#    debug "---";

    if( my $new_val = $props->{'value'} )
    {
	delete $props->{'value'};
	if( my $arc = $lit->lit_revarc )
	{
	    my $newarc = $arc->set_value($new_val, $args );
	    $lit = $newarc->value;
	}
	else
	{
	    $lit = RDF::Base::Resource->get_by_anything($new_val, $args);
	}

	$lit->update($props, $args);
    }
    elsif( %$props ) # not if empty
    {
	my $node = $lit->node_set;
	debug "Getting value node ".$node->sysdesig;
	$node->update($props, $args);

#	$lit->node_set->update($props, $args);
    }

    return $lit;
}


##############################################################################

=head3 this_valtype

  $lit->this_valtype()

This is like the C<is> property for literals. Defaults to
L</default_valtype>.

See also: L<RDF::Base::Resource/this_valtype>

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

##############################################################################

=head3 this_valtype_reset

  $lit->this_valtype_reset()

For re-evaluating the valtype of the literal. This does nothing, since
we needs to keep the given valtype. But the Resource equivalent does a
re-evaluation.

Returns: -

See also: L<RDF::Base::Resource/this_valtype_reset>

=cut

sub this_valtype_reset
{
    return;
}

##############################################################################

=head3 this_coltype

  $lit->this_coltype()

This gives the coltype of the value of this literal.

returns: the plain string of table column name

See also: L<RDF::Base::Resource/this_coltype>

=cut

sub this_coltype
{
    return $_[0]->this_valtype->coltype;
}

##############################################################################

=head3 subj

  $this->subj( \%args )

Get existing or planned subj

Supported args are:

  arc
  subj_new

=cut

sub subj
{
    my( $this, $args_in ) = @_;

    if( ref $this )
    {
	my $lit = $this;
	if( my $arc = $lit->lit_revarc )
	{
	    return $arc->subj;
	}
    }

    my( $args ) = parse_propargs($args_in);
    if( my $arc = $args->{'arc'} )
    {
	return $arc->subj;
    }

    return $args->{'subj_new'} || is_undef;
}

##############################################################################

=head3 pred

  $this->pred( \%args )

Get existing or planned pred

Supported args are:

  arc
  pred_new

=cut

sub pred
{
    my( $this, $args_in ) = @_;

    if( ref $this )
    {
	my $lit = $this;
	if( my $arc = $lit->lit_revarc )
	{
	    return $arc->pred;
	}
    }

    my( $args ) = parse_propargs($args_in);
    if( my $arc = $args->{'arc'} )
    {
	return $arc->pred;
    }

    return $args->{'pred_new'} || is_undef;
}

##############################################################################

=head2 extract_string

  $class->extract_string( \$val, \%args )

For use in L</parse> methods.

Supported args are:
  valtype
  coltype
  arclim

Thre C<$retval> will either be a scalar ref of the plain value to
parse, or a L<RDF::Base::Literal> object.

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
    elsif( UNIVERSAL::isa $val, "RDF::Base::Literal" )
    {
	# Validate below
    }
    elsif( (ref $val eq 'HASH') or
	   (ref $val eq 'ARRAY') or
	   (UNIVERSAL::isa $val, "Para::Frame::List")
	 )
    {
	$val = RDF::Base::Resource->get_by_anything( $val,
						     {
						      %$args,
						      valtype => $valtype,
						     });
	return( $val, $coltype, $valtype, $args );
    }
    elsif( UNIVERSAL::isa $val, "RDF::Base::Resource::Literal" )
    {
#	debug "Val isa Res Lit: ".$val->id;
#	debug "Using args:\n".query_desig($args);

	# Sort by id in order to use the original arc as a base of
	# reference for the value, in case that other arc points to
	# the same node.

	my $node = $val;
	$val = $node->first_literal();

#	debug "  Extracted ".$val->sysdesig;
	unless( UNIVERSAL::isa $val, "RDF::Base::Literal" )
	{
	    debug "First literal of node is a ".ref($val);
	    throw('validation', $node->id." is not a literal resource");
	}
    }
    elsif( UNIVERSAL::isa $val, "RDF::Base::Undef" )
    {
	return( \ undef, $coltype, $valtype, $args );
    }
    else
    {
	confess "Can't parse $val";
    }

    # TODO: check for compatible valtype

    return( $val, $coltype, $valtype, $args );

}


##############################################################################

=head3 id

Returns: the node id

=cut

sub id
{
    $_[0]->node->id;
}


#########################################################################
#########################  Value resource methods  ######################

=head3 find

=cut

sub find
{
    return shift->node->find(@_);
}


##############################################################################

=head3 find_one

=cut

sub find_one
{
    return shift->node->find_one(@_);
}


##############################################################################

=head3 find_set

=cut

sub find_set
{
    my( $lit ) = shift;
    blessed $lit or confess "Not a class method";
    return $lit->node_set->find_set(@_);
}


##############################################################################

=head3 set_one

=cut

sub set_one
{
    my( $lit ) = shift;
    blessed $lit or confess "Not a class method";
    return $lit->node_set->set_one(@_);
}


##############################################################################

=head3 form_url

=cut

sub form_url
{
    my( $lit ) = shift;

    if( my $subj = $lit->subj )
    {
	return $subj->form_url(@_);
    }
    else
    {
	confess "fixme";
    }
}


##############################################################################

=head3 page_url_path_slash

=cut

sub page_url_path_slash
{
    my( $lit ) = shift;

    if( my $subj = $lit->subj )
    {
	return $subj->page_url_path_slash(@_);
    }
    else
    {
	confess "fixme";
    }
}


##############################################################################

=head3 empty

  $n->empty()

Returns true if the literal node has no properties.

Returns true if the literal is not coupled to a node.

Returns: boolean

=cut

sub empty
{
    return $_[0]->node->empty;
}


##############################################################################

=head3 created

=cut

sub created
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->created;
    }

    cluck "FIXME";

    return RDF::Base::Literal::Time->new();
}


##############################################################################

=head3 updated

=cut

sub updated
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->updated;
    }

    cluck "FIXME";

    return RDF::Base::Literal::Time->new();
}


##############################################################################

=head3 owned_by

=cut

sub owned_by
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->subj->owned_by;
    }

    return is_undef;
}


##############################################################################

=head3 read_access

=cut

sub read_access
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->read_access;
    }

    return is_undef;
}


##############################################################################

=head3 write_access

=cut

sub write_access
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->write_access;
    }

    return is_undef;
}


##############################################################################

=head3 created_by

=cut

sub created_by
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->created_by;
    }

    return is_undef;
}


##############################################################################

=head3 updated_by

=cut

sub updated_by
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->updated_by;
    }

    return is_undef;
}


##############################################################################

=head3 list

=cut

sub list
{
    my( $lit, $pred_in, $proplim, $args_in ) = @_;
    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'RDF::Base::Pred') )
	{
	    $pred = $pred_in;
	}
	else
	{
	    $pred = RDF::Base::Pred->get($pred_in);
	}
	$name = $pred->plain;

	unless( $name eq 'value' )
	{
	    return $lit->node->list($pred, $proplim, $args_in);
	}

	my $node = $lit->node;
	unless( $node )
	{
	    return RDF::Base::List->new_empty();
	}


	my( $args, $arclim ) = parse_propargs($args_in);
	unless( RDF::Base::Arc::Lim::literal_meets_lim($lit, $arclim ) )
	{
	    return RDF::Base::List->new_empty();
	}

	# Don't call find if proplim is empty
	if( $proplim and (ref $proplim eq 'HASH' ) and not keys %$proplim )
	{
	    undef $proplim;
	}

	if( $proplim ) # May be a value or anything taken by find
	{
	    unless( $node->find($proplim, $args)->size )
	    {
		return RDF::Base::List->new_empty();
	    }
	}

	return $lit;
    }
    else
    {
	return $lit->node->list_preds( $proplim, $args_in );
    }
}


##############################################################################

=head3 list_preds

=cut

sub list_preds
{
    return shift->node->list_preds(@_);
}


##############################################################################

=head3 revlist

=cut

sub revlist
{
    my( $node, $name, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    my $arc = $node->lit_revarc;
    unless( $arc )
    {
	return RDF::Base::List->new_empty();
    }

    if( $name )
    {
 	if( UNIVERSAL::isa($name,'RDF::Base::Pred') )
 	{
 	    $name = $name->plain;
 	}

 	unless( $arc->pred->plain eq $name )
 	{
 	    return RDF::Base::List->new_empty();
 	}

 	unless( $arc->meets_arclim($arclim) )
 	{
 	    return RDF::Base::List->new_empty();
 	}


 	my $vals = RDF::Base::List->new([$arc->subj]);

 	if( $proplim and (ref $proplim eq 'HASH' ) and keys %$proplim )
 	{
 	    $vals = $vals->find($proplim, $args);
 	}

 	return $vals;
    }
    else
    {
 	return $node->revlist_preds( $proplim, $args );
    }
}


##############################################################################

=head3 revlist_preds

=cut

sub revlist_preds
{
    my $arc = $_[0]->lit_revarc;
    unless( $arc )
    {
 	return RDF::Base::Pred::List->new_empty();
    }

    my $pred = $arc->pred;
    return RDF::Base::List->new([$pred]);
}


##############################################################################

=head3 first_prop

=cut

sub first_prop
{
    return shift->node->first_prop(@_);
}


##############################################################################

=head3 first_revprop

=cut

sub first_revprop
{
    return shift->revlist(@_)->get_first_nos;
}


##############################################################################

=head3 has_pred

=cut

sub has_pred
{
    return shift->node->has_pred(@_);
}


##############################################################################

=head3 has_value

=cut

sub has_value
{
    my( $lit, $preds, $args_in ) = @_;
    confess "Not a hashref" unless ref $preds;

    my( $pred_name, $value ) = each( %$preds );

#    debug sprintf "Checking if %s  --%s--> %s", $lit->sysdesig, $pred_name, $value->sysdesig;


    if( $pred_name eq 'is' ) # checking valtype for implicit is arcs
    {
	my $valtype = $lit->this_valtype;
	unless( UNIVERSAL::isa $value, 'RDF::Base::Resource' )
	{
	    $value = RDF::Base::Resource->get($value);
	}

	if( $valtype->equals( $value ) )
	{
#	    debug "  matches valtype";
	    return 1;
	}
	elsif( $valtype->scof( $value ) )
	{
#	    debug "  matches scof of valtype";
	    return 1;
	}
    }

    unless( $pred_name eq 'value' )
    {
	return $lit->node->has_value($preds, $args_in);
    }

    my( $args, $arclim ) = parse_propargs($args_in);

    my $match = $args->{'match'} || 'eq';
    my $clean = $args->{'clean'} || 0;

    my $pred = RDF::Base::Pred->get( $pred_name );

    # Sub query
    if( ref $value eq 'HASH' )
    {
	unless( $match eq 'eq' )
	{
	    confess "subquery not implemented for matchtype $match";
	}
	return 0;
    }

    # $value holds alternative values
    elsif( ref $value eq 'ARRAY' )
    {
	foreach my $val (@$value )
	{
	    my $res = $lit->has_value({$pred_name=>$val},  $args);
	    return $res if $res;
	}
	return 0;
    }

    if( $match eq 'eq' )
    {
	return $lit->equals( $value, $args );
    }

    my $val1 = $lit->plain;
    my $val2 = $value->plain;

    if( $match eq 'begins' )
    {
	return 1 if $val1 =~ /^\Q$val2/;
    }
    elsif( $match eq 'like' )
    {
	return 1 if $val1 =~ /\Q$val2/;
    }
    else
    {
	confess "Matchtype $match not implemented";
    }
}


##############################################################################

=head3 arc_weight

=cut

sub arc_weight
{
    return $_[0]->{'arc'} ? $_[0]->{'arc'}->arc_weight : undef;
}


##############################################################################

=head3 count

=cut

sub count
{
    return shift->node->count(@_);
}


##############################################################################

=head3 revcount

=cut

sub revcount
{
    my( $node, $tmpl, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    my $arc = $node->lit_revarc;
    unless( $arc )
    {
 	return 0;
    }

    if( ref $tmpl and ref $tmpl eq 'HASH' )
    {
 	throw('action',"count( \%tmpl, ... ) not implemented");
    }

    # Only handles pred nodes
    my $pred = RDF::Base::Pred->get_by_label( $tmpl );

    if( $pred->equals( $arc->pred )  )
    {
 	if( $arc->meets_arclim( $arclim ) )
 	{
 	    return 1;
 	}
    }

    return 0;
}


##############################################################################

=head3 label

=cut

sub label
{
    return undef;
}


##############################################################################

=head3 set_label

=cut

sub set_label
{
    confess "Setting a label on a literal is not allowed";
}


##############################################################################

=head3 arc_list

NOTE: May have expected to get the 'value' arc. But we should not
pretend to have one...

=cut

sub arc_list
{
    return shift->node->arc_list(@_);
}


##############################################################################

=head3 revarc_list

=cut

sub revarc_list
{
    my( $node, $name, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    my $arc = $node->lit_revarc;
    unless( $arc )
    {
 	return RDF::Base::Arc::List->new_empty();
    }

    if( $name )
    {
 	if( UNIVERSAL::isa($name,'RDF::Base::Pred') )
 	{
 	    $name = $name->plain;
 	}

 	unless( $name eq $arc->pred->plain )
 	{
 	    return RDF::Base::Arc::List->new_empty();
 	}
    }

    unless( $arc->meets_arclim($arclim) )
    {
 	return RDF::Base::Arc::List->new_empty();
    }

    my $vals = RDF::Base::Arc::List->new([$arc]);

    if( $proplim and (ref $proplim eq 'HASH' ) and keys %$proplim )
    {
 	$vals = $vals->find($proplim, $args);
    }

    return $vals;
}


##############################################################################

=head3 first_arc

=cut

sub first_arc
{
    return shift->node->first_arc(@_);
}


##############################################################################

=head3 first_revarc

=cut

sub first_revarc
{
    return shift->revarc_list(@_)->get_first_nos;
}


##############################################################################

=head3 arc

=cut

sub arc
{
    return shift->node->arc(@_);
}


##############################################################################

=head3 revarc

=cut

sub revarc
{
    return shift->lit_revarc(@_);
}


##############################################################################

=head3 add

=cut

sub add
{
    return shift->node_set->add(@_);
}


##############################################################################

=head3 vacuum

This will vaccum the value but NOT the value node.

Implemented in respective subclass.

Returns: The vacuumed literal

This will be automatically called by L<RDF::Base::Arc/vacuum>

=cut

sub vacuum
{
    return $_[0];
}


##############################################################################

=head3 merge_node

=cut

sub merge_node
{
    confess "merging a literal?!";
}


##############################################################################

=head3 link_paths

=cut

sub link_paths
{
    return [];
}


##############################################################################

=head3 wu

Widget for updating a node

=cut

sub wu
{
    my( $lit, $pred_name, $args_in ) = @_;

    confess "not implemented"
      unless( $pred_name eq 'value' );

    # Widget for updating literal
    return $lit->wul($args_in);
}


##############################################################################

=head3 arcversions

=cut

sub arcversions
{
    return {};
}


##############################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id, if existing.

=cut

sub sysdesig  # The designation of obj, including node id
{
    my( $lit, $args_in ) = @_;

    my $out;

#    debug "Literal is '$lit', a ". ref $lit;
    confess "$lit is not a literal: ". ref $lit
      if $lit eq 'RDF::Base::Literal::String';
    #unless( UNIVERSAL::isa $lit, 'RDF::Base::Literal' );

    if( my $id = $lit->id )
    {
	$out .= "$id: ";
    }

    my $valtypename = $lit->this_valtype->desig;
    $out .= $valtypename . " ";

#    my $classname = ref $lit;
#    $out .= $classname . " ";

    my $plain = $lit->plain;

    if( defined $plain )
    {
	my $value  = truncstring( shift->{'value'} );
	$value =~ s/\n/\\n/g;
	return $out . '"'.$value.'"';
    }
    else
    {
	return $out . "undef";
    }
}


##############################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    croak "No valtype given";
#    return RDF::Base::Literal::Class->get_by_label('valtext');
}


#########################################################################

=head3 wdirc

=cut

sub wdirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;

	debug 2, "String wuirc for $predname";
	debug 2, "$predname class is ". $pred->range->instance_class;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = RDF::Base::Pred->get_by_label($predname);
    }

#    $out .= label_from_params({
#			       label       => $args->{'label'},
#			       tdlabel     => $args->{'tdlabel'},
#			       separator   => $args->{'separator'},
#			       id          => $args->{'id'},
#			       label_class => $args->{'label_class'},
#			      });

    my $arclist = $subj->arc_list($predname, undef, $args);

    while( my $arc = $arclist->get_next_nos )
    {
	$out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
    }

    return $out;
}


#########################################################################

=head3 update_by_query_arc

=cut

sub update_by_query_arc
{
    my( $lit, $props, $args ) = @_;

    my $value = $props->{'value'};
    my $arc = $props->{'arc'};
    my $pred = $props->{'pred'} || $arc->pred;
    my $res = $args->{'res'};

    if( ref $value )
    {
	my $coltype = $pred->coltype;
	die "This must be an object. But coltype is set to $coltype: $value";
    }
    elsif( length $value )
    {
	# Give the valtype of the pred. We want to use the
	# current valtype rather than the previous one that
	# maight not be the same.  ... unless for value
	# nodes. But take care of that in set_value()

	my $valtype = $pred->valtype;
	if( debug > 1 and $valtype->isa('RDF::Base::Literal::Class') )
	{
	    debug "arc is $arc->{id}";
	    debug "valtype is ".$valtype->desig;
	    debug "pred is ".$pred->desig;
	    debug "setting value to $value";
	}

	$arc = $arc->set_value( $value,
				{
				 %$args,
				 valtype => $valtype,
				});
    }
    else
    {
	$res->add_to_deathrow( $arc );
    }

    return $arc;
}


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource::Literal>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
