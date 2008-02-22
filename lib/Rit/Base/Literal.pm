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
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal

=cut

use strict;
use Carp qw( cluck confess carp shortmess longmess );
use Scalar::Util qw( refaddr );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Widget qw( label_from_params );

use Rit::Base::Literal::String;
use Rit::Base::Literal::Time;
use Rit::Base::Literal::URL;
use Rit::Base::Literal::Email::Address;
use Rit::Base::Arc::Lim;
use Rit::Base::Pred;
use Rit::Base::List;

use Rit::Base::Utils qw( is_undef valclean truncstring parse_propargs
                         convert_query_prop_for_creation query_desig );

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


TODO: For handling value resoruces and be clean and consistent we will
have to, for the example String:

  @{"Rit::Base::Metaclass::Literal::Rit::Base::Literal::String::ISA"} =
   ("Rit::Base::String", "Rit::Base::Literal");

And for value resources of String type:

  @{"Rit::Base::Metaclass::Rit::Base::Literal::String::ISA"} =
   ("Rit::Base::String", "Rit::Base::Literal::Resource");

And Rit::Base::Literal::Resource will implement its version of
Rit::Base::Literal and inherit from Rit::Base::Resource


This makes it behave more like other speical classes handled by
L<Rit::Base::Resource/find_class>. And we will bless all valuenodes in
this way and can then access the literal methods and still get the
other properties.

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
    my( $this, $val_in, $valtype_in ) = @_;

    unless( $valtype_in )
    {
	confess "valtype missing";
    }

    my $valtype = Rit::Base::Resource->get($valtype_in);
    unless( $valtype->UNIVERSAL::isa('Rit::Base::Literal::Class') )
    {
	my $valtype_desig = $valtype->desig;
	confess "valtype $valtype_desig is not a literal class";
    }

    my $class_name = $valtype->instance_class;

    return $class_name->new( $val_in, $valtype );
}


#######################################################################

=head2 new_from_db

=cut

sub new_from_db
{
    my( $this, $val_in, $valtype_in ) = @_;

    unless( $valtype_in )
    {
	confess "valtype missing";
    }

    my $valtype = Rit::Base::Resource->get($valtype_in);
    unless( $valtype->UNIVERSAL::isa('Rit::Base::Literal::Class') )
    {
	my $valtype_desig = $valtype->desig;
	confess "valtype $valtype_desig is not a literal class";
    }

    my $class_name = $valtype->instance_class;

    return $class_name->new_from_db( $val_in, $valtype );
}


#######################################################################

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

=head2 lit_revarc

  $literal->lit_revarc

Return the arc this literal is a part of. For value resources, this
will return the value arc.

See also: L</arc> and L</revarc>

=cut

sub lit_revarc
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
#    debug query_desig($props);
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
	    $lit = Rit::Base::Resource->get_by_anything($new_val, $args);
	}

	return $lit->update($props, $args);
    }

    if( keys %$props )
    {
	my $node;
	if( my $id = $lit->{'id'} )
	{
	    # Transform to value resource
	    delete $Rit::Base::Cache::Resource{ $id };
	    $node = Rit::Base::Resource->get( $id );
	}
	else
	{
	    $node =  Rit::Base::Resource->get( 'new' );
	}

	$node->add( $props, $args );

	my $arc = $lit->lit_revarc; # Before updating literal
	if( $arc )
	{
	    debug "Arc for lit is ".$arc->sysdesig;
	}
	else
	{
	    debug "No arc in update";
	}
	my $valtype = $lit->this_valtype;
	Rit::Base::Arc->create({
				subj    => $node,
				pred    => 'value',
				value   => $lit,
				valtype => $valtype,
			       }, $args);

	if( $arc )
	{
	    $arc->set_value( $node, $args );
	}

	return $node;
    }

    return $lit;
}


#######################################################################

=head2 set_arc

  $literal->set_arc( $arc )

Bind Literal to arc.

=cut

sub set_arc
{
    my( $literal, $arc ) = @_;

#    debug "set_arc to $arc->{id} for $literal ".refaddr($literal);
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
	if( my $arc = $lit->lit_revarc )
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
	if( my $arc = $lit->lit_revarc )
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
	if( my $arc = $val->first_arc('value', undef, $args) )
	{
	    $val = $arc->value;

	    # Is arc always set?
	    $val->set_arc($arc) unless $val->{'arc'};
	}
	else
	{
	    throw('validation', "$val->{id} is not a value node");
	}
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Undef" )
    {
	return \ undef;
    }
    else
    {
	confess "Can't parse $val";
    }

    # TODO: check for compatible valtype

    return( $val, $coltype, $valtype, $args );

}


#######################################################################

=head3 id

=cut

sub id
{
    my( $lit ) = @_;
    unless( $lit->{'id'} )
    {
	my $id = $lit->{'id'} = $Rit::dbix->get_nextval('node_seq');
	$Rit::Base::Cache::Resource{ $id } = $lit;
#        debug shortmess "Created Literal id ".$lit->sysdesig;
    }
    return $lit->{'id'};
}


#########################################################################
#########################  Value resource methods  ######################

=head3 find

=cut

sub find
{
    my( $lit, $query, $args_in ) = @_;

    unless( ref $query )
    {
	return Rit::Base::List->new_empty();
    }
    unless( ref $lit )
    {
	return Rit::Base::List->new_empty();
    }
    my( $args ) = parse_propargs($args_in);

    ## Default criterions
    my $default = $args->{'default'} || {};
    foreach my $key ( keys %$default )
    {
	unless( defined $query->{$key} )
	{
	    $query->{$key} = $default->{$key};
	}
    }

    my $list = Rit::Base::List->new([$lit]);
    return $list->find($query, $args);
}


#######################################################################

=head3 find_one

=cut

sub find_one
{
    return shift->find(@_)->get_first_nos;
}


#######################################################################

=head3 find_set

=cut

sub find_set
{
    my( $this, $query, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $nodes = $this->find( $query, $args )->as_arrayref;
    my $node = $nodes->[0];
    unless( $node )
    {
	my $query_new = convert_query_prop_for_creation($query);

	my $default_create = $args->{'default_create'} || {};
	foreach my $pred ( keys %$default_create )
	{
	    unless( defined $query_new->{$pred} )
	    {
		$query_new->{$pred} = $default_create->{$pred};
	    }
	}

	my $default = $args->{'default'} || {};
	foreach my $pred ( keys %$default )
	{
	    unless( defined $query_new->{$pred} )
	    {
		$query_new->{$pred} = $default->{$pred};
	    }
	}

	return $this->create($query_new, $args);
    }

    return $node;
}


#######################################################################

=head3 set_one

=cut

sub set_one
{
    my( $this, $query, $args_in ) = @_;

    my( $args ) = parse_propargs($args_in);

    my $nodes = $this->find( $query, $args );
    my $node = $nodes->get_first_nos;

    while( my $enode = $nodes->get_next_nos )
    {
	confess "not possible";
    }

    unless( $node )
    {
	my $query_new = convert_query_prop_for_creation($query);

	my $default_create = $args->{'default_create'} || {};
	foreach my $pred ( keys %$default_create )
	{
	    unless( defined $query_new->{$pred} )
	    {
		$query_new->{$pred} = $default_create->{$pred};
	    }
	}

	my $default = $args->{'default'} || {};
	foreach my $pred ( keys %$default )
	{
	    unless( defined $query_new->{$pred} )
	    {
		$query_new->{$pred} = $default->{$pred};
	    }
	}

	return $this->create($query_new, $args);
    }

    return $node;
}


#######################################################################

=head3 form_url

=cut

sub form_url
{
    confess "fixme";
}


#######################################################################

=head3 page_url_path_slash

=cut

sub page_url_path_slash
{
    confess "fixme";
}


#######################################################################

=head3 empty

=cut

sub empty
{
    return 1;
}


#######################################################################

=head3 created

=cut

sub created
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->created;
    }

    return Rit::Base::Literal::Time->new();
}


#######################################################################

=head3 updated

=cut

sub updated
{
    if( my $arc = $_[0]->lit_revarc )
    {
	return $arc->updated;
    }

    return Rit::Base::Literal::Time->new();
}


#######################################################################

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


#######################################################################

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


#######################################################################

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


#######################################################################

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


#######################################################################

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


#######################################################################

=head3 list

=cut

sub list
{
    my( $node, $name, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $name )
    {
	if( UNIVERSAL::isa($name,'Rit::Base::Pred') )
	{
	    $name = $name->plain;
	}

	my $target;

	if( $name eq 'value' )
	{
	    $target = $node;
	}
	else
	{
	    return Rit::Base::List->new_empty();
	}

	unless( Rit::Base::Arc::Lim::literal_meets_lim($target, $arclim ) )
	{
	    return Rit::Base::List->new_empty();
	}

	# Don't call find if proplim is empty
	if( $proplim and (ref $proplim eq 'HASH' ) and not keys %$proplim )
	{
	    undef $proplim;
	}

	if( $proplim ) # May be a value or anything taken by find
	{
	    # Proplim may be in negative form, and thus valid

	    $target = $target->find($proplim, $args)->get_first_nos;
	}

	return $target;
    }
    else
    {
	return $node->list_preds( $proplim, $args );
    }
}


#######################################################################

=head3 list_preds

=cut

sub list_preds
{
    my $pred = Rit::Base::Pred->get_by_label('value');
    return Rit::Base::Pred::List->new([$pred]);
}


#######################################################################

=head3 revlist

=cut

sub revlist
{
    my( $node, $name, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    my $arc = $node->lit_revarc;
    unless( $arc )
    {
	return Rit::Base::List->new_empty();
    }

    if( $name )
    {
	if( UNIVERSAL::isa($name,'Rit::Base::Pred') )
	{
	    $name = $name->plain;
	}

	unless( $arc->pred->plain eq $name )
	{
	    return Rit::Base::List->new_empty();
	}

	unless( $arc->meets_arclim($arclim) )
	{
	    return Rit::Base::List->new_empty();
	}


	my $vals = Rit::Base::List->new([$arc->subj]);

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


#######################################################################

=head3 revlist_preds

=cut

sub revlist_preds
{
    my $arc = $_[0]->lit_revarc;
    unless( $arc )
    {
	return Rit::Base::Pred::List->new_empty();
    }

    my $pred = $arc->pred;
    return Rit::Base::List->new([$pred]);
}


#######################################################################

=head3 first_prop

=cut

sub first_prop
{
    return shift->list(@_)->get_first_nos;
}


#######################################################################

=head3 first_revprop

=cut

sub first_revprop
{
    return shift->revlist(@_)->get_first_nos;
}


#######################################################################

=head3 has_pred

=cut

sub has_pred
{
    my( $node ) = shift;

    if( $node->list(@_)->size )
    {
	return $node;
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

=head3 has_value

=cut

sub has_value
{
    my( $node, $preds, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    confess "Not a hashref" unless ref $preds;

    my( $pred_name, $value ) = each( %$preds );

    my $match = $args->{'match'} || 'eq';
    my $clean = $args->{'clean'} || 0;

    my $pred = Rit::Base::Pred->get( $pred_name );
    $pred_name = $pred->plain;


    # Sub query
    if( ref $value eq 'HASH' )
    {
	unless( $match eq 'eq' )
	{
	    confess "subquery not implemented for matchtype $match";
	}

	if( $node->find($value, $args)->size )
	{
	    return 1;
	}
	return 0;
    }

    # $value holds alternative values
    elsif( ref $value eq 'ARRAY' )
    {
	foreach my $val (@$value )
	{
	    my $res = $node->has_value({$pred_name=>$val},  $args);
	    return $res if $res;
	}
	return 0;
    }


    # Check the dynamic properties (methods) for the node
    if( $node->can($pred_name) )
    {
	debug 3, "  check method $pred_name";
	my $prop_value = $node->$pred_name( {}, $args );

	if( ref $prop_value )
	{
	    $prop_value = $prop_value->desig;
	}

	if( $clean )
	{
	    $prop_value = valclean(\$prop_value);
	    $value = valclean(\$value);
	}

	if( $match eq 'eq' )
	{
	    return -1 if $prop_value eq $value;
	}
	elsif( $match eq 'begins' )
	{
	    return -1 if $prop_value =~ /^\Q$value/;
	}
	elsif( $match eq 'like' )
	{
	    return -1 if $prop_value =~ /\Q$value/;
	}
	else
	{
	    confess "Matchtype $match not implemented";
	}
    }


    if( $pred_name eq 'value' )
    {
	return $node->equals( $value, $args );
    }

    return 0;
}


#######################################################################

=head3 count

=cut

sub count
{
    my( $node, $tmpl, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( ref $tmpl and ref $tmpl eq 'HASH' )
    {
	throw('action',"count( \%tmpl, ... ) not implemented");
    }

    # Only handles pred nodes
    my $pred_name = Rit::Base::Pred->get_by_label( $tmpl )->plain;

    if( $pred_name eq 'value' )
    {
	if( Rit::Base::Arc::Lim::literal_meets_lim($node, $arclim ) )
	{
	    return 1;
	}
    }

    return 0;
}


#######################################################################

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
    my $pred = Rit::Base::Pred->get_by_label( $tmpl );

    if( $pred->equals( $arc->pred )  )
    {
	if( $arc->meets_arclim( $arclim ) )
	{
	    return 1;
	}
    }

    return 0;
}


#######################################################################

=head3 label

=cut

sub label
{
    return undef;
}


#######################################################################

=head3 set_label

=cut

sub set_label
{
    confess "Setting a label on a literal is not allowed";
}


#######################################################################

=head3 arc_list

NOTE: May have expected to get the 'value' arc. But we should not
pretend to have one...

=cut

sub arc_list
{
    return Rit::Base::Arc::List->new_empty();
}


#######################################################################

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
	return Rit::Base::Arc::List->new_empty();
    }

    if( $name )
    {
	if( UNIVERSAL::isa($name,'Rit::Base::Pred') )
	{
	    $name = $name->plain;
	}

	unless( $name eq $arc->pred->plain )
	{
	    return Rit::Base::Arc::List->new_empty();
	}
    }

    unless( $arc->meets_arclim($arclim) )
    {
	return Rit::Base::Arc::List->new_empty();
    }

    my $vals = Rit::Base::Arc::List->new([$arc]);

    if( $proplim and (ref $proplim eq 'HASH' ) and keys %$proplim )
    {
	$vals = $vals->find($proplim, $args);
    }

    return $vals;
}


#######################################################################

=head3 first_arc

=cut

sub first_arc
{
    return Rit::Base::Arc::List->new_empty();
}


#######################################################################

=head3 first_revarc

=cut

sub first_revarc
{
    return shift->revarc_list(@_)->get_first_nos;
}


#######################################################################

=head3 arc

=cut

sub arc
{
    return is_undef;
}


#######################################################################

=head3 revarc

=cut

sub revarc
{
    return shift->lit_revarc(@_);
}


#######################################################################

=head3 add

=cut

sub add
{
    return shift->update(@_);
}


#######################################################################

=head3 vacuum

=cut

sub vacuum
{
    if( my $arc = $_[0]->lit_revarc )
    {
	$arc->vacuum;
    }
    return $_[0];
}


#######################################################################

=head3 merge_node

=cut

sub merge_node
{
    confess "merging a literal?!";
}


#######################################################################

=head3 link_paths

=cut

sub link_paths
{
    return [];
}


#######################################################################

=head3 wu

=cut

sub wu
{
    my( $lit, $pred_name, $args_in ) = @_;
    my( $args_parsed ) = parse_propargs($args_in);
    my $args = {%$args_parsed}; # Shallow clone

    confess "not implemented"
      unless( $pred_name eq 'value' );

    my $pred = Rit::Base::Pred->get_by_label($pred_name);

    return $lit->wuirc( $lit, $pred, $args );
}


#######################################################################

=head3 arcversions

=cut

sub arcversions
{
    return {};
}


#######################################################################

=head3 tree_select_widget

=cut

sub tree_select_widget
{
    return "";
}


#######################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id, if existing.

=cut

sub sysdesig  # The designation of obj, including node id
{
    my( $lit, $args_in ) = @_;

    my $out;

    debug "Literal is '$lit', a ". ref $lit;
    confess "$lit is not a literal: ". ref $lit
      if $lit eq 'Rit::Base::Literal::String';
    #unless( UNIVERSAL::isa $lit, 'Rit::Base::Literal' );

    if( my $id = $lit->{'id'} )
    {
	$out .= "$id: ";
    }

    my $classname = ref $lit;

    $out .= $classname . " ";

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


#######################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    die "No valtype given";
#    return Rit::Base::Literal::Class->get_by_label('valtext');
}

#########################################################################

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
	$pred = Rit::Base::Pred->get_by_label($predname);
    }

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    my $arclist = $subj->arc_list($predname, undef, $args);

    while( my $arc = $arclist->get_next_nos )
    {
	$out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
    }

    return $out;
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
