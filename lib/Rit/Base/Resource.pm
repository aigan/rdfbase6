#  $Id$  -*-cperl-*-
package Rit::Base::Resource;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource class
#
# AUTHOR
#   Jonas Liljegren <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Resource

=cut

use strict;
use utf8;

use Carp qw( cluck confess croak carp shortmess );
use vars qw($AUTOLOAD);
use Time::HiRes qw( time );
use LWP::Simple (); # Do not import get
use Template::PopupTreeSelect 0.9;
use JSON; # objToJson jsonToObj


BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Code::Class;
use Para::Frame::Utils qw( throw catch create_file trim debug datadump
			   package_to_module );

use Rit::Base::Node;
use Rit::Base::Search;
use Rit::Base::List;
use Rit::Base::Arc::List;
use Rit::Base::Arc;
use Rit::Base::Literal::Class;
use Rit::Base::Literal;
use Rit::Base::Literal::Time qw( now );
use Rit::Base::Literal::String;
use Rit::Base::Pred;
use Rit::Base::Pred::List;
use Rit::Base::Metaclass;
use Rit::Base::Resource::Change;
use Rit::Base::Arc::Lim;
use Rit::Base::Widget;
use Rit::Base::Widget::Handler;

use Rit::Base::Constants qw( $C_language $C_valtext $C_valdate
                             $C_class $C_literal_class $C_resource );

use Rit::Base::Utils qw( valclean translate parse_query_props
			 parse_form_field_prop is_undef arc_lock
			 arc_unlock truncstring query_desig
			 convert_query_prop_for_creation
			 parse_propargs aais );

our %UNSAVED;

### Inherit
#
use base qw( Rit::Base::Node );

=head1 DESCRIPTION

Most things is represented by resources.  Resources can have
properties.  Each property is represented by an arc that connects the
resource with another resource or a literal.

L<Rit::Base::Arc>s and L<Rit::Base::Pred>s are special resources.
L<Rit::Base::List>s are objects but not resources.  are not yet
considered nodes.

Inherits from L<Rit::Base::Node>.

=cut



#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any node object.

=cut


#######################################################################

=head2 get

  $n->get( $id, \%args )

  $n->get( $anything, \%args )

get() is the central method for getting things.  It expects node id,
but also takes labels and searches.  It will call L</new> and
L</init>.  Anything other than id is given to L</get_by_anything>.  Those
methods are reimplemented in the subclasses.  L</new> must only take
the node id.  L</get_by_anything> must take any form of identification,
but expects and returns only ONE node.  The coresponding
L</find_by_anything> returns a List.

You should call get() through the right class.  If not, it will look
up the right class and bless itself into that class, and call thats
class L</init>.

The global variable C<%Rit::Base::LOOKUP_CLASS_FOR> can be modified
(during startup) for setting which classes it should lookup the class
for. This is initiated to:

  Rit::Base::Resource   => 1,
  Rit::Base::User::Meta => 1,

NB! If you call get() from a class other than these, you must make
sure that the object will never also be of another class.

Supported args are:

  initiate_rel: initiates all rel arcs BEFORE L</first_bless>

Returns:

a node object

If called with undef value, returns undef without exception

Exceptions:

See L</get_by_anything> then called with anything but $id

=cut

sub get
{
    my( $this, $val_in, $args_in ) = @_;
    my $class = ref($this) || $this;

    return undef unless $val_in;
    my $node;
    my $id;

#    debug "Getting $val_in ($class)";

    # Get the resource id
    #
    if( $val_in !~ /^\d+$/ )
    {
	if( ref $val_in and UNIVERSAL::isa($val_in, 'Rit::Base::Resource') )
	{
	    # This already is a (node?) obj
#	    debug "Got     $id";
	    return $val_in;
	}

	if( $val_in eq 'new' ) # Minimal init for empty node
	{
	    $id = $Rit::dbix->get_nextval('node_seq');
	    $node = $class->new( $id );
	    $node->{'new'} = 1;
	    return $node;
	}


	# $val_in could be a hashref, but those are not chached
	if( my $const = $Rit::Base::Constants::Label{$val_in} )
	{
#	    if( $val_in eq 'range' )
#	    {
#		cluck "Got const $val_in";
#	    }
	    return $const;
	}
	else
	{
	    $node = $class->get_by_anything( $val_in ) or return is_undef;
	    $id = $node->id;

	    # Cache id lookups
	    #
#	    debug "Got $id: Caching node $id: $node";
	    $Rit::Base::Cache::Resource{ $id } = $node;

	    return $node;
	}
    }
    else
    {
	$id = $val_in;
    }

#    debug sprintf "id=%s (%s)", $id, ref($id);

    # Is the resource cached?
    #
    $node = $Rit::Base::Cache::Resource{ $id };
    if( defined $node ) # May be literal with 'false' value
    {
#	debug "Got     $id from Resource cache: ".($node||'<undef>');
	return $node;
    }

    $node = $class->new( $id );
    # The node will be cached by the new()

    $args_in ||= {};
    if( $args_in->{'initiate_rel'} ) # Optimization
    {
	$node->initiate_rel;
    }

    $node->first_bless;

#    debug "Got     $id ($node)";

    return $node;
}


#######################################################################

=head2 get_by_node_rec

  $n->get_by_node_rec( $rec, @extra )

Returns: a node

Exceptions: see L</init>.

=cut

sub get_by_node_rec
{
    my( $this, $rec ) = @_;

    my $id = $rec->{'node'} or
      confess "get_by_node_rec misses the node param: ".datadump($rec,2);

    return $Rit::Base::Cache::Resource{$id} ||
      $this->new($id)->first_bless($rec);
}


#######################################################################

=head2 get_by_id

  $n->get_by_id( $id )

Returns:

Returns a Arc or Resource object

=cut

sub get_by_id
{
    my( $this, $id ) = @_;

    return $this->get( $id ); # Now handles all types
}


#######################################################################

=head2 find_by_anything

  1. $n->find_by_anything( $node, \%args )

  2. $n->find_by_anything( $query, \%args )

  3. $n->find_by_anything( $list );

  4. $n->find_by_anything( $string, {%args, coltype=>$coltype} );

  5. $n->find_by_anything( "$any_name ($props)", \%args )

  6. $n->find_by_anything( "$called ($predname)", \%args )

  7. $n->find_by_anything( "$id: $name", \%args )

  8. $n->find_by_anything( "#$id", \%args )

  9. $n->find_by_anything();

 10. $n->find_by_anything( $label, \%args );

 11. $n->find_by_anything( $name, \%args );

 12. $n->find_by_anything( $id, \%args );

C<$node> is a node object.

C<$query> is defined in L</find>.

A C<$list> returns itself.

In case C<4>, the coltype is given in the arg. It will return objects
of type L<Rit::Base::Literal>.  Objects will be returned
unchanged. Strings will be parsed for object creation.  Especially
handles C<valtext>, C<valfloat> and C<valdate>.

In case C<5>, C<$any_name> is either name, name_short or code, with
C<clean>.  C<$props> is a list of criterions of the form "pred value"
spearated by comma, there the value is everything after the first
space and before the next comma or end of string. Example: "Jonas (is
person)".

In case C<6>, we can identify a node by the predicate of our choosing.
The node must have a property C<$predname> with value C<$called>.
Example: "123 (code)".

Case C<7> expects the node id followed by the node designation.

Case C<8> is just for givin the node id following a C<#>.

Case C<9> will result in an empty list.

Case C<10> finds the node by L</get_by_label>

Case C<11> finds nodes by the given name using C<clean>. This is the
last resort for anything that doen't looks like a node id number.

Case C<12> returns the node by the id given.

Whitespace will be trimmed for all searches of existing nodes (usning
L<Para::Frame::Utils/trim>). New Literals will not be trimmed. The
caller will have to trime surrounding whitespace, if needed.


Supported args are
  valtype
  arclim

Returns:

a list of zero or more node objects

Exceptions:

validation : C<"$id: $name"> mismatch

See also L</find> if C<$query> or C<$props> is used.

=cut

sub find_by_anything
{
    my( $this, $val, $args_in ) = @_;
    return is_undef unless defined $val;

    my( $args, $arclim, $res ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(3);

#    debug "fins args:\n".query_desig($args); ### DEBUG

    my( @new );
    my $valtype = $args->{'valtype'};

    $valtype ||= Rit::Base::Resource->get_by_label('resource');
    my $coltype = $valtype->coltype;


    # For arcs pointing to valuenodes: The coltype would be 'obj' and
    # the valtype would be the value of the value property.



    if( debug > 1 )
    {
	debug "find_by_anything: $val ($coltype)";
	if( $valtype )
	{
	    debug "  valtype ".$valtype->sysdesig;
	}
    }

    # 1. obj as object
    #
    if( ref $val and UNIVERSAL::isa( $val, 'Rit::Base::Resource') )
    {
	debug 3, "  obj as object";
	push @new, $val;
    }
    #
    # 2. obj as subquery
    #
    elsif( ref $val and ref $val eq 'HASH' )
    {
	debug 3, "  obj as subquery";
	debug "    query: ".query_desig($val) if debug > 3;
	my $objs = $this->find($val, $args);
	unless( $objs->size )
	{
	    return is_undef;
	}

	push @new, $objs->as_array;
    }
    #
    # 3. obj is not an obj.  Looking at coltype
    #
    elsif( $coltype ne 'obj' )
    {
	debug 3, "  obj as not an obj, It's a $coltype";

	my( $valref );
	if( ref $val )
	{
	    $valref = $val;
	}
	else
	{
	    $valref ||= \$val;
	}

	$valtype ||= $this->get_by_label( $coltype );

#	debug "Parsing literal using valtype ".$valtype->sysdesig;
#	debug query_desig $valref;

	$val = $valtype->instance_class->parse( $valref,
						{
						 %$args,
						 aclim => 'active',
						}
					      );
	push @new, $val;
    }
    #
    # 4. obj as list
    #
    elsif( ref $val and UNIVERSAL::isa( $val, 'Para::Frame::List') )
    {
	debug 3, "  obj as list";
	foreach my $elem ( $val->as_array )
	{
	    my $subl = $this->find_by_anything($elem);
	    if( my $size = $subl->size )
	    {
		if( $size == 1 )
		{
		    push @new, $subl->get_first_nos;
		}
		else
		{
		    push @new, $subl;
		}
	    }
	}
    }
    elsif( (ref $val) and (ref $val eq 'ARRAY') )
    {
	debug 3, "  obj as list";
	foreach my $elem ( @$val )
	{
	    my $subl = $this->find_by_anything($elem);
	    if( my $size = $subl->size )
	    {
		if( $size == 1 )
		{
		    push @new, $subl->get_first_nos;
		}
		else
		{
		    push @new, $subl;
		}
	    }
	}
    }
    #
    # 5/6. obj as name of obj with criterions
    #
    elsif( $val =~ /^\s*(.*?)\s*\(\s*(.*?)\s*\)\s*$/ )
    {
	debug 3, "  obj as name of obj with criterions";
	my $name = trim($1);
	my $spec = trim($2);
	my $objs;
	if( $spec !~ /\s/ ) # just one word
	{
	    debug 3, "    Finding nodes with $spec = $name";
	    $objs = $this->find({$spec => $name}, $args);
	}
	else
	{
	    my $props = parse_query_props( $spec );
	    $props->{'predor_name_-_code_-_name_short_clean'} = $name;
	    debug "    Constructing props for find: ".query_desig($props)
	      if debug > 3;
	    $objs = $this->find($props, $args);
	}

	unless( $objs->size )
	{
	    croak "No obj with name '$val' found\n";
	    return is_undef;
	}

	push @new, $objs->as_array;
    }
    #
    # 7. obj as obj id and name
    #
    elsif( $val =~ /^\s*(\d+)\s*:\s*(.*?)\s*$/ )
    {
	debug 3, "  obj as obj id and name";
	my $id = trim($1);
	my $name = trim($2);

	my $obj = $this->get( $id );
	my $desig = $obj->desig;
	if( $desig ne $name )
	{
	    # The name could be truncated

	    if( $name =~ s/\.\.\.$// and $name =~ /^$desig/ )
	    {
		debug 3, "    name was truncated";
	    }
	    else
	    {
		confess('validation', "id/name mismatch.\nid $id is called '$desig'");
	    }
	}
	push @new, $obj;
    }
    #
    # 8. obj as obj id with prefix '#'
    #
    elsif( $val =~ /^\s*#(\d+)\s*$/ )
    {
	debug 3, "  obj as obj id with prefix '#'";
	my $id = $1;
	my $obj = $this->get( $id );
	push @new, $obj;
    }
    #
    # 9. no value
    #
    elsif( not length $val )
    {
	# Keep @new empty
    }
    #
    # 10. obj as label of obj or 11. obj as name of obj
    #
    elsif( $val !~ /^\s*\d+\s*$/ )
    {
	debug 3, "  obj as label or name of obj";
	# TODO: Handle empty $val

	trim(\$val);

	eval # May throw exception
	{
#	    debug "Getting $val from const";
	    my $const = $this->get_by_label($val);
	    unless( $const->{'NOT_INITIALIZED'} )
	    {
		@new = ( $const );
	    }
	};

	unless( @new )
	{
	    # Used to use find_simple.  But this is a general find
	    # function and can not assume the simple case
	    @new = $this->find({ name_clean => $val }, $args)->as_array;
	}
    }
    #
    # 12. obj as obj id
    #
    else
    {
	debug 3, "  obj as obj id";
	push @new, $this->get_by_id( trim($val) );
    }

#    warn "  returning @new\n";

    return Rit::Base::List->new(\@new);
}


#######################################################################

=head2 get_id

  $n->get_id( $anything )

Shortcut for C<$n->get($anything)->id>, but caches the result.

Returns:

a scalar integer

Exceptions:

See L</get>.

=cut

sub get_id
{
    my( $this, $label, $args ) = @_;
    my $class = ref($this) || $this;

    return undef unless defined $label;
    if( my $const = $Rit::Base::Constants::Label{$label} )
    {
	return $const->id;
    }

    my $node = $class->get_by_anything( $label, $args ) or return is_undef;
    return $node->id;
}


#######################################################################

=head2 find

  $class->find( $query )

  $node->find( $query )

  $list->find( $query )

  $node->find( $pred => $value )

  $node->find( $name )

  $any->find( $any, \%args )


If called with class, searches all nodes.  Uses
L<Rit::Base::Search/modify>.

If called with $node or $list, searches only among those nodes.  Uses
L<Rit::Base::List/find>.

Those two methods differs but we have tried to make them mostly
equivalent.

A query is a hash ref with the predicate names as keys and their
values as values.  The format supported depends on which of the
methods above that is used.

If the $query isn't a hash, it will make it into a hash either by C<{
$query => $arg2 }> or C<{ name => $query }>, depending on if a second
arg was passed.

Supported args are

  default
  arclim

Examples:

Find all swedish regional offices of the mother company that begins
with the letter 'a'. The variables C<$mother_company> and C<$sweden>
could be anything that you can pass to L</get>, including subqueries,
but especially the actual node objects.

  my $nodes = Rit::Base::Resource->find({
      is => 'organization',
      rev_has_member => $mother_company,
      in_region => $sweden,
      name_begins => 'a'
  });

Returns:

a L<Rit::Base::List> object

Exceptions:

See L</get>, L<Rit::Base::Search/modify> and L<Rit::Base::List/find>.

=cut

sub find
{
    my( $this, $query, $args_in ) = @_;

    # TODO: set priority by number of values of specific type
#    warn timediff("find");

    unless( ref $query )
    {
	$query = { 'name' => $query };
    }

    my( $args_parsed ) = parse_propargs($args_in);
    my $args = {%$args_parsed}; # Shallow clone

    ## Default criterions
    my $default = $args->{'default'} || {};
    foreach my $key ( keys %$default )
    {
	unless( defined $query->{$key} )
	{
	    $query->{$key} = $default->{$key};
	}
    }

    if( ref $this )
    {
	if( UNIVERSAL::isa($this, 'Rit::Base::Resource') )
	{
	    $this = Rit::Base::List->new([$this]);
	}

	if( UNIVERSAL::isa($this, 'Rit::Base::List') )
	{
	    return $this->find($query, $args);
	}
    }
    my $class = ref($this) || $this;

    my $search = Rit::Base::Search->new({ %$args,
					  maxlimit =>
					  Rit::Base::Search::TOPLIMIT,
					});
    $search->modify($query, $args);

#    if( $query->{'label'} )
#    {
#	debug "find label:\n".query_desig($query);
#    }

    $search->execute($args);

    my $result = $search->result;
    $result->set_type($class);
    return $result;
}


#######################################################################

=head2 find_simple

  $class->find_simple( $pred, $value )

  $node->find( $pred, $value )

Searches all nodes for those having the B<ACTIVE> property with pred
C<$pred> and text C<$value>.

C<$pred> is any type of predicate reference, like a name, id or
object. C<$value> is a string.

This uses the field valtext (valclean).  No other value types are
supported.

The search result is cached.

Note that this will not work for Literal resources (value nodes).

Examples:

  my $nodes = Rit::Base::Resource->find_simple( name => 'Ragnar' );

Returns:

a L<Rit::Base::List> object

Exceptions:

none

=cut

sub find_simple
{
    my( $this, $pred_in, $value_in ) = @_;

    # Only handles pred nodes
    my $pred = Rit::Base::Pred->get_by_label( $pred_in );
    my $pred_id = $pred->id;

    my $value = valclean($value_in);
    my $list = $Rit::Base::Cache::find_simple{$pred_id}{$value};
    unless( defined $list ) # Avoid using list overload
    {
	my @nodes;
	my $st = "select subj from arc where pred=? and valclean=? and active is true";
	my $dbh = $Rit::dbix->dbh;
	my $sth = $dbh->prepare($st);
	$sth->execute($pred_id, $value);
	while( my($subj_id) = $sth->fetchrow_array )
	{
	    push @nodes, Rit::Base::Resource->get( $subj_id );
	}
	$sth->finish;

	$list = Rit::Base::List->new(\@nodes);
	$Rit::Base::Cache::find_simple{$pred_id}{$value} = $list;
    }

    return $list;
}


#######################################################################

=head2 find_one

  $n->find_one( $query )

  $n->find_one( $query, \%args )

Does a L</find>, but excpect to fins just one.

If more than one match is found, tries one more time to find exact
matchas.

Supported args are:

  arclim


Returns:

a L<Rit::Base::Resource> object

Exceptions:

alternatives : more than one nodes matches the criterions

notfound : no nodes matches the criterions

See also L</find_set> and L</set_one>

See also L</find>.

=cut

sub find_one
{
    my( $this, $query, $args_in ) = @_;

    my( $args ) = parse_propargs($args_in);
    my $nodes = $this->find( $query, $args );

    if( $nodes->size > 1 )
    {
	my $new_nodes;
	debug "Found more than one match";

	if( $args->{'clean'} )
	{
	    # Look for an exact match
	    debug "Trying to exclude some matches";
	    my $new_nodes = $nodes->find($query,
					 { %$args,
					   clean => 0,
					 });

	    # Go with the original search result if the exclusion
	    # excluded all matches

	    unless( $new_nodes->[0] )
	    {
		$new_nodes = $nodes;
	    }
	}
	else
	{
	    $new_nodes = $nodes;
	}

	if( $new_nodes->[1] )
	{
	    # TODO: Explain 'kriterierna'

	    my $req = $Para::Frame::REQ;
	    my $uri = $req->page->url_path_slash;
	    $req->session->route->bookmark;
	    $req->set_error_response_path("/alternatives.tt");


	    my $result = $Para::Frame::REQ->result;
	    $result->{'info'}{'alternatives'}{'alts'} = $nodes;
	    $result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	    $result->{'info'}{'alternatives'}{'query'} = $query;
	    $result->{'info'}{'alternatives'}{'args'} = $args;

	    $result->{'info'}{'alternatives'}{'rowformat'} =
	      sub
	      {
		  my( $item ) = @_;
		  my $tstr = $item->list('is', undef, 'adirect')->desig || '';
		  my $cstr = $item->list('scof',undef, 'adirect')->desig;
		  my $desig = $item->desig;
		  my $desc = "$tstr $desig";
		  if( $cstr )
		  {
		      $desc .= " ($cstr)";
		  }
		  my $link = Para::Frame::Widget::jump($desc, $uri,
						       {
							route_alternative => $item->id,
							run => 'next_step',
							step_replace_params => 'route_alternative',
						       });
		  return $link;
	      };

	    $result->{'info'}{'alternatives'}{'button'} =
	      [
	       ['Backa', $req->referer_path(), 'skip_step'],
	      ];
	    $req->q->delete_all();

	    throw('alternatives', "More than one node matches the criterions");
	}

	$nodes = $new_nodes;
    }

    my $node = $nodes->[0];
    unless( $nodes->[0] )
    {
	my $req = $Para::Frame::REQ;
	my $result = $req->result;
	$result->{'info'}{'alternatives'}{'alts'} = undef;
	$result->{'info'}{'alternatives'}{'query'} = $query;
	$result->{'info'}{'alternatives'}{'args'} = $args;
	$result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	$req->set_error_response_path('/node_query_error.tt');
	throw('notfound', "No nodes matches query (1)");
    }

    return $nodes->[0];
}


#######################################################################

=head2 find_set

  $n->find_set( $query, \%args )

Finds the nodes matching $query, as would L</find_one>.  But if no
node are found, one is created using the C<$query> and
C<default_create> as properties.

Supported args are

  default
  default_create
  arclim
  res

Properties specified in C<defult> is used unless corresponding
properties i C<$query> is defined.  The resulting properties are
passed to L</create>. C<default_create> does the same, but only for
create. Not for L</find>.

Returns:

a node

Exceptions:

alternatives : more than one nodes matches the criterions

See also L</find_one> and L</set_one>

See also L</find> and L</create>.

=cut

sub find_set
{
    my( $this, $query, $args_in ) = @_;

    my( $args ) = parse_propargs($args_in);

#    debug "find_set:\n".datadump($query,2);

    my $nodes = $this->find( $query, $args )->as_arrayref;

    if( $nodes->[1] )
    {
	debug "Found more than one match";
	my $new_nodes;

	if( $args->{'clean'} )
	{
	    # Look for an exact match
	    debug "Trying to exclude some matches";
	    $new_nodes = $nodes->find($query,
				      {
				       %$args,
				       clean => 0,
				      });

	    # Go with the original search result if the exclusion
	    # excluded all matches

	    unless( $new_nodes->[0] )
	    {
		$new_nodes = $nodes;
	    }
	}
	else
	{
	    $new_nodes = $nodes;
	}

	if( $new_nodes->[1] )
	{
	    unless( $Para::Frame::REQ->is_from_client )
	    {
		throw('alternatives',
		      "More than one node matches the criterions");
	    }

	    my $req = $Para::Frame::REQ;
	    my $uri = $req->page->url_path_slash;
	    $req->session->route->bookmark;
	    $req->set_error_response_path("/alternatives.tt");

	    my $result = $Para::Frame::REQ->result;
	    $result->{'info'}{'alternatives'}{'alts'} = $nodes;
	    $result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	    $result->{'info'}{'alternatives'}{'query'} = $query;
	    $result->{'info'}{'alternatives'}{'args'} = $args;

	    $result->{'info'}{'alternatives'}{'rowformat'} =
	      sub
	      {
		  my( $item ) = @_;
		  my $tstr = $item->list('is', undef, 'adirect')->desig || '';
		  my $cstr = $item->list('scof',undef, 'adirect')->desig;
		  my $desig = $item->desig;
		  my $desc = "$tstr $desig";
		  if( $cstr )
		  {
		      $desc .= " ($cstr)";
		  }
		  my $link = Para::Frame::Widget::jump($desc, $uri,
						       {
							route_alternative => $item->id,
							run => 'next_step',
							step_replace_params => 'route_alternative',
						       });
		  return $link;
	      };

	    $result->{'info'}{'alternatives'}{'button'} =
	      [
	       ['Backa', $req->referer_path(), 'skip_step'],
	      ];
	    $req->q->delete_all();

	    throw('alternatives', "More than one node matches the criterions");
	}

	$nodes = $new_nodes;
    }

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

=head2 set_one

  $n->set_one( $query )

  $n->set_one( $query, \%args )

Just as L</find_set>, but merges all found nodes to one, if more than
one is found.

If a merging occures, one node is selected.  All
L<explicit|Rit::Base::Arc/explicit> arcs going to and from
the other nodes are copied to the selected node and then removed from the
other nodes.

Supported args are:

  default
  arclim
  res

Returns:

a node

Exceptions:

See L</find> and L</create>.

See also L</find_set> and L</find_one>

=cut

sub set_one
{
    my( $this, $query, $args_in ) = @_;

    my( $args ) = parse_propargs($args_in);

    my $nodes = $this->find( $query, $args );
    my $node = $nodes->get_first_nos;

    while( my $enode = $nodes->get_next_nos )
    {
	$enode->merge($node,
		      {
		       %$args,
		       move_literals => 1,
		      });
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

=head2 create

  $n->create( $props, \%args )

Creates a node with the specified props.

C<$props> is a hashref there the keys are the predicate names and the
value is either a node or a array(ref) of nodes or a
L<List|Rit::Base::List> of nodes.  And the nodes can be given
as anything that L</get> will accept.

Special args:

  activate_new_arcs

  submit_new_arcs

Returns:

a node

Exceptions:

See L</get>.

=cut

sub create
{
    my( $this, $props, $args_in ) = @_;

    my( $args ) = parse_propargs($args_in);

    my $subj_id = $Rit::dbix->get_nextval('node_seq');


    # TODO: Handle creation with 'is' coupled to a class. Especially
    # is $C_arc

    confess "invalid props: $props" unless ref $props; ### DEBUG


#    # Any value props should be added after datatype props
#    my @props_list;
#    if( defined $props->{'value'} )
#    {
#	@props_list =  grep{ $_ ne 'value'} keys(%$props);
#	push @props_list, 'value';
#    }
#    else
#    {
#	@props_list =  keys(%$props);
#    }
    my @props_list =  keys(%$props);


    my $adr = undef; # Define if used

    # Create all props before checking
    arc_lock;

    foreach my $pred_name ( @props_list )
    {
	# May not be only Resources
	my $vals = Para::Frame::List->new_any( $props->{$pred_name} );

	# Check for definedness
	foreach my $val ( $vals->as_array )
	{
	    debug 2, "Checking $pred_name = $val";
	    if( ($val and ((ref $val and not $val->defined) or not length $val)) or not $val )
	    {
		confess "Tried to create a node with an undefined value as $pred_name";
	    }
	}

	if( $pred_name eq 'label' )
	{
	    my $node = Rit::Base::Resource->get( $subj_id );
	    if( $vals->size > 1 )
	    {
		confess "Can't give a node more than one label";
	    }
	    $node->set_label( $vals->get_first_nos );
	}
	elsif( $pred_name =~ /^rev_(.*)$/ )
	{
	    $pred_name = $1;

	    foreach my $val ( $vals->as_array )
	    {
		Rit::Base::Arc->create({
		    subj    => $val,
		    pred    => $pred_name,
		    obj     => $subj_id,
		}, $args);
	    }
	}
	else
	{
	    foreach my $val ( $vals->as_array )
	    {
		Rit::Base::Arc->create({
		    subj    => $subj_id,
		    pred    => $pred_name,
		    value   => $val,
		}, $args);
	    }
	}
    }

    my $node = Rit::Base::Resource->get( $subj_id );
    unless( @props_list )
    {
	$node->{'new'} = 1;
    }


    arc_unlock;

    return $node;
}


#########################################################################
################################  Accessors  ############################


=head1 Accessors

=cut


#######################################################################

=head2 form_url

  $n->form_url

Returns the URL of the page for viewing/updating this node.

Returns:

A L<URI> object.

=cut

sub form_url
{
    my( $n ) = @_;

    my $base = $Para::Frame::REQ->site->home->url;
    my $path;

#    warn "$n\n";

    if( $n->is_arc )
    {
#	warn "  is an ARC\n";
	$path = 'rb/node/arc/update.tt';
    }
    elsif( $n->is_value_node )
    {
	$path = "rb/translation/node.tt";
    }
    else
    {
	my $alts = $n->list('is')->sorted('weight', 'desc')->first_prop('class_form_url');
#	debug $alts;
	if( my $path_node = $alts->get_first_nos )
	{
	    $path = $path_node->plain;
	}
	else
	{
	    $path = 'rb/node/update.tt';
	}
    }

    my $url = URI->new($path)->abs($base);

    $url->query_form([id=>$n->id]);

    return $url;
}


#########################################################################

=head2 page_url_path_slash

Returns a default page for presenting a resource.  Defaults to form_url()

=cut

sub page_url_path_slash
{
    return $_[0]->form_url;
}


#######################################################################

=head2 plain

  $n->plain

Make it a plain value. Returns self...

The plain value turns Undef objects to undef value and Literal objects
to literal values. But resource objects returns itself.

=cut

sub plain { $_[0] }


#######################################################################

=head2 id

  $n->id

The unique node id as a plain string.

=cut

sub id
{
#   confess "not a object" unless ref $_[0]; ### DEBUG
    return $_[0]->{'id'};
}


#######################################################################

=head2 name

  $n->name(...)

Just an optimization for AUTOLOAD name (using L</prop> or L</list>).

=cut

sub name
{
    my $node = shift;
#    warn "Called name...\n";
    if( @_ )
    {
	return $node->list('name', @_);
    }
    else
    {
	return $node->prop('name');
    }
}


#######################################################################

=head2 score

Used by L<Rit::Base::Seach> class.

Default: 0

TODO: Remove

=cut

sub score
{
    cluck "REMOVE ME";
    $_[0]->{'score'}||0;
} ## Used by Seach class


#######################################################################

=head2 random

  $n->random

Used by L<Rit::Base::Seach> class.  Must be set by some other
method.

Default: 0

TODO: Remove

=cut

sub random
{
    cluck "REMOVE ME";
    $_[0]->{'random'}||0;
} ## Used by Seach class


#######################################################################

=head2 is_resource

  $n->is_resource

Returns true.

=cut

sub is_resource { 1 };


#######################################################################

=head2 is_value_node

  $n->is_value_node( \%args )

Returns true if this node is a Literal Resource (aka value node).

TODO: All value nodes should be handled as literals

Returns: boolean

See also: L</this_valtype>

=cut

sub is_value_node
{
    my( $node, $args ) = @_;
    if( $node->first_prop('value', undef, $args) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


#######################################################################

=head2 empty

  $n->empty()

Returns true if this node has no properties.

Returns: boolean

=cut

sub empty
{
    my( $node ) = @_;

    if( $node->{'new'} )
    {
	return 1;
    }
    elsif( scalar keys(%{$node->{'arc_id'}}) )
    {
	return 0;
    }
    else
    {
	$node->initiate_node;
	if( $node->{'initiated_node'} > 1 )
	{
	    return 0;
	}

	my $st = "select count(ver) from arc where subj=? or obj=? or ver=? or id=?";
	my $dbh = $Rit::dbix->dbh;
	my $sth = $dbh->prepare($st);
	my $node_id = $node->id;
	$sth->execute($node_id, $node_id, $node_id, $node_id);
	my $res = 1;
	if( $sth->fetchrow_array )
	{
	    $res = 0;
	}
	$sth->finish;
	return $res;
    }
}


#######################################################################

=head2 created

  $n->created

Returns: L<Rit::Base::Literal::Time> object

=cut

sub created
{
    return $_[0]->initiate_node->{'created'};
}


#######################################################################

=head2 updated

  $n->updated

Returns: L<Rit::Base::Literal::Time> object

=cut

sub updated
{
    return $_[0]->initiate_node->{'updated'};
}


#######################################################################

=head2 owned_by

  $n->ownde_by

Returns: L<Rit::Base::Resource> object

=cut

sub owned_by
{
    return $_[0]->{'owned_by_obj'} ||=
      Rit::Base::Resource->get( $_[0]->initiate_node->{'owned_by'} );
}


########################################################################

=head2 read_access

  $n->read_access

Returns: L<Rit::Base::Resource> object

=cut

sub read_access
{
    return $_[0]->{'read_access_obj'} ||=
      Rit::Base::Resource->get( $_[0]->initiate_node->{'read_access'} );
}


########################################################################

=head2 write_access

  $n->write_access

Returns: L<Rit::Base::Resource> object

=cut

sub write_access
{
    return $_[0]->{'write_access_obj'} ||=
      Rit::Base::Resource->get( $_[0]->initiate_node->{'write_access'} );
}


########################################################################

=head2 created_by

  $n->created_by

Returns: L<Rit::Base::Resource> object

=cut

sub created_by
{
    return $_[0]->{'created_by_obj'} ||=
      Rit::Base::Resource->get( $_[0]->initiate_node->{'created_by'} );
}


########################################################################

=head2 updated_by

  $n->updated_by

Returns: L<Rit::Base::Resource> object

=cut

sub updated_by
{
    return $_[0]->{'updated_by_obj'} ||=
      Rit::Base::Resource->get( $_[0]->initiate_node->{'updated_by'} );
}


#######################################################################

=head2 list

  $n->list

Retuns a ref to a list of all property names. Also availible as
L</list_preds>.

  $n->list( $predname )

Returns a L<Rit::Base::List> of all values of the propertis
whith the predicate C<$predname>.

  $n->list( $predname, $value );

Returns C<true> if $value is not a hash and no more params exist, and
this node has a property with predicate C<$predname> and value
C<$value>.  This construct, that uses the corresponding feature in
L<Rit::Base::List/find>, enables you to say things like: C<if(
$item->is($C_city) )>. Otherwise, returns false.

  $n->list( $predname, $proplim );

Returns a L<Rit::Base::List> of all values of the propertis
whith the preicate C<$predname>, those values has the properties
specified in C<$proplim>. A C<find()> is done on the list, using
C<$proplim>.

  $n->list( $predname, $proplim, \%args )

Same, but restrict list to values of C<$arclim> property arcs.

Supported args are:

  arclim
  arclim2

C<$arclim> can be any of the strings L<direct|Rit::Base::Arc/direct>,
L<explicit|Rit::Base::Arc/explicit>,
L<indirect|Rit::Base::Arc/indirect>,
L<implicit|Rit::Base::Arc/implicit>, L<inactive|Rit::Base::Arc/inactive> and L<not_disregarded|Rit::Base::Arc/not_disregarded>.

C<arclim2> if existing, will be used for proplims. Without C<arclim2>,
C<arclim> will be used.

Note that C<list> is a virtual method in L<Template>. Use it via
autoload in TT.

unique_arcs_prio filter is applied BEFORE proplim. That means that we
choose among the versions that meets the proplim (and arclim).

=cut

sub list
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    unless( ref $node and UNIVERSAL::isa $node, 'Rit::Base::Resource' )
    {
	confess "Not a resource: ".datadump($node);
    }

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = Rit::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my( $active, $inactive ) = $arclim->incl_act;
	my @arcs;

	if( $node->initiate_prop( $pred, $proplim, $args ) )
	{
	    if( $active and $node->{'relarc'}{$name} )
	    {
#		debug "Adding relarcs";
		push @arcs, @{ $node->{'relarc'}{$name} };
	    }

	    if( $inactive and $node->{'relarc_inactive'}{$name} )
	    {
#		debug "Adding relarcs inactive for $node->{id} prop $name";
		push @arcs, @{ $node->{'relarc_inactive'}{$name} };
	    }
	}
	else
	{
#	    debug "No values for $node->{id} prop $name found!";
	    return Rit::Base::Arc::List->new_empty();
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    @arcs = Rit::Base::Arc::List->new(\@arcs)->
	      unique_arcs_prio($uap)->as_array;
	}

	if( my $arclim2 = $args->{'arclim2'} )
	{
	    my $args2 = {%$args};
	    $args2->{'arclim'} = $arclim2;
	    delete $args2->{'arclim2'};

#	    debug "Replacing arclim ".$arclim->sysdesig;
#	    debug "            with ".$arclim2->sysdesig;

	    $args = $args2;
	}

	return $pred->valtype->instance_class->list_class->
	  new([ grep $_->meets_proplim($proplim,$args),
		map $_->value, @arcs ]);
    }
    else
    {
	return $node->list_preds( $proplim, $args );
    }
}


#######################################################################

=head2 list_preds

  $n->list_preds

  $n->list_preds( $proplim )

  $n->list_preds( $proplim, \%args )

The same as L</list> with no args.

Retuns: a ref to a list of all property names.

=cut

sub list_preds
{
    my( $node, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $proplim )
    {
	confess "proplim not implemented";
    }

    my( $active, $inactive ) = $arclim->incl_act;

    $node->initiate_rel( $proplim, $args );

    my %preds_name;
    if( $active )
    {
	if( @$arclim )
	{
#	    debug "Finding active preds for node";
	    foreach my $predname (keys %{$node->{'relarc'}})
	    {
#		debug "  testing $predname";
		foreach my $arc (@{$node->{'relarc'}{$predname}})
		{
		    if( $arc->meets_arclim($arclim) )
		    {
			$preds_name{$predname} ++;
			last;
		    }
		}
	    }
	}
	else
	{
	    foreach my $predname ( keys %{$node->{'relarc'}} )
	    {
		$preds_name{ $predname } ++;
	    }
	}
    }

    if( $inactive )
    {
	if( @$arclim )
	{
	    foreach my $predname (keys %{$node->{'relarc_inactive'}})
	    {
		foreach my $arc (@{$node->{'relarc_inactive'}{$predname}})
		{
		    if( $arc->meets_arclim($arclim) )
		    {
			$preds_name{$predname} ++;
			last;
		    }
		}
	    }
	}
	else
	{
	    foreach my $predname ( keys %{$node->{'relarc'}} )
	    {
		$preds_name{ $predname } ++;
	    }
	}
    }

    # Only handles pred nodes
    my @preds = map Rit::Base::Pred->get_by_label($_, $args), keys %preds_name;

    return Rit::Base::Pred::List->new(\@preds);
}


#######################################################################

=head2 revlist

  $n->revlist

  $n->revlist( $predname )

  $n->revlist( $predname, $proplim )

  $n->revlist( $predname, $proplim, \%args )

The same as L</list> but returns the values of the reverse properties
instead.

=cut

sub revlist
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = Rit::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my( $active, $inactive ) = $arclim->incl_act;
	my @arcs;

	if( $node->initiate_revprop( $pred, $proplim, $args ) )
	{
	    if( $active and $node->{'revarc'}{$name} )
	    {
		push @arcs, @{ $node->{'revarc'}{$name} };
	    }

	    if( $inactive and $node->{'revarc_inactive'}{$name} )
	    {
		push @arcs, @{ $node->{'revarc_inactive'}{$name} };
	    }
	}
	else
	{
#	    debug 3, "  No values for revprop $name found!";
	    return Rit::Base::Arc::List->new_empty();
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    @arcs = Rit::Base::Arc::List->new(\@arcs)->
	      unique_arcs_prio($uap)->as_array;
	}

	if( my $arclim2 = $args->{'arclim2'} )
	{
	    my $args2 = {%$args};
	    $args2->{'arclim'} = $arclim2;
	    delete $args2->{'arclim2'};

	    $args = $args2;
	}

	return $pred->valtype->instance_class->list_class->
	  new([ grep $_->meets_proplim($proplim,$args),
		map $_->subj, @arcs ]);
    }
    else
    {
	return $node->revlist_preds( $proplim, $args );
    }
}


#######################################################################

=head2 revlist_preds

  $n->revlist_preds

  $n->revlist_preds( $proplim )

  $n->revlist_preds( $proplim, \%args )

The same as L</revlist> with no args.

Retuns: a ref to a list of all reverse property names.

=cut

sub revlist_preds
{
    my( $node, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( $proplim )
    {
	die "proplim not implemented";
    }

    my( $active, $inactive ) = $arclim->incl_act;

    $node->initiate_rev( $proplim, $args );

    my %preds_name;
    if( $active )
    {
	if( @$arclim )
	{
	    foreach my $predname (keys %{$node->{'revarc'}})
	    {
		foreach my $arc (@{$node->{'revarc'}{$predname}})
		{
		    if( $arc->meets_arclim($arclim) )
		    {
			$preds_name{$predname} ++;
			last;
		    }
		}
	    }
	}
	else
	{
	    foreach my $predname ( keys %{$node->{'revarc'}} )
	    {
		$preds_name{ $predname } ++;
	    }
	}
    }

    if( $inactive )
    {
	if( @$arclim )
	{
	    foreach my $predname (keys %{$node->{'revarc_inactive'}})
	    {
		foreach my $arc (@{$node->{'revarc_inactive'}{$predname}})
		{
		    if( $arc->meets_arclim($arclim) )
		    {
			$preds_name{$predname} ++;
			last;
		    }
		}
	    }
	}
	else
	{
	    foreach my $predname ( keys %{$node->{'revarc'}} )
	    {
		$preds_name{ $predname } ++;
	    }
	}
    }

    # Only handles pred nodes
    my @preds = map Rit::Base::Pred->get_by_label($_, $args), keys %preds_name;

    return Rit::Base::Pred::List->new(\@preds);
}


#######################################################################

=head2 first_prop

  $n->first_prop( $pred_name, $proplim, \%args )

Returns the value of one of the properties with predicate
C<$pred_name> or C<undef> if none found.

unique_arcs_prio filter is applied BEFORE proplim. That means that we
choose among the versions that meets the proplim (and arclim).

=cut

sub first_prop
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    my( $pred, $name );
    if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
    {
	$pred = $pred_in;
	$name = $pred->plain;
    }
    else
    {
	$pred = Rit::Base::Pred->get($pred_in);
	$name = $pred->plain
    }

    $node->initiate_prop( $pred, $proplim, $args );


    # NOTE: We should make sure that if a relarc key exists, that the
    # list never is empty


    if( my $sortargs_in = $args->{unique_arcs_prio} )
    {
	#
	# optimized version of Rit::Base::List->unique_arcs_prio
	#
	my $sortargs = Rit::Base::Arc::Lim->parse($sortargs_in);

	my $arcs = [];

	if( $active and not $inactive )
	{
	    $arcs = $node->{'relarc'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $inactive and not $active )
	{
	    $arcs = $node->{'relarc_inactive'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $active and $inactive )
	{
	    if( defined $node->{'relarc'}{$name} )
	    {
		push @$arcs, @{$node->{'relarc'}{$name}};
	    }

	    if( defined $node->{'relarc_inactive'}{$name} )
	    {
		push @$arcs, @{$node->{'relarc_inactive'}{$name}};
	    }
	}

	my( $best_arc, $best_arc_cid, $best_arc_order, $i );

	for( $i=0; $i<=$#$arcs; $i++ )
	{
	    my $arc = $arcs->[$i];
	    if( $arc->meets_arclim($arclim) and
		$arc->value_meets_proplim($proplim, $args) )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $sortargs->sortorder($best_arc);
		last;
	    }
	}

	return is_undef unless $best_arc;

	while( $i<=$#$arcs )
	{
	    my $arc = $arcs->[$i];
	    unless( ($arc->common_id == $best_arc_cid) and
		    $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim, $args)
		  )
	    {
		next;
	    }

	    my $arc_order = $sortargs->sortorder($arc);
	    if( $arc_order < $best_arc_order )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $arc_order;
	    }
	}
	continue
	{
	    $i++;
	}

	return $best_arc->value;
    }


    # No unique filter


    if( $active )
    {
	if( defined $node->{'relarc'}{$name} )
	{
	    foreach my $arc (@{$node->{'relarc'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim, $args) )
		{
		    return $arc->value;
		}
	    }
	}
    }

    if( $inactive )
    {
	if( defined $node->{'relarc_inactive'}{$name} )
	{
	    foreach my $arc (@{$node->{'relarc_inactive'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim, $args) )
		{
		    return $arc->value;
		}
	    }
	}
    }

    return is_undef;
}


#######################################################################

=head2 first_revprop

  $n->first_revprop( $pred_name, $proplim, \%args )

Returns the value of one of the reverse B<ACTIVE> properties with
predicate C<$pred_name>

unique_arcs_prio filter is applied BEFORE proplim. That means that we
choose among the versions that meets the proplim (and arclim).

=cut

sub first_revprop
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    my( $pred, $name );
    if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
    {
	$pred = $pred_in;
	$name = $pred->plain;
    }
    else
    {
	$pred = Rit::Base::Pred->get($pred_in);
	$name = $pred->plain
    }

    # NOTE: We should make sure that if a relarc key exists, that the
    # list never is empty


    $node->initiate_revprop( $pred, $proplim, $args );

    if( my $sortargs_in = $args->{unique_arcs_prio} )
    {
	#
	# optimized version of Rit::Base::List->unique_arcs_prio
	#
	my $sortargs = Rit::Base::Arc::Lim->parse($sortargs_in);

	my $arcs = [];

	if( $active and not $inactive )
	{
	    $arcs = $node->{'revarc'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $inactive and not $active )
	{
	    $arcs = $node->{'revarc_inactive'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $active and $inactive )
	{
	    if( defined $node->{'revarc'}{$name} )
	    {
		push @$arcs, @{$node->{'revarc'}{$name}};
	    }

	    if( defined $node->{'revarc_inactive'}{$name} )
	    {
		push @$arcs, @{$node->{'revarc_inactive'}{$name}};
	    }
	}

	my( $best_arc, $best_arc_cid, $best_arc_order, $i );

	for( $i=0; $i<=$#$arcs; $i++ )
	{
	    my $arc = $arcs->[$i];
	    if( $arc->meets_arclim($arclim) and
		$arc->subj->meets_proplim($proplim, $args) )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $sortargs->sortorder($best_arc);
		last;
	    }
	}

	return is_undef unless $best_arc;

	while( $i<=$#$arcs )
	{
	    my $arc = $arcs->[$i];
	    unless( ($arc->common_id == $best_arc_cid) and
		    $arc->meets_arclim($arclim) and
		    $arc->subj->meets_proplim($proplim, $args)
		  )
	    {
		next;
	    }

	    my $arc_order = $sortargs->sortorder($arc);
	    if( $arc_order < $best_arc_order )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $arc_order;
	    }
	}
	continue
	{
	    $i++;
	}

	return $best_arc->subj;
    }


    # No unique filter


    if( $active )
    {
	if( defined $node->{'revarc'}{$name} )
	{
	    foreach my $arc (@{$node->{'revarc'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->subj->meets_proplim($proplim, $args) )
		{
		    return $arc->subj;
		}
	    }
	}
    }

    if( $inactive )
    {
	if( defined $node->{'revarc_inactive'}{$name} )
	{
	    foreach my $arc (@{$node->{'revarc_inactive'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->subj->meets_proplim($proplim, $args) )
		{
		    return $arc->subj;
		}
	    }
	}
    }

    return is_undef;
}


#######################################################################

=head2 has_value

  $n->has_value({ $pred => $value }, \%args)

Returns true if one of the node properties has a combination of any of
the predicates and any of the values.  The true value returned is the
first arc found that matches.

This only takes one pred/value pair. The pred must be a plain pred
name. Not extended by prefixes or suffixes.

For the extended usage, use L</meets_proplim>.

# Predicate can be a name, object or array.  Value can be a list of
# values or anything that L<Rit::Base::List/find> takes.

Supported args are

  match
  clean
  arclim
  unique_arcs_prio

With a C<unique_arcs_prio>, we will also look for removal arcs that in
it's previous version had the value. If that arc is prioritized, it will
change the return to false, if there's no other match.


Default C<match> is C<eq>. Other supported values are C<begins> and
C<like>.

Default C<clean> is C<false>. If C<clean> is true, strings will be
compared in clean mode. (You don't have to clean the C<$value> by
yourself.)

Default C<arclim> is C<active>.

Examples:

See if node C<$n> has the name or short name 'olle' or a name (or short
name) that is an alias.

#  $n->has_value( ['name','name_short'], ['olle', {is => 'alias'}] )

See if node C<$n> has the name beginning with 'oll' or 'kall'.

#  $n->has_beginning( 'name', ['olle', 'kall'] )

Returns:

If true, returns one of the relevant arcs.

If false, returns 0.  Not the undef object.

If it's a dynamic property (a method) returns -1, that is true.

If node is a literal and search is true, returns 1

See also L</arc_list> with C<pred> and C<value> params.


TODO: Scalars (i.e strings) with properties not yet supported.

Consider $n->has_value({'some_pred'=>is_undef})

=cut

sub has_value
{
    my( $node, $preds, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    confess "Not a hashref" unless ref $preds;

#    Para::Frame::Logging->this_level(4);

    my( $pred_name, $value ) = %$preds;

    my $match = $args->{'match'} || 'eq';
    my $clean = $args->{'clean'} || 0;

    # Can we also handle dynamic preds like id or desig?
    my $pred = Rit::Base::Pred->get( $pred_name );

    $pred_name = $pred->plain;

    if( debug > 2 )
    {
	my $value_str = defined($value)?$value:"<undef>";
	debug "  Checking if node $node->{'id'} has $pred_name $match($clean) $value_str";
    }


    # Sub query
    if( ref $value eq 'HASH' )
    {
	if( debug > 3 )
	{
	    debug "  Checking if ".$node->desig.
	      " has $pred_name with the props ". query_desig($value);
	}

	unless( $match eq 'eq' )
	{
	    confess "subquery not implemented for matchtype $match";
	}

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    my @arcs;
	    foreach my $arc ( $node->arc_list($pred_name, undef, $args)->as_array )
	    {
		if( $arc->is_removal )
		{
		    if( $arc->replaces->obj->find($value, $args)->size )
		    {
			push @arcs, $arc;
		    }
		}
		elsif( $arc->obj->find($value, $args)->size )
		{
		    push @arcs, $arc;
		}
	    }

	    if( @arcs )
	    {
		foreach my $arc ( Rit::Base::Arc::List->new(\@arcs)->
				  unique_arcs_prio($uap)->as_array )
		{
		    return $arc unless $arc->is_removal;
		}
	    }
	}
	else
	{
	    foreach my $arc ( $node->arc_list($pred_name, undef, $args)->as_array )
	    {
		if( $arc->obj->find($value, $args)->size )
		{
		    return $arc;
		}
	    }
	}
	return 0;
    }

    # $value holds alternative values
    elsif( ref $value eq 'ARRAY' )
    {
	if( my $uap = $args->{unique_arcs_prio} )
	{
	    my @arcs;
	    foreach my $val (@$value )
	    {
		my $arc = $node->has_value({$pred_name=>$val},  $args);
		push @arcs, $arc if $arc;
	    }

	    if( @arcs )
	    {
		return Rit::Base::Arc::List->new(\@arcs)->
		  unique_arcs_prio($uap)->get_first_nos;
	    }
	}
	else
	{
	    foreach my $val (@$value )
	    {
		my $arc = $node->has_value({$pred_name=>$val},  $args);
		return $arc if $arc;
	    }
	}
	return 0;
    }


    # Check the dynamic properties (methods) for the node
    # Special case for optimized name
    if( $node->can($pred_name) and ($pred_name ne 'name') )
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

    if( my $uap = $args->{unique_arcs_prio} )
    {
	my @arcs;
#	debug "In has_value";
	foreach my $arc ( $node->arc_list($pred_name, undef, $args)->as_array )
	{
#	    debug 1, "  check arc ".$arc->id;
	    if( $arc->is_removal )
	    {
		if( $arc->replaces->value_equals( $value, $args ) )
		{
#		    debug "    removal passed";
		    push @arcs, $arc;
		}
	    }
	    elsif( $arc->value_equals( $value, $args ) )
	    {
#		debug "    passed";
		push @arcs, $arc;
	    }
	}

	if( @arcs )
	{
	    foreach my $arc ( Rit::Base::Arc::List->new(\@arcs)->
			      unique_arcs_prio($uap)->as_array )
	    {
		return $arc unless $arc->is_removal;
	    }
	}
    }
    else
    {
	foreach my $arc ( $node->arc_list($pred_name, undef, $args)->as_array )
	{
	    debug 3, "  check arc ".$arc->id;
	    return $arc if $arc->value_equals( $value, $args );
	}
    }


    if( debug > 2 )
    {
	my $value_str = defined($value)?$value:"<undef>";
	debug "  no such value $value_str for ".$node->desig;
    }

    return 0;
}


#######################################################################

=head2 count

  $n->count( $pred, \%args )

  $n->count( \%tmpl, \%args ) # not implemented

Counts the number of properties the node has with a specific property,
meeting the arclim.  Default arclim is C<active>.

Examples:

This can be used in C<Rit::Base::List-E<gt>find()> by count_pred
pattern. Example from TT; select active (direct) subclasses that has
10 or more instances:

  [% nodes = node.revarc_list('scof').direct.subj.find(inactive_ne=1, rev_count_pred_is_gt = 9).as_list %]

=cut

sub count
{
    my( $node, $tmpl, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( ref $tmpl and ref $tmpl eq 'HASH' )
    {
	throw('action',"count( \%tmpl, ... ) not implemented");
    }
    my $pred_id = Rit::Base::Pred->get( $tmpl )->id;

    my $arclim_sql = $arclim->sql;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare( "select count(id) as cnt from arc where pred=? and subj=? and $arclim_sql" );
    debug "select count(id) as cnt from arc where pred=? and subj=? and $arclim_sql; ($pred_id, $node->{id})";
    $sth->execute( $pred_id, $node->id );
    my( $cnt ) =  $sth->fetchrow_array;
    return $cnt;
}


#######################################################################

=head2 revcount

  $n->revcount( $pred, \%args )

  $n->revcount( \%tmpl, \%args ) # not implemented

Counts the number of properties the node has with a specific property,
meeting the arclim.  Default arclim is C<active>.

Examples:

This can be used in C<Rit::Base::List-E<gt>find()> by count_pred
pattern. Example from TT; select active (direct) subclasses that has
10 or more instances:

  [% nodes = node.revarc_list('scof').direct.subj.find(inactive_ne=1, rev_count_pred_is_gt = 9).as_list %]

=cut

sub revcount
{
    my( $node, $tmpl, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    if( ref $tmpl and ref $tmpl eq 'HASH' )
    {
	throw('action',"count( \%tmpl, ... ) not implemented");
    }
    my $pred_id = Rit::Base::Pred->get( $tmpl )->id;

    my $arclim_sql = $arclim->sql;

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare( "select count(id) as cnt from arc where pred=? and obj=? and $arclim_sql" );
    $sth->execute( $pred_id, $node->id );
    my( $cnt ) =  $sth->fetchrow_array;
    $sth->finish;
    return $cnt;
}


#######################################################################

=head2 label

  $n->label()

The constant label, if there is one for this resource.

Returns:

  A plain string or plain undef.

=cut

sub label
{
    return $_[0]->initiate_node->{'label'};
}


#######################################################################

=head2 set_label

  $n->set_label($label)

Sets the constant label. Crates the constant if not existing yet. Set
to undef to remove the constant.

Returns:

  A plain string or plain undef.

=cut

sub set_label
{
    my( $node, $label_new ) = @_;

    my $label_old = $node->label || '';
    $label_new ||= '';

    if( $label_old ne $label_new )
    {
	debug "Node $node->{id} label set to '$label_new'";

	delete $Rit::Base::Constants::Label{$label_old};
	$node->{'label'} = $label_new;
	$Rit::Base::Constants::Label{$label_new} = $node;
	$node->mark_updated;
    }

    return $label_new;
}


#######################################################################

=head2 desig

  $n->desig( \%args )

The designation of an object, to be used for node administration or
debugging.

=cut

sub desig  # The designation of obj, meant for human admins
{
    my( $node, $args ) = @_;

#    debug "About to give a designation for $node->{id}";

    my $desig;

    if( $node->has_pred('name',undef,$args) )
    {
	$desig = $node->list('name',undef,$args)->loc();
    }
    elsif( $node->has_pred('name_short',undef,$args) )
    {
	$desig = $node->list('name_short',undef,$args)->loc();
    }
    elsif( $desig = $node->label )
    {
	# That's good
    }
    elsif( $node->has_pred('value',undef,$args) )
    {
	$desig = $node->list('value',undef,$args)->loc();
    }
    elsif( $node->has_pred('code',undef,$args) )
    {
	$desig = $node->list('code',undef,$args)->loc;
    }
    else
    {
	$desig = $node->id;
    }

    $desig = $desig->loc if ref $desig; # Could be a Literal Resource
    utf8::upgrade($desig);
#    debug "Returning desig $desig";

    return truncstring( \$desig );
}


#######################################################################

=head2 sysdesig

  $n->sysdesig( \%args )

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id.

=cut

sub sysdesig
{
    my( $node, $args ) = @_;

    my $desig = $node->desig;

#    debug "Sysdesig for $node->{id}: $desig";

    if( $desig eq $node->{'id'} )
    {
	return $desig;
    }
    else
    {
	return "$node->{'id'}: $desig";
    }
}


#######################################################################

=head2 syskey

  $n->syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return sprintf("node:%d", shift->{'id'});
}


#######################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.  This asumes that the
object is a Literal Resource (aka Value Resource).  Only use this then you
know that this L</is_value_node>.

Defaults to C<is_undef>.

=cut

sub literal
{
    my( $node, $args ) = @_;

    if( UNIVERSAL::isa($node,'Para::Frame::List') )
    {
	croak "deprecated";
#	return $node->loc( $args );
    }

    debug "Turning node ".$node->{'id'}." to literal";
    return $node->first_prop('value', $args);
}


#######################################################################

=head2 loc

  $n->loc( \%args )

Asking to translate this word.  But there is only one value.  This is
probably a lone literal resource.

Used by L<Rit::Base::List/loc>.

Returns: A plain string

=cut

sub loc
{
    return shift->value->loc(@_);
}


#######################################################################

=head2 arc_list

  $n->arc_list()

  $n->arc_list( $pred_name )

  $n->arc_list( $predname, $value )

  $n->arc_list( $predname, \@values )

  $n->arc_list( $predname, $proplim )

  $n->arc_list( $predname, $proplim, $args )

Returns a L<Rit::Base::List> of the arcs that have C<$n> as
subj and C<$pred_name> as predicate.

With no C<$pred_name>, all arcs from the node is returned.

If given C<$value> or C<\@values>, returns those arcs that has any of
the given values. Similar to L</has_value> but returns a list instad
of a single arc.

unique_arcs_prio filter is applied BEFORE proplim. That means that we
choose among the versions that meets the proplim (and arclim).

=cut

sub arc_list
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = Rit::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my @arcs;

#	debug sprintf("Got arc_list for %s prop %s with arclim %s", $node->sysdesig, $name, query_desig($arclim));

	if( $node->initiate_prop( $pred, $proplim, $args ) )
	{
	    if( $active and $node->{'relarc'}{$name} )
	    {
		push @arcs, @{ $node->{'relarc'}{$name} };
	    }

	    if( $inactive and $node->{'relarc_inactive'}{$name} )
	    {
		push @arcs, @{ $node->{'relarc_inactive'}{$name} };
	    }
	}
	else
	{
#	    debug 1, "  No values for relprop $name found!";
	    return Rit::Base::Arc::List->new_empty();
	}

#	debug "  applying arclim";
	@arcs = grep $_->meets_arclim($arclim), @arcs;

	my $lr = Rit::Base::Arc::List->new(\@arcs);

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    $lr = $lr->unique_arcs_prio($uap);
	}

#	debug "List is now ".$lr->sysdesig;
	if( defined $proplim ) # The Undef Literal is also an proplim
	{
#	    debug "Sorting out the nodes matching proplim ".datadump($proplim);
#	    debug "  Sorting out the nodes matching proplim\n";

	    if( ref $proplim and ref $proplim eq 'HASH' )
	    {
		# $n->arc_list( $predname, { $pred => $value } )
		#
		$lr = $lr->find($proplim, $args);
	    }
	    elsif( not( ref $proplim) and not( length $proplim ) )
	    {
		# Treat as no proplim given
	    }
	    else
	    {
		# $n->arc_list( $predname, [ $val1, $val2, $val3, ... ] )
		#
		unless( ref $proplim and ref $proplim eq 'ARRAY' )
		{
		    $proplim = [$proplim];
		}

#		debug "proplim: ".query_desig($proplim);
		my $proplist = Rit::Base::Arc::List->new($proplim);
#		debug "Proplist contains:\n".query_desig($proplist);

		my @newlist;
		my( $arc, $error ) = $lr->get_first;
		while(! $error )
		{
#		    debug "  Does proplist containt the value ".$arc->value;
		    # May return is_undef object
		    # No match gives literal undef
		    if( ref $proplist->contains( $arc->value, $args ) )
		    {
			push @newlist, $arc;
#			debug "  MATCH";
		    }
		    ( $arc, $error ) = $lr->get_next;
		}
#		debug "limit done";

		$lr = Rit::Base::Arc::List->new(\@newlist);
	    }
	}

#	debug "Returning list $lr";
	return $lr;
    }
    else
    {
	$node->initiate_rel($proplim, $args);

	if( $proplim )
	{
	    confess "proplim not implemented";
	}

	my @arcs;
	if( $active )
	{
	    foreach my $pred_name ( keys %{$node->{'relarc'}} )
	    {
		push @arcs, @{ $node->{'relarc'}{$pred_name} };
	    }
	}

	if( $inactive )
	{
	    foreach my $pred_name ( keys %{$node->{'relarc_inactive'}} )
	    {
		push @arcs, @{ $node->{'relarc_inactive'}{$pred_name} };
	    }
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

#	debug "Returnig new list";

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    return Rit::Base::Arc::List->new(\@arcs)->unique_arcs_prio($uap);
	}
	else
	{
	    return Rit::Base::Arc::List->new(\@arcs);
	}
    }
}


#######################################################################

=head2 revarc_list

  $n->revarc_list()

  $n->revarc_list( $pred_name )

  $n->revarc_list( $predname, $proplim )

  $n->revarc_list( $predname, $proplim, $args )

Returns a L<Rit::Base::List> of the arcs that have C<$n> as
subj and C<$pred_name> as predicate.

With no C<$pred_name>, all revarcs from the node is returned.

=cut

sub revarc_list
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    if( $pred_in )
    {
	my( $pred, $name );
	if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
	{
	    $pred = $pred_in;
	    $name = $pred->plain;
	}
	else
	{
	    $pred = Rit::Base::Pred->get($pred_in);
	    $name = $pred->plain
	}

	my @arcs;

	if( $node->initiate_revprop( $pred, $proplim, $args ) )
	{
	    if( $active and $node->{'revarc'}{$name} )
	    {
		push @arcs, @{ $node->{'revarc'}{$name} };
	    }

	    if( $inactive and $node->{'revarc_inactive'}{$name} )
	    {
		push @arcs, @{ $node->{'revarc_inactive'}{$name} };
	    }
	}
	else
	{
#	    debug 3, "  No values for revprop $name found!";
	    return Rit::Base::Arc::List->new_empty();
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	my $lr = Rit::Base::Arc::List->new(\@arcs);

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    $lr = $lr->unique_arcs_prio($uap);
	}

	if( $proplim and (ref $proplim eq 'HASH' ) and keys %$proplim )
	{
	    $lr = $lr->find($proplim, $args);
	}

	return $lr;
    }
    else
    {
	$node->initiate_rev($proplim, $args);

	if( $proplim )
	{
	    die "proplim not implemented";
	}

	my @arcs;
	if( $active )
	{
	    foreach my $pred_name ( keys %{$node->{'revarc'}} )
	    {
		push @arcs, @{ $node->{'revarc'}{$pred_name} };
	    }
	}

	if( $inactive )
	{
	    foreach my $pred_name ( keys %{$node->{'revarc_inactive'}} )
	    {
		push @arcs, @{ $node->{'revarc_inactive'}{$pred_name} };
	    }
	}

	@arcs = grep $_->meets_arclim($arclim), @arcs;

	if( my $uap = $args->{unique_arcs_prio} )
	{
	    return Rit::Base::Arc::List->new(\@arcs)->unique_arcs_prio($uap);
	}
	else
	{
	    return Rit::Base::Arc::List->new(\@arcs);
	}
    }
}


#######################################################################

=head2 first_arc

  $n->first_arc( $pred_name, $proplim, \%args )

Returns one of the arcs that have C<$n> as subj and C<$pred_anme> as
predicate.

=cut

sub first_arc
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    my( $pred, $name );
    if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
    {
	$pred = $pred_in;
	$name = $pred->plain;
    }
    else
    {
	$pred = Rit::Base::Pred->get($pred_in);
	$name = $pred->plain
    }

    # NOTE: We should make sure that if a relarc key exists, that the
    # list never is empty

    $node->initiate_prop( $pred, $proplim, $args );

    if( my $sortargs_in = $args->{unique_arcs_prio} )
    {
	#
	# optimized version of Rit::Base::List->unique_arcs_prio
	#
	my $sortargs = Rit::Base::Arc::Lim->parse($sortargs_in);

	my $arcs = [];

	if( $active and not $inactive )
	{
	    $arcs = $node->{'relarc'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $inactive and not $active )
	{
	    $arcs = $node->{'relarc_inactive'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $active and $inactive )
	{
	    if( defined $node->{'relarc'}{$name} )
	    {
		push @$arcs, @{$node->{'relarc'}{$name}};
	    }

	    if( defined $node->{'relarc_inactive'}{$name} )
	    {
		push @$arcs, @{$node->{'relarc_inactive'}{$name}};
	    }
	}

	my( $best_arc, $best_arc_cid, $best_arc_order, $i );

	for( $i=0; $i<=$#$arcs; $i++ )
	{
	    my $arc = $arcs->[$i];
	    if( $arc->meets_arclim($arclim) and
		$arc->value_meets_proplim($proplim, $args) )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $sortargs->sortorder($best_arc);
		last;
	    }
	}

	return is_undef unless $best_arc;

	while( $i<=$#$arcs )
	{
	    my $arc = $arcs->[$i];
	    unless( ($arc->common_id == $best_arc_cid) and
		    $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim, $args)
		  )
	    {
		next;
	    }

	    my $arc_order = $sortargs->sortorder($arc);
	    if( $arc_order < $best_arc_order )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $arc_order;
	    }
	}
	continue
	{
	    $i++;
	}

	return $best_arc;
    }


    # No unique filter


    if( $active )
    {
	if( defined $node->{'relarc'}{$name} )
	{
	    foreach my $arc (@{$node->{'relarc'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim) )
		{
		    return $arc;
		}
	    }
	}
    }

    if( $inactive )
    {
	if( defined $node->{'relarc_inactive'}{$name} )
	{
	    foreach my $arc (@{$node->{'relarc_inactive'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim) )
		{
		    debug "Arc ".$arc->sysdesig." meets ".$arclim->sysdesig;
		    return $arc;
		}
	    }
	}
    }

    return is_undef;
}


#######################################################################

=head2 first_revarc

  $n->first_revarc( $pred_name, $proplim, \%args )

Returns one of the arcs that have C<$n> as obj and C<$pred_anme> as
predicate.

=cut

sub first_revarc
{
    my( $node, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;

    my( $pred, $name );
    if( UNIVERSAL::isa($pred_in,'Rit::Base::Pred') )
    {
	$pred = $pred_in;
	$name = $pred->plain;
    }
    else
    {
	$pred = Rit::Base::Pred->get($pred_in);
	$name = $pred->plain
    }

    # TODO: We should make sure that if a relarc key exists, that the
    # list never is empty

    $node->initiate_revprop( $pred, $proplim, $args );

    if( my $sortargs_in = $args->{unique_arcs_prio} )
    {
	#
	# optimized version of Rit::Base::List->unique_arcs_prio
	#
	my $sortargs = Rit::Base::Arc::Lim->parse($sortargs_in);

	my $arcs = [];

	if( $active and not $inactive )
	{
	    $arcs = $node->{'revarc'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $inactive and not $active )
	{
	    $arcs = $node->{'revarc_inactive'}{$name};
	    return is_undef unless defined $arcs;
	}
	elsif( $active and $inactive )
	{
	    if( defined $node->{'revarc'}{$name} )
	    {
		push @$arcs, @{$node->{'revarc'}{$name}};
	    }

	    if( defined $node->{'revarc_inactive'}{$name} )
	    {
		push @$arcs, @{$node->{'revarc_inactive'}{$name}};
	    }
	}

	my( $best_arc, $best_arc_cid, $best_arc_order, $i );

	for( $i=0; $i<=$#$arcs; $i++ )
	{
	    my $arc = $arcs->[$i];
	    if( $arc->meets_arclim($arclim) and
		$arc->value_meets_proplim($proplim, $args) )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $sortargs->sortorder($best_arc);
		last;
	    }
	}

	return is_undef unless $best_arc;

	while( $i<=$#$arcs )
	{
	    my $arc = $arcs->[$i];
	    unless( ($arc->common_id == $best_arc_cid) and
		    $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim, $args)
		  )
	    {
		next;
	    }

	    my $arc_order = $sortargs->sortorder($arc);
	    if( $arc_order < $best_arc_order )
	    {
		$best_arc = $arc;
		$best_arc_cid = $arc->common_id;
		$best_arc_order = $arc_order;
	    }
	}
	continue
	{
	    $i++;
	}

	return $best_arc;
    }


    # No unique filter


    if( $active )
    {
	if( defined $node->{'revarc'}{$name} )
	{
	    foreach my $arc (@{$node->{'revarc'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim) )
		{
		    return $arc;
		}
	    }
	}
    }

    if( $inactive )
    {
	if( defined $node->{'revarc_inactive'}{$name} )
	{
	    foreach my $arc (@{$node->{'revarc_inactive'}{$name}})
	    {
		if( $arc->meets_arclim($arclim) and
		    $arc->value_meets_proplim($proplim) )
		{
		    return $arc;
		}
	    }
	}
    }

    return is_undef;
}


#######################################################################

=head2 arc

  $n->arc( $pred_name, ... )

As L</arc_list>, but returns the only value, if only one (or zero).
Else, it returns an array ref to the list of values.

Use L</first_arc> or L</arc_list> explicitly if that's what you want!

=cut

sub arc
{
    my $node = shift;
    my $arcs = $node->arc_list(@_);

    if( defined $arcs->[1] ) # More than one element
    {
	return $arcs;
    }
    else
    {
	return $arcs->get_first_nos;
    }
}


#######################################################################

=head2 revarc

  $n->revarc( $pred_name, ... )

As L</revarc_list>, but returns the only value, if only one (or zero).
Else, it returns an array ref to the list of values.

Use L</first_revarc> or L<revarc_list> explicitly if that's what you want!

=cut

sub revarc
{
    my $node = shift;
    my $arcs = $node->revarc_list(@_);

    if( defined $arcs->[1] ) # More than one element
    {
	return $arcs;
    }
    else
    {
	return $arcs->get_first_nos;
    }
}



#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

#######################################################################

=head2 add

  $n->add({ $pred1 => $value1, $pred2 => $value2, ... }, \%args )

The value may be a list (or L<Para::Frame::List>) of values.

Supported args are:
  res

Returns:

  The node object

=cut

sub add
{
    my( $node, $props, $args ) = @_;

    unless( UNIVERSAL::isa($props, 'HASH') )
    {
	confess "Invalid parameter ".query_desig($props);
    }

    foreach my $pred_name ( keys %$props )
    {
	# Must be pred_name, not pred

	# Values may be other than Resources
	my $vals = Para::Frame::List->new_any( $props->{$pred_name} );

	foreach my $val ( $vals->as_array )
	{
	    Rit::Base::Arc->create({
		subj => $node,
		pred => $pred_name,
		value => $val,
	    }, $args);
	  }
    }
    return $node;
}


#######################################################################

=head2 update

  $n->update( \%props, \%args )

Updates all properties having the mentioned predicate.  It doesn't
touch properties with predicates not mentioned. C<%props> is a
hash with pairs of predicates and values.

  - If the node has a property with the same predicate and value as
    one of the properties given to update; that arc will be untouchted

  - If a property is given to update that doesn't exist in the node;
    an arc will be created

  - If the node has a property with a predicate, and that predicate
    exists in a property given to update, and the value fo the two
    properties is not the same; that existing property will be removed
    and a new arc created.

This algorithm will not touch existing properties if the new property
has the same value.  This asures that any properties on the arcs will
remain.

The most of the job is done by L</replace>.

Supported args are:

  res

Returns:

  The updated node. For literals, it may be a new object.

Exceptions:

See L</replace>

=cut

sub update
{
    my( $node, $props, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    # Update specified props to their values

    # Does not update props not mentioned

    # - existing specified values is unchanged
    # - nonexisting specified values is created
    # - existing nonspecified values is removed

    my @arcs_old = ();

    # Start by listing all old values for removal
    foreach my $pred_name ( keys %$props )
    {
	my $old = $node->arc_list( $pred_name, undef, aais($args,'explicit') );
	push @arcs_old, $old->as_array;
    }

    $node->replace(\@arcs_old, $props, $args);

    return $node;
}


#######################################################################

=head2 equals

  1. $n->equals( $node2 )

  2. $n->equals( { $pred => $val, ... } )

  3. $n->equals( [ $node2, $node3, $node4, ... ] )

  4. $n->equals( $list_obj )

  5. $n->equals( $undef_obj )

  6. $n->equals( $literal_obj )

  7. $n->equals( $id )

  8. $n->equals( $name )


Returns true (C<1>) if the argument matches the node, and false (C<0>)
if it does not.

Case C<2> search for nodes matching the criterions and returns true if
any of the elements in the list is the node.

For C<3> and C<4> we also returns true if the node exists in the given list.

Case C<5> always returns false. (A resource is never undef.)

For case C<7> we compare the id with the node id.

In cases C<6> and C<8> we searches for nodes that has the given
C<name> and returns true if one of the elements found matches the
node. This search is done using L</find_simple> which dosn't handle
literal nodes.


=cut

sub equals
{
    my( $node, $node2, $args ) = @_;

    return 0 unless defined $node2;

    if( ref $node2 )
    {
	if( UNIVERSAL::isa $node2, 'Rit::Base::Resource' )
	{
	    return( ($node->id == $node2->id) ? 1 : 0 );
	}
	elsif( ref $node2 eq 'HASH' )
	{
	    return Rit::Base::List->new([$node])->find($node2, $args)->size;
	}
	elsif( ref $node2 eq 'Rit::Base::List' )
	{
	    foreach my $val ( $node2->as_array )
	    {
		return 1 if $node->equals($val, $args);
	    }
	    return 0;
	}
	elsif( ref $node2 eq 'ARRAY' )
	{
	    foreach my $val (@$node2 )
	    {
		return 1 if $node->equals($val, $args);
	    }
	    return 0;
	}
	elsif( ref $node2 eq 'Rit::Base::Undef' )
	{
	    return 0; # Resource is defined
	}
	elsif( ref $node2 and UNIVERSAL::isa($node2, 'Rit::Base::Literal') )
	{

	    # We will not try totransform a literal node into a
	    # resource node. They are not considered equals
	    return 0;
	}
	else
	{
#	    die "not implemented: $node2";
	    debug "While comparing $node->{id} with other";
	    confess "not implemented: ".datadump($node2);
	}
    }

    if( $node2 =~ /^\d+$/ )
    {
	return( ($node->id == $node2) ? 1 : 0 );
    }
    elsif( $node2 = Rit::Base::Resource->get( $node2 ) )
    {
	return $node->equals( $node2, $args );
    }

    return 0;
}


#######################################################################

=head2 vacuum

  $n->vacuum( \%args )

Vacuums each arc of the resource

Supported args are:

  arclim

Returns: The node

=cut

sub vacuum
{
    my( $node, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $no_lim = Rit::Base::Arc::Lim->parse(['active','inactive']);
    foreach my $arc ( $node->arc_list( undef, undef, $no_lim )->as_array )
    {
	next if $arc->disregard;
	$Para::Frame::REQ->may_yield;
	$arc->vacuum( $args );
    }

    return $node;
}


#######################################################################

=head2 merge

  $node1->merge($node2, \%args )

Copies all arcs from C<$node1> to C<$node2>. And remove the arcs from
C<$node1>.  Copies both arcs and reverse arcs.

Supported args are:

  move_literals
  res
  arclim

If C<$move_literals> is true, all properties are copied.  If false or
missing, only ovject properties are copied.

This will destroy any properties of the copied arcs, beyond the basic
properties C<{subj, pred, value}>.

TODO:

Move the arcs in order to keep arc metadata.

Returns: C<$node2>

=cut

sub merge
{
    my( $node1, $node2, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    if( $node1->equals( $node2, $args ) )
    {
	throw('validation', "You can't merge a node into itself");
    }

    debug sprintf("Merging %s with %s",
		  $node1->sysdesig($args),
		  $node2->sysdesig($args),
		 );

    my $move_literals = $args->{'move_literals'} || 0;

    foreach my $arc ( $node1->arc_list(undef, undef, aais($args,'explicit'))->nodes )
    {
	my $pred_name = $arc->pred->plain;
	if( my $obj = $arc->obj )
	{
	    debug sprintf "  Moving %s", $arc->sysdesig;
	    $node2->add({ $pred_name => $obj }, $args );
	}
	elsif( $move_literals )
	{
	    debug sprintf "  Moving %s", $arc->sysdesig($args);
	    $node2->add({$pred_name => $arc->value}, $args );
	}
	$arc->remove( $args );
    }

    foreach my $arc ( $node1->revarc_list(undef, undef, aais($args,'explicit'))->nodes )
    {
	my $pred_name = $arc->pred->plain;
	if( my $subj = $arc->subj )
	{
	    $subj->add({ $pred_name => $node2 }, $args);
	}
	$arc->remove( $args );
    }

    return $node2;
}


#######################################################################

=head2 link_paths

  $n->link_paths( \%args, $level )

Create a list of paths leading up to this node. A list of a list of
nodes. The list of nodes is the path from the base down to the leaf.

This can be used to generate a path with links to go up in the tree.

Supported args are:

  level
  arclim

=cut

sub link_paths
{
    my( $node, $args_in, $lvl ) = @_;
    my( $args ) = parse_propargs($args_in);

    $lvl ||= 0;
    $lvl ++;

    my @link_paths;

    debug 3, '  'x$lvl . "link_paths for ".$node->id;

    # TODO:  ----> merge arclim with 'direct' with a method
    my @parents = $node->list('scof', {inactive_ne=>1},
			      aais($args,'adirect'))->nodes;

    foreach my $parent ( @parents )
    {
	debug 3, '  'x$lvl . "  parent ".$parent->id;
	foreach my $part ( @{ $parent->link_paths($args, $lvl) } )
	{
	    if( debug > 2 )
	    {
		debug '  'x$lvl . "    part has: ".join(', ', map $_->id, @$part);
	    }

	    push @$part, $parent;
	    push @link_paths, $part;
	}
    }

    unless( @parents )
    {
	push @link_paths, [];
    }


    if( debug > 2 )
    {
	debug '  'x$lvl . "  Returning:";
	foreach my $row ( @link_paths )
	{
	    debug '  'x$lvl . "    " . join(", ", map $_->id, @$row);
	}
	debug '  'x$lvl . "  ----------";
    }

    return \@link_paths;
}



#######################################################################

=head2 wd

  $n->wd( $pred, \%args )

Calls L</wdirc> for the class given by
C<$pred-E<gt>range-E<gt>instance_class>

Stands for Widget for Displaying

Returns: a HTML widget for displaying the value

=cut

sub wd
{
    my( $node, $pred_name, $args_in ) = @_;
    my( $args_parsed ) = parse_propargs($args_in);
    my $args = {%$args_parsed}; # Shallow clone

    my $R = Rit::Base->Resource;
    my $rev = 0;

    if( $pred_name =~ /^rev_(.*)$/ )
    {
	$pred_name = $1;
	$rev = 1;
    }

    # Should we support dynamic preds?
    my $pred = Rit::Base::Pred->get($pred_name);

    my( $range, $range_scof );
    if( $rev )
    {
	$args->{'rev'} = 1;
	$range = ( $args->{'range'} ? $R->get($args->{'range'}) :
		   $pred->first_prop('domain') || $C_resource );
	$range_scof = ( $args->{'range_scof'} ?
			$R->get($args->{'range_scof'}) :
			$pred->first_prop('domain_scof') );
	debug "REV Range". ( $range_scof ? ' (scof)' : '') .": ".
	  $range->sysdesig;
    }
    else
    {
	$range = ( $args->{'range'} ? $R->get($args->{'range'}) :
		   $pred->valtype );
	$range_scof = ( $args->{'range_scof'} ?
			$R->get($args->{'range_scof'}) :
			$pred->first_prop('range_scof') );
    }

    if( $range_scof )
    {
	$args->{'range_scof'} = $range_scof;
	$range = $range_scof;
    }
    else
    {
	$args->{'range'} = $range;
    }

    # widget for updating subclass of range class
    return $range->instance_class->wdirc($node, $pred, $args);
}


#######################################################################

=head wdirc

  $class->wdirc( $subj, $pred, \%args )

  Widget for Displaying Instance of Range Class

Example:

  $pred->range->instance_class->wdirc($subj, $pred, $args);

=cut

sub wdirc
{
    my( $this, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = '';
    my $is_scof = $args->{'range_scof'};
    my $is_rev = $args->{'rev'} || '';
    my $is_pred = ( $is_scof ? 'scof' : 'is' );
    my $range = $args->{'range'} || $args->{'range_scof'};
    unless( $range )
    {
	confess "Range missing";
    }
    my $list = ( $is_rev ?
		 $subj->revarc_list( $pred->name, undef, 'explicit' )
		 : $subj->arc_list( $pred->name, undef, 'explicit' ) );

    if( $is_rev )
    {
	$list = $list->find({ subj => { $is_pred => $range }}); # Sort out arcs on range...
    }
    else
    {
	$list = $list->find({ obj => { $is_pred => $range }}); # Sort out arcs on range...
    }

    $out .= Para::Frame::Widget::label_from_params({
			       label       => delete $args->{'label'},
			       tdlabel     => delete $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => delete $args->{'label_class'},
			      });

    $out .= '<ul>'
      if( $list->size > 1);

    foreach my $arc ($list->as_array)
    {
	$out .= '<li>'
	  if( $list->size > 1);

	my $item;
	if( $is_rev )
	{
	    $item = $arc->subj;
	}
	else
	{
	    $item = $arc->value;
	}

	$out .= $item->as_html;

	if( $list->size > 1)
	{
	    $out .= '</li>';
	}
	else
	{
	    $out .= '<br/>';
	}
    }

    return $out;
}


#######################################################################

=head2 wu

  $n->wu( $pred, \%args )

Stands for Widget for Updating

Calls L</wuirc> for the class given by
C<$pred-E<gt>range-E<gt>instance_class>

Returns: a HTML widget for updating the value

=cut

sub wu
{
    my( $node, $pred_name, $args_in, $extra_html ) = @_;
    my( $args_parsed ) = parse_propargs($args_in);
    my $args = {%$args_parsed}; # Shallow clone

    my $R = Rit::Base->Resource;
    my $rev = 0;

    if( $pred_name =~ /^rev_(.*)$/ )
    {
	$pred_name = $1;
	$rev = 1;
	$args->{'rev'} = 1;
    }

    # Should we support dynamic preds?
    my $pred = Rit::Base::Pred->get($pred_name);

    my( $range, $range_scof );

    if( $args->{'range'} or $args->{'range_scof'} )
    {
	$range = $args->{'range'} ? $R->get($args->{'range'}) : undef;
	$range_scof = $args->{'range_scof'} ?
	  $R->get($args->{'range_scof'}) : undef;
    }
    elsif( $rev )
    {
	$range = $pred->first_prop('domain') || $C_resource;
	$range_scof = $pred->first_prop('domain_scof');

	#debug "REV Range". ( $range_scof ? ' (scof)' : '') .": ".
	#  $range->sysdesig;
    }
    elsif( $pred_name eq 'value' ) # value resource
    {
	$range = $node->revarc(undef,undef,['active','submitted'])->pred->range;
    }
    else
    {
	$range = $pred->valtype;
	$range_scof = $pred->first_prop('range_scof');
    }

    if( $range_scof )
    {
	$args->{'range_scof'} = $range_scof;
	$range = $range_scof;
    }
    else
    {
	$args->{'range'} = $range;
    }

    # Wrap in for ajax
    my $out = "";
    my $ajax = ( defined $args->{'ajax'} ? $args->{'ajax'} : 1 );
    my $from_ajax = $args->{'from_ajax'};
    my $divid = $args->{'divid'} ||
      ( $ajax ? Rit::Base::AJAX->new_form_id() : undef );
    $args->{'divid'} = $divid
      if $divid and not $from_ajax;

    $out .= Para::Frame::Widget::label_from_params({
			       label       => delete $args->{'label'},
			       tdlabel     => delete $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => delete $args->{'label_class'},
			      });

    $out .= '<div id="'. $divid .'" style="position: relative;">'
      if $divid and not $from_ajax;

    # widget for updating subclass of range class
    $out .= $range->instance_class->wuirc($node, $pred, $args);

    $out .= $extra_html
      if $extra_html;

    if( $ajax and not $from_ajax )
    {
	$out .= '</div>';
	$out .= $node->register_ajax_pagepart( $pred_name, $divid, $args );
    }

    return $out;
}


#######################################################################

=head2 wuh

  $n->wuh( $pred, $obj, \%args )

Stands for Widget for Updating Hidden

Returns: a HTML hidden field for making a new arc

=cut

sub wuh
{
    my( $node, $pred_name, $obj, $args ) = @_;

    my $R = Rit::Base->Resource;

    my $extra = '';

    if( $args->{'if'} )
    {
	$extra = '__if_'. $args->{'if'};
    }
    my $key = "arc___subj_". $node->id ."__pred_". $pred_name . $extra;
    return Para::Frame::Widget::hidden($key, $obj->id);
}


#######################################################################

=head2 register_ajax_pagepart

Returns: html-fragment of javascript-code to register a divid

=cut

sub register_ajax_pagepart
{
    my( $node, $pred_name, $divid, $args ) = @_;

    my $out = "";
    my $params = {
		  from_ajax => 1,
		 };
    foreach my $key (keys %$args)
    {
	if( $key =~ /label/ or
	    $key eq 'arclim' or
	    $key eq 'res' or
	    $key eq 'depends_on'
	  )
	{}
	elsif( ref $args->{$key} )
	{
	    $params->{$key} = $args->{$key}->id;
	}
	else
	{
	    $params->{$key} = $args->{$key};
	}
    }

    my $home = $Para::Frame::REQ->site->home_url_path;
    $out .=
      "<script type=\"text/javascript\">
        <!--
            new PagePart('$divid', '$home/ajax/wu',
            { params: { subj: '". $node->id ."',
                        params: '". objToJson( $params ) ."',
                        pred_name: '$pred_name' }";

    if( $args->{'depends_on'} )
    {
	my $depends_on = $args->{'depends_on'};
	if( ref $depends_on )
	{
	    debug "Ref depends_on: ". ref $depends_on;
	    $depends_on = join(', ', map("'$_'", @$depends_on));
	}
	else
	{
	    $depends_on = "'$depends_on'";
	}
	debug "Depends on now: ". $depends_on;
	$out .= ", depends_on: [ $depends_on ]";
    }
    $out .= "}); //--> </script>";

    return $out;
}


#######################################################################

=head wuirc

  $class->wuirc( $subj, $pred, \%args )

  Widget for Updating Instance of Range Class

Example:

  $pred->range->instance_class->wuirc($subj, $pred, $args);

Returns: a HTML widget for updating subj when a pred's range is a
Resource..

All wuirc should handle: disabled

Use args:
  rev => 1
    for reverse pred

  range => $range_node
    the range class. May not be the same as $class

  range_scof => $range_scof_node
    the range scof class. May not be the same as $class

  arc_type => singular
    if there should be only one arc with that pred from that subj.

  inputtype => select
    to get a select of all $n->rev_scof's.

  inputtype => select_tree
    to get a select of all $n->rev_scof_direct, and then another etc.

  inputtype => text
    to get a text-input.

  ajax => true
    defaults to use ajax-widgets.

=cut

sub wuirc
{
    my( $this, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $out = '';
    my $is_scof = $args->{'range_scof'};
    my $is_rev = ( $args->{'rev'} ? 'rev' : '' );
    my $is_pred = ( $is_scof ? 'scof' : 'is' );
    my $range = $args->{'range'} || $args->{'range_scof'};
    my $ajax = ( defined $args->{'ajax'} ? $args->{'ajax'} : 1 );
    my $divid = $args->{'divid'};
    my $disabled = $args->{'disabled'} || 0;

    confess "Range missing"
      unless( $range );

    my $list = ( $is_rev ?
		 $subj->revarc_list( $pred->name, undef, 'explicit' )
		 : $subj->arc_list( $pred->name, undef, 'explicit' ) );

    if( $is_rev )
    {
	$list = $list->find({ subj => { $is_pred => $range }}); # Sort out arcs on range...
    }
    else
    {
	$list = $list->find({ obj => { $is_pred => $range }}); # Sort out arcs on range...
    }

    my $arc_type = $args->{'arc_type'};
    my $singular = (($arc_type||'') eq 'singular') ? 1 : undef;

    my $inputtype = $args->{'inputtype'} ||
      ( ( $range->revcount($is_pred) < 25 ) ?
	( $is_scof ? 'select_tree' : 'select' ) : 'text' );

    if( $list and
	( $inputtype eq 'text' or not $singular ) )
    {
	delete $args->{'default_value'}; # No default when values exist...

	$out .= "<ul id=\"$divid-list\">"
	  if( $list->size > 1);

	foreach my $arc (@$list)
	{
	    $out .= '<li>'
	      if( $list->size > 1);

	    my $check_subj = $arc->subj;
	    my $item = $arc->value;

	    unless( $disabled )
	    {
		if( $ajax )
		{
		    my $arc_id = $arc->id;
		    $out .= $q->input({ type => 'button',
					value => '-',
					onclick => "rb_remove_arc('$divid', '$arc_id')",
					class => 'nopad',
				 });
		}
		else
		{
		    my $field = 'arc_'. $arc->id .'__subj_'. $check_subj->id
		      .'__pred_'. $pred->name;
		    $out .= Para::Frame::Widget::hidden('check_arc_'. $arc->id, 1);
		    $out .= Para::Frame::Widget::checkbox($field, $item->id, 1);
		}
	    }

	    $out .= ( $is_rev ? $check_subj->wu_jump :
		      $item->wu_jump ) .'&nbsp;'.
			$arc->edit_link_html;

	    if( $list->size > 1)
	    {
		$out .= '</li>';
	    }
	    else
	    {
		$out .= '<br/>';
	    }
	}
    }

    if( not $singular or
	not $list or
	( $singular and $inputtype ne 'text' ))
    {
	if( $ajax and $inputtype eq 'text' )
	{
	    unless( $disabled )
	    {
		my $search_params = { $is_pred => $range->id };

		$out .= "
              <input type=\"button\" id=\"$divid-button\" value=\"". Para::Frame::L10N::loc('Add') ."\"/>";
		$out .=
		  "<script type=\"text/javascript\">
                     <!--
                         new RBInputPopup('$divid-button',
                                  '$divid', '". objToJson( $search_params ) ."',
                                  'name_clean_like', '". $pred->name ."',
                                  '". $subj->id ."') //--> </script>";
	    }
	}
	elsif( $inputtype eq 'text' )
	{
	    my $type_str = ( $is_scof ? 'scof_' : 'type_' ) . $range->label .'__';

	    $out .=
	      Para::Frame::Widget::input('arc___'. $type_str .'subj_'.
					 $subj->id .'__'. $is_rev .'pred_'.
					 $pred->name,
					 $args->{'default_value'},
					 {
					  label => Para::Frame::L10N::loc('Add'),
					 });
	}
	elsif( $inputtype eq 'select' )
	{
	    my $header = $args->{'header'} ||
	      ( $args->{'default_value'} ? '' :
		Para::Frame::L10N::loc('Select') );
	    $out .= Rit::Base::Widget::wub_select( $subj, $pred->name, $range,
						   {
						    %$args,
						    header => $header,
						   });
	}
	elsif( $inputtype eq 'select_tree' )
	{
	    $out .= Rit::Base::Widget::wub_select_tree( $subj, $pred->name, $range, $args );
	}
	else
	{
	    confess "Unknown input type: $inputtype";
	}
    }

    return $out;
}


#######################################################################

=head2 arcversions

  $n->arcversions( $pred, $proplim, \%args )

Produces a list of all relevant common-arcs, with lists of their
relevant versions, used for chosing version to activate/deactivate.

  language (if applicable)
    arc-list...

=cut

sub arcversions
{
    my( $node, $predname, $proplim ) = @_;

#    debug "In arcversions for $predname for ".$node->sysdesig;

    return #probably new...
      unless( UNIVERSAL::isa($node, 'Rit::Base::Resource') );


    #debug "Got request for prop_versions for ". $node->sysdesig ." with pred ". $predname;

    my $arcs = $node->arc_list( $predname, $proplim, ['submitted','active'] )->unique_arcs_prio(['active','submitted']);

    my %arcversions;

    while( my $arc = $arcs->get_next_nos )
    {
	my @versions;

	if( $arc->realy_objtype ) # Value resource
	{
	    push @versions,
	      $arc->obj->arc_list( 'value', $proplim, ['active','submitted'] )->as_array;
	}
	else
	{
	    push @versions,
	      $arc->versions($proplim, ['active','submitted'])->sorted('updated')->as_array;
	    #debug "Getting versions of ". $arc->id .".  Got ". $arc->versions($proplim, ['active','submitted'])->size;
	}

	$arcversions{$arc->id} = \@versions
	  if( @versions );
	#debug "Added arc ". $arc->sysdesig;
    }

    #debug datadump( \%arcversions, 2 );

    return \%arcversions;
}


#######################################################################

=head2 tree_select_widget

  $n->tree_select_widget( $pred, \%args )

Returns: a HTML widget that draws the C<scof> tree.

=cut

sub tree_select_widget
{
    my( $node, $pred_in, $args ) = @_;

    my $pred = Rit::Base::Pred->get($pred_in)
      or die "no pred ($pred_in)";

    my $data = $node->tree_select_data($pred, $args);

    my $select = Template::PopupTreeSelect->new(
						name => 'Ritbase_tsw',
						data => $data,
						title => 'Select a node',
						button_label => 'Choose',
						include_css => 0,
						image_path => $Para::Frame::REQ->site->home_url_path . '/images/PopupTreeSelect/',
					       );
    return $select->output;
}


#######################################################################

=head2 tree_select_data

  $n->tree_select_data( $pred, \%args )

Used by L</tree_select_widget>

=cut

sub tree_select_data
{
    my( $node, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    $pred or confess "param pred missing";

    my $id = $node->id;
    my $pred_id = $pred->id;

    my $name = $node->prop('name', undef, $args)->loc;
    debug 2, "Processing treepart $id: $name";
    my $rec = $Rit::dbix->select_record("select count(id) as cnt from arc where pred=? and obj=? and active is true", $pred_id, $id);
    my $cnt = $rec->{'cnt'};
    debug 3, "                    $id: $cnt nodes";
    my $flags = " ";
    $flags .= 'p' if $node->private;
    $flags .= 'i' if $node->inactive;

    my $label = sprintf("%s (%d) %s", $name, $cnt, $flags);

    my $data =
    {
     label  => $label,
     value  => $id,
    };

    my $childs = $node->revlist('scof', undef, aais($args,'adirect'));

    if( $childs->size )
    {
	debug 2, "                   $id got ".($childs->size)." childs";
	$data->{children} = [];

	foreach my $subnode ( $childs->nodes )
	{
	    push @{ $data->{children} },
	      $subnode->tree_select_data($pred, $args);
	}
    }

    $Para::Frame::REQ->may_yield;

    return $data;
}

#########################################################################
################################  Private methods  ######################

=head1 Private methods

=cut


#########################################################################

=head2 find_class

  $n->find_class()

TODO: Handle the class for value nodes based on the value-arcs
valtype.


Checks if the resource has a property C<is> to a class that has the
property C<class_handled_by_perl_module>.

The classes C<literal_class>, C<arc> and C<pred> and C<Rule> are
handled as special cases in order to avoid bootstrap problems. Of
these, handling of C<literal_class> is needed in this method.

This tells that the resource object should be blessd into the class
represented bu the object pointed to by
C<class_handled_by_perl_module>.  The package name is given by the
nodes C<code> property.

If no such classes are found, L<Rit::Base::Resource> is used.  We make
a special check for L<Rit::Base::Arc> but L<Rit::Base::Pred> uses
C<class_handled_by_perl_module>.

A Class can only be handled by one perl class. But a resource can have
propertis C<is> to more than one class. Special perl packages may be
constructed for this, that inherits from all the given classes.

Each node has one single object in the cache. The class of the object
are based on the currently B<active> nodes. In order to work on a new,
not yet active node, you may have to first get the is-relation
activated. (TODO: Fix this)

Returns: A scalar with the package name

=cut

sub find_class
{
    my( $node ) = @_;

    # I guess this is sufficiently efficient

    # This is an optimization for:
    # my $classes = $islist->list('class_handled_by_perl_module');
    #
#    my $islist = $node->list('is',undef,'not_disregarded');
#    debug "Finding the class for node $node->{id}";

    # Used in startup. Get pred here. (For optimization)
    my $p_is = Rit::Base::Pred->get_by_label('is');
    my $p_chbpm = Rit::Base::Pred->
      get_by_label('class_handled_by_perl_module');
    my $p_code = Rit::Base::Pred->get_by_label('code');

    my $islist = $node->list($p_is);
    my @classes;
    foreach my $elem ($islist->as_array)
    {
#	debug "Looking at is $elem->{id}";
	if( $elem->{'id'} == $Rit::Base::Literal::Class::id )
	{
	    return "Rit::Base::Literal::Class";
	}

	foreach my $class ($elem->list($p_chbpm)->nodes )
	{
	    my $pkg = $class->first_prop($p_code)->plain;
#	    debug "  found $pkg";

	    # Let confident classes handle themself
	    if( UNIVERSAL::can($pkg, 'use_class') )
	    {
#		debug "    using a custom class";
		# Should only be for classes that never should be
		# metaclasses
		#
		return $pkg->use_class;
	    }

#	    debug "  Handled by $class";
	    push @classes, $class;
	}
    }

    if( $classes[0] )
    {
	my $package;
	my $key = join '_', sort map $_->id, @classes;
	if( $package = $Rit::Base::Cache::Class{ $key } )
	{
	    return $package;
	}

	my( @classnames );
	foreach my $class ( @classes )
	{
	    my $classname = $class->first_prop($p_code)->plain;
	    unless( $classname )
	    {
		debug datadump($class,2);
		confess "No classname found for class $class->{id}";
	    }

	    eval
	    {
		require(package_to_module($classname));
	    };
	    if( $@ )
	    {
		debug $@;
	    }
	    else
	    {
		push @classnames, $classname;
	    }
	}

	no strict "refs";
	if( $classnames[1] ) # Multiple inheritance
	{
	    $package = "Rit::Base::Metaclass::$key";
#	    debug "Creating package $package";
	    @{"${package}::ISA"} = ("Rit::Base::Metaclass",
				    @classnames,
				    "Rit::Base::Resource");
	}
	elsif( $classnames[0] ) # Single inheritance
	{
	    my $classname = $classnames[0];
	    $package = "Rit::Base::Metaclass::$classname";
	    #	    debug "Creating package $package";
	    @{"${package}::ISA"} = ($classname, "Rit::Base::Resource");
	}
	else
	{
	    $package = "Rit::Base::Resource";
	}

	return $Rit::Base::Cache::Class{ $key } = $package;
    }

    return "Rit::Base::Resource";
}


#########################################################################

=head2 first_bless

  $node->first_bless()

  $node->first_bless( @init_params )

Used by L</get>

Uses C<%Rit::Base::LOOKUP_CLASS_FOR>

Calls L</init> with given params

=cut

sub first_bless
{
    my $node = shift;

    # get the right class
    my( $class ) = ref $node;
    if( $Rit::Base::LOOKUP_CLASS_FOR{ $class } )
    {
	# We assume that Arcs et al are retrieved directly. Thus,
	# only look for 'is' arcs. Pred and Rule nodes should have an
	# is arc. Lastly, look if it's an arc if it's nothing else.

	$class = $node->find_class();

	# If its a resource and no args given for init
	if( ($class eq 'Rit::Base::Resource') and not $_[0] )
	{
	    # Check if this is an arc
	    #
	    my $sth_id = $Rit::dbix->dbh->prepare("select * from arc where ver = ?");
	    $sth_id->execute($node->{'id'});
	    my $rec = $sth_id->fetchrow_hashref;
	    $sth_id->finish;
	    if( $rec )
	    {
		$class = "Rit::Base::Arc";
		@_ = ($rec);
	    }
	}

	bless $node, $class;
    }

#    $node->initiate_node; # Done on demand

    confess $node unless ref $node;

    $node->init(@_);

#    debug sprintf "Node %d initiated as $node", $node->id;

    return $node;
}


#########################################################################

=head2 on_class_perl_module_change

  $node->on_class_perl_module_change()

Blesses the childs

=cut

sub on_class_perl_module_change
{
    my( $node, $arc, $pred_name, $args_in ) = @_;

    debug "on_class_perl_module_change for ".$node->sysdesig;

    # Check out new module
    my $modules = $node->list('class_handled_by_perl_module',undef,'relative');
    while( my $module = $modules->get_next_nos )
    {
	eval
	{
	    my $code = $module->code->plain;
	    require(package_to_module($code));
	};
	if( $@ )
	{
	    debug $@;
	}
    }

    if( $node->isa('Rit::Base::Literal::Class') )
    {
	debug "TODO: rebless literals for ".$node->sysdesig;
    }
    else
    {
	my $childs = $node->revlist('is');
	while( my $child = $childs->get_next_nos )
	{
	    $child->rebless($args_in);
	}
    }
}


#########################################################################

=head2 code_class

  $node->code_class()

List the class of the node

=cut

sub code_class
{
    my( $node ) = @_;

    return Para::Frame::Code::Class->get($node);
}


#########################################################################

=head2 code_class_desig

  $node->code_class_desig()

Return a string naming the class of the node suitable for Rit::Base.

=cut

sub code_class_desig
{
    my( $node ) = @_;

    my $cl = Para::Frame::Code::Class->get($node);
    my $cl_name = $cl->name;
    if( $cl_name =~ /^Rit::Base::Metaclass/ )
    {
	return join ", ", map $_->name, @{$cl->parents};
    }
    else
    {
	return $cl_name;
    }
}


#########################################################################

=head2 rebless

  $node->rebless( \%args )

Called by L<Rit::Base::Arc/create_check> and
L<Rit::Base::Arc/remove_check> for updating the blessing of the
resource object.

This checks the class by calling L</find_class>.

If the class has changed, calls L</on_unbless> in the old class,
reblesses in the new class and then calls L</on_bless>. This should
work also for metaclasses L<Rit::Base::Metaclass>.

For a new C<is> arc; the rebless is done after the infered arcs are
created and before the calling of L</on_arc_add>.

For a removed C<is> arc; the rebless is done after the infered arcs
are removed and before the calling of L</on_arc_del>.

The new package are required if necessary.

Returns: the resource object

=cut

sub rebless
{
    my( $node, $args_in ) = @_;

    my $class_old = ref $node;
    my $class_new = $node->find_class;
    if( $class_old ne $class_new )
    {
	debug "Reblessing ".$node->sysdesig;
	debug "  from $class_old\n    to $class_new";
	unless($class_new =~ /^Rit::Base::Metaclass::/ )
	{
	    eval
	    {
		require(package_to_module($class_new));
	    };
	    if( $@ )
	    {
		debug $@;
	    }
	}

	if( $node->isa("Rit::Base::Metaclass") )
	{
	    if( $class_new->isa("Rit::Base::Metaclass") )
	    {
		no strict "refs";
		foreach my $class_old_real (@{"${class_old}::ISA"})
		{
		  REBLESS_BMM:
		    {
			foreach my $class_new_real (@{"${class_new}::ISA"})
			{
			    if( $class_old_real eq $class_new_real )
			    {
				last REBLESS_BMM;
			    }
			}

			if( my $method = $class_old->can("on_unbless") )
			{
			    &{$method}($node, $class_new, $args_in);
			}
		    }
		}
	    }
	    else
	    {
		no strict "refs";
		foreach my $class_old_real (@{"${class_old}::ISA"})
		{
		    if( $class_old_real ne $class_new )
		    {
			if( my $method = $class_old_real->can("on_unbless") )
			{
			    &{$method}($node, $class_new, $args_in);
			}
		    }
		}
	    }
	}
	else
	{
	    if( $class_new->isa("Rit::Base::Metaclass") )
	    {
	      REBLESS_BNM:
		{
		    no strict "refs";
		    foreach my $class_new_real (@{"${class_new}::ISA"})
		    {
			if( $class_old eq $class_new_real )
			{
			    last REBLESS_BNM;
			}
		    }

		    if( my $method = $class_old->can("on_unbless") )
		    {
			&{$method}($node, $class_new, $args_in);
		    }
		}
	    }
	    else
	    {
		$node->on_unbless( $class_new, $args_in );
	    }
	}

	######################
	#
	bless $node, $class_new;
	#
	######################

	if( $class_old->isa("Rit::Base::Metaclass") )
	{
	    if( $node->isa("Rit::Base::Metaclass") )
	    {
		no strict "refs";
		foreach my $class_new_real (@{"${class_new}::ISA"})
		{
		  REBLESS_AMM:
		    {
			foreach my $class_old_real (@{"${class_old}::ISA"})
			{
			    if( $class_old_real eq $class_new_real )
			    {
				last REBLESS_AMM;
			    }
			}

			if( my $method = $class_new_real->can("on_bless") )
			{
			    &{$method}($node, $class_old, $args_in);
			}
		    }
		}
	    }
	    else
	    {
		no strict "refs";
		foreach my $class_old_real (@{"${class_old}::ISA"})
		{
		    if( $class_old_real ne $class_new )
		    {
			if( my $method = $class_new->can("on_bless") )
			{
			    &{$method}($node, $class_old, $args_in);
			}
		    }
		}
	    }
	}
	else
	{
	    if( $node->isa("Rit::Base::Metaclass") )
	    {
		no strict "refs";
		foreach my $class_new_real (@{"${class_new}::ISA"})
		{
		    if( $class_old ne $class_new_real )
		    {
			if( my $method = $class_new_real->can("on_bless") )
			{
			    &{$method}($node, $class_old, $args_in);
			}
		    }
		}
	    }
	    else
	    {
		$node->on_bless( $class_old, $args_in );
	    }
	}
    }

    return $node;
}


#########################################################################

=head2 on_unbless

  $node->on_unbless( $class_new, \%args )

See L</rebless>

Reimplement this

See also L<Rit::Base::Metaclass/on_unbless>

Returns: ---

=cut

sub on_unbless
{
    return;
}


#########################################################################

=head2 on_bless

  $node->on_bless( $class_old, \%args )

See L</rebless>

Reimplement this

See also L<Rit::Base::Metaclass/on_bless>

Returns: ---

=cut

sub on_bless
{
    return;
}


#########################################################################

=head2 on_arc_add

  $node->on_arc_add( $arc, $pred_name, \%args )

Called by L<Rit::Base::Arc/create_check>. This is called after the arc
has been created and after other arcs has been created by inference
from this arc. It's also called after L</rebless>.

Reimplement this.

C<$pred_name> is given as a shortcut for C<$arc-E<gt>pred-E<gt>name>

See also L<Rit::Base::Metaclass/on_arc_add>

Returns: ---

=cut

sub on_arc_add
{
    return;
}


#########################################################################

=head2 on_arc_del

  $node->on_arc_del( $arc, $pred_name, \%args )

Called by L<Rit::Base::Arc/remove_check> that is called by
L<Rit::Base::Arc/remove> just after we know that the arc is going to
be removed. This method is called at the end of C<remove_check> after
the infered arcs has been removed and after L</rebless> has been
called. This is done while the present arc is
L<Rit::Base::Arc/disregard>. The arc is removed and the caches cleaned
up after this method L</on_arc_del> returns.

You have to check each arc if it's disregarded or not, while in this
method. Other infered arcs may have been removed.

TODO: If it's to much job to check for disregards, we may filter them
out beforehand. But in most cases, it will only affect the present
arc.

Reimplement this.

C<$pred_name> is given as a shortcut for C<$arc-E<gt>pred-E<gt>name>

See also L<Rit::Base::Metaclass/on_arc_del>

Returns: ---

=cut

sub on_arc_del
{
    return;
}


#########################################################################

=head2 new

  Class->new( $id, @args )

The caller must take care of using the cache
C<$Rit::Base::Cache::Resource{$id}> before calling this constructor!

The C<@args> differs for diffrent classes. Specially implemented in
L<Rit::Base::Arc> and maby other classes. Will call L</initiate_cache>
with the given args in the given class.

=cut

sub new
{
    my $class = shift;
    my $id    = shift;

    # Resources not stored in DB can have negative numbers
    unless( $id =~ /^-?\d+$/ )
    {
	confess "Invalid id for node: $id";
    }

    confess "class $class invalid" if ref $class;

    my $node = bless
    {
	'id' => $id,
    }, $class;

    $Rit::Base::Cache::Resource{ $id } = $node;

    $node->initiate_cache(@_);

#    warn("Set up new node $node for -->$id<--\n");

    return $node;
}


#########################################################################

=head2 get_by_anything

  Rit::Base::Resource->get_by_anything( $val, \%args )

Same as L</find_by_anything>, but returns ONE node

If input is undef, will return a L<Rit::Base::Undef> rather than
throwing an exception for an empty list.

=cut

sub get_by_anything
{
    my( $class, $val, $args ) = @_;

    my $list = $class->find_by_anything($val, $args);

    my $req = $Para::Frame::REQ;

    unless( $list->size )
    {
	if( $args->{'valtype'} )
	{
	    if( $args->{'valtype'}->coltype eq 'obj' )
	    {
		unless( $val )
		{
		    return is_undef;
		}
	    }
	}

	my $msg = "";
	if( $req and $req->is_from_client )
	{
	    my $result = $req->result;
	    $result->{'info'}{'alternatives'}{'query'} = $val;
	    $result->{'info'}{'alternatives'}{'args'} = $args;
	    $result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	    $req->set_error_response_path("/node_query_error.tt");
#	    debug datadump($result,5);
	}
	else
	{
	    $msg .= query_desig($val);
	    $msg .= Carp::longmess;
	}
	throw('notfound', "No nodes matches query:\n$msg");
    }

    if( $list->size > 1 )
    {
	# Did we make the choice for this?

	# TODO: Handle situations with multipple choices (in sequence (nested))

	unless( $req and $req->is_from_client )
	{
	    confess "We got a list: ".$list->sysdesig;
	}

	my $home = $req->site->home_url_path;
	if( my $item_id = $req->q->param('route_alternative') )
	{
	    $req->q->delete('route_alternative');
	    return Rit::Base::Resource->get( $item_id );
	}

	# Ask for which alternative; redo

	$req->session->route->bookmark;
	$req->set_error_response_path("/alternatives.tt");
	my $page = $req->page;
	my $uri = $page->url_path_slash;
	my $result = $req->result;
	$result->{'info'}{'alternatives'} =
	{
	 title => "Välj alterativ",
	 text  => "Sökning gav flera alternativ\n",
	 alts => $list,
	 rowformat => sub
	 {
	     my( $item ) = @_;
	     my $tstr = $item->list('is', undef, 'adirect')->desig || '';
	     my $cstr = $item->list('scof',undef, 'adirect')->desig;
	     my $desig = $item->desig;
	     my $desc = "$tstr $desig";
	     if( $cstr )
	     {
		 $desc .= " ($cstr)";
	     }
	     my $link = Para::Frame::Widget::jump($desc, $uri,
					      {
					       route_alternative => $item->id,
					       run => 'next_step',
					       step_replace_params => 'route_alternative',
					      });
	     return $link;
	 },
	 button =>
	 [
	  ['Backa', $req->referer_path(), 'skip_step'],
	 ],
	};
	$req->q->delete_all();
	throw('alternatives', 'Specificera alternativ');
    }

    return $list->get_first_nos;
}


#########################################################################

=head2 get_by_label

  $class->get_by_label( $label )

Looks for a label WITH THE SPECIFIED CLASS.

If called fro L<Rit::Base::Pred> it will assume it's a predicate

=cut

sub get_by_label
{
    my( $this, $label ) = @_;

    unless( $Rit::Base::Constants::Label{$label} )
    {
	if( ref $label )
	{
	    confess "label must be a plain string";
	}
	my $sth = $Rit::dbix->dbh->prepare(
		  "select * from node where label=?");
	$sth->execute( $label );
	my( $rec ) = $sth->fetchrow_hashref;
	$sth->finish;
	my $id = $rec->{'node'};

	unless( $id )
	{
	    confess "Constant $label doesn't exist";
	}

	# We have to trust that the label is of the class given with
	# $this. Otherwise, we would have to look up the class, which
	# would result in infinite recursion during startup on the
	# first use of pred 'is'.

	# Each class init should validate the node...

	$Rit::Base::Constants::Label{$label} = $this->get( $id );
	$Rit::Base::Constants::Label{$label}->initiate_node($rec);
    }

    my $class = ref $this || $this;
    if( $class ne 'Rit::Base::Resource' )
    {
	if( my $obj = $Rit::Base::Constants::Label{$label} )
	{
	    unless( UNIVERSAL::isa $obj, $class )
	    {
		confess "Constant $label is not a $class";
	    }

	    return $obj;
	}
	return undef;
    }

    return $Rit::Base::Constants::Label{$label};
}


#########################################################################

=head2 init

  $node->init

May be implemented in a subclass to initiate class specific data.

Returns the node

=cut

sub init
{
    return $_[0];
}


#########################################################################

=head2 initiate_cache

  $node->initiate_cache

Returns the node with all data resetted. It will be reread from the DB.

=cut

sub initiate_cache
{
    my( $node ) = @_;

    # TODO: Callers should reset the specific part
#    warn "resetting node $node->{id}\n";


    $node->{'arc_id'}                 = {};
    $node->{'relarc'}                 = {};
    $node->{'revarc'}                 = {};
    $node->{'relarc_inactive'}        = {};
    $node->{'revarc_inactive'}        = {};
    $node->{'initiated_relprop'}      = {};
    $node->{'initiated_revprop'}      = {};
    $node->{'initiated_rel'}          = 0;
    $node->{'initiated_rev'}          = 0;
    $node->{'initiated_rel_inactive'} = 0;
    $node->{'initiated_rev_inactive'} = 0;
    $node->{'new'}                    = 0;

    $node->{'initiated_node'} ||= 0;
    if( $node->{'initiated_node'} > 1 )
    {
	if( $UNSAVED{$node->{'id'}} )
	{
	    debug "CHANGES of node $node->{id} not yet saved";
	}
	else
	{
	    foreach my $key (qw(
                       coltype label owned_by_obj owned_by
                       read_access_obj read_access write_access_obj
                       write_access created created_by_obj created_by
                       updated updated_by_obj updated_by
                       ))
	    {
		delete $node->{$key};
	    }

	    $node->{'initiated_node'} = 0;

	    # We want to reinitiate the node since for exampel preds
	    # should always be initiated.

#	    debug "RE-initiating node $node->{id} from DB";
	    $node->initiate_node;
	}
    }

    return $node;
}


#########################################################################

=head2 initiate_node

  $node->initiate_node()

  $node->initiate_node( $rec )

=cut

sub initiate_node
{
    my( $node, $rec ) = @_;
    return $node if $node->{'initiated_node'};

    my $nid = $node->{'id'};
    my $class = ref $node;

    unless( $rec )
    {
	my $sth_node = $Rit::dbix->dbh->prepare("select * from node where node = ?");
	$sth_node->execute($nid);
	$rec = $sth_node->fetchrow_hashref;
	$sth_node->finish;
    }

    if( $rec )
    {
	if( my $pred_coltype = $rec->{'pred_coltype'} )
	{
	    $class = "Rit::Base::Pred";
	    bless $node, $class;
	    $node->{'coltype'} = $pred_coltype;
	}

	if( my $label = $rec->{'label'} )
	{
	    $node->{'label'} = $label;
	}

	$node->{'owned_by'} = $rec->{'owned_by'};
	$node->{'read_access'} = $rec->{'read_access'};
	$node->{'write_access'} = $rec->{'write_access'};
	$node->{'created'} = Rit::Base::Literal::Time->get( $rec->{'created'} );
	$node->{'created_by'} = $rec->{'created_by'};
	$node->{'updated'} = Rit::Base::Literal::Time->get( $rec->{'updated'} );
	$node->{'updated_by'} = $rec->{'updated_by'};
#	debug "  Created $node->{created} by $node->{created_by}";

	$node->{'initiated_node'} = 2;
    }
    else
    {
	$node->{'initiated_node'} = 1;
    }

    return $node;
}


#########################################################################

=head2 node_rec_exist

  $node->node_rec_exist

Returns: True if there exists a node record

=cut

sub node_rec_exist
{
    my( $node ) = @_;

    $node->initiate_node;

    if( $node->{'initiated_node'} > 1 )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


#########################################################################

=head2 mark_unsaved

=cut

sub mark_unsaved
{
    $UNSAVED{$_[0]->{'id'}} = $_[0];
#    debug "Node $_[0]->{id} marked as unsaved now";
}


#########################################################################

=head2 mark_updated

  $node->mark_updated( $time, $user )

This will update info about the nodes update-time and who did the
updating.

Default user is the request user

Default time is now

For not creating a node rec, consider using:

  $node->mark_updated if $node->node_rec_exist;

The changes will be saved after the request, or by calling L</commit>.

Returns: a time obj

TODO: implement args

=cut

sub mark_updated
{
    my( $node, $time, $u ) = @_;
    $time ||= now();
    $u ||= $Para::Frame::REQ->user;
    $node->initiate_node;
    $node->{'updated'} = $time;
    $node->{'created'} ||= $time;
    $node->{'updated_by_obj'} = $u;
    $node->{'created_by_obj'} ||= $u;
    $node->mark_unsaved;
    return $time;
}


#########################################################################

=head2 commit

=cut

sub commit
{
#    debug "Comitting Resource node changes";
    return if $Para::Frame::FORK;

    eval
    {
	my $cnt = 0;
	foreach my $node ( values %UNSAVED )
	{
	    debug "Saving node ".$node->sysdesig;
	    $node->save;

	    unless( ++$cnt % 100 )
	    {
		debug "Saved $cnt";
		$Para::Frame::REQ->may_yield;
		die "cancelled" if $Para::Frame::REQ->cancelled;
	    }
	}
    };
    if( $@ )
    {
	debug $@;
	Rit::Base::Resource->rollback;
    }
}


#########################################################################

=head2 rollback

=cut

sub rollback
{
    debug "ROLLBACK NODES";
    foreach my $node ( values %UNSAVED )
    {
	$node->initiate_cache;
    }
    %UNSAVED = ();
}


#########################################################################

=head2 save

=cut

sub save
{
    my( $node ) = @_;

    my $nid = $node->{'id'} or confess "No id in $node";

#    debug "Saving node $nid with label ".$node->label;

    my $dbix = $Rit::dbix;

    $node->initiate_node;

    my $u = $Para::Frame::REQ->user;
    my $uid = $u->id;
    my $now = now();
    my $public = Rit::Base::Constants->get('public');
    my $sysadmin_group = Rit::Base::Constants->get('sysadmin_group');

    $node->{'read_access'}    ||= $public->id;
    $node->{'write_access'}   ||= $sysadmin_group->id;
    $node->{'created'}        ||= $now;

    if( $node->{'updated_by_obj'} )
    {
	$node->{'created_by'}   = $node->{'updated_by_obj'}->id;
    }
    $node->{'created_by'}     ||= $uid;

    $node->{'updated'}        ||= $now;
    if( $node->{'updated_by_obj'} )
    {
	$node->{'updated_by'}   = $node->{'updated_by_obj'}->id;
    }
    $node->{'updated_by'}     ||= $node->{'created_by'};

    if( $node->{'owned_by_obj'} )
    {
	$node->{'owned_by'}     = $node->{'owned_by_obj'}->id;
    }
    $node->{'owned_by'}       ||= $node->{'created_by'};


    my @values =
      (
       $node->label,
       $node->{'owned_by'},
       $node->{'read_access'},
       $node->{'write_access'},
       $node->{'coltype'},
       $dbix->format_datetime($node->{'created'}),
       $node->{'created_by'},
       $dbix->format_datetime($node->{'updated'}),
       $node->{'updated_by'},
       $nid,
      );

    if( $node->{'initiated_node'} == 2 ) # Existing node part
    {
	my $sth = $dbix->dbh->prepare("update node set
                                        label=?,
                                        owned_by=?,
                                        read_access=?,
                                        write_access=?,
                                        pred_coltype=?,
                                        created=?,
                                        created_by=?,
                                        updated=?,
                                        updated_by=?
                                        where node=?");

#	debug "Updating node with values ".join(', ',map{defined($_)?$_:'<undef>'} @values);

	$sth->execute(@values) or die;
    }
    else
    {
	my $sth = $dbix->dbh->prepare("insert into node (label, owned_by,
                                        read_access, write_access,
                                        pred_coltype, created,
                                        created_by, updated,
                                        updated_by, node)
                                        values (?,?,?,?,?,?,?,?,?,?)");

#	debug "Creating node with values ".join(', ',map{defined($_)?$_:'<undef>'} @values);

	$sth->execute(@values) or die;
	$node->{'initiated_node'} = 2;
    }

    $Rit::Base::Cache::Changes::Updated{$nid} ++;

    delete $UNSAVED{$nid};
    return 1;
}


#########################################################################

=head2 initiate_rel

=cut

sub initiate_rel
{
    my( $node, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

    my $nid = $node->id;

    debug 2, "initiating $nid";

    if( $arclim->size )
    {
#	debug "Initiating node $nid rel with arclim";

	my( $active, $inactive ) = $arclim->incl_act();

	my $sql = "select * from arc where subj=?";

	if( $active and not $inactive )
	{
	    return if $_[0]->{'initiated_rel'};
	    $sql .= " and active is true";
	}
	elsif( $inactive and not $active )
	{
	    return if $_[0]->{'initiated_rel_inactive'};
	    $sql .= " and active is false";
	}
	elsif( $active and $inactive )
	{
	    if( $_[0]->{'initiated_rel'} and
		$_[0]->{'initiated_rel_inactive'} )
	    {
		return;
	    }
	}

	# TODO:
	# Here we have to make an intelligent guess if it's faster to
	# initiate all the arcs or just the ones that are asked for.
	# (using $arclim->sql )

	my $extralim = 0;

#	debug "Initiating node $nid with $sql";
	my $sth_init_subj = $Rit::dbix->dbh->prepare($sql);
	$sth_init_subj->execute($nid);
	my $recs = $sth_init_subj->fetchall_arrayref({});
	$sth_init_subj->finish;

	my $rowcount = $sth_init_subj->rows;
	if( $rowcount > 100 )
	{
	    debug "initiate_rel $node->{id}";
	    debug "Populating $rowcount arcs";
	    debug "ARGS: ".query_desig($args);
	}

	my $cnt = 0;
	foreach my $rec ( @$recs )
	{
	    $node->populate_rel( $rec );

	    # Handle long lists
	    unless( ++$cnt % 100 )
	    {
		debug "Populated $cnt";
		$Para::Frame::REQ->may_yield;
		die "cancelled" if $Para::Frame::REQ->cancelled;
	    }
	}

	unless( $extralim )
	{
	    if( $active )
	    {
		$node->{'initiated_rel'} = 1;

		# Mark up all individual preds for the node as initiated
		foreach my $name ( keys %{$node->{'relarc'}} )
		{
		    $node->{'initiated_relprop'}{$name} = 2;
		}

	    }

	    if( $inactive )
	    {
		$node->{'initiated_rel_inactive'} = 1;
	    }
	}
    }
    else
    {
	return if $_[0]->{'initiated_rel'};

#	debug "Initiating node $nid rel WITHOUT arclim";

	my $p_name_id = Rit::Base::Resource->get_by_label('name')->id;

	# Optimized for also getting value nodes
	my $sth_init_subj_name = $Rit::dbix->dbh->prepare("select * from arc where subj in(select obj from arc where (subj=? and pred=? and active is true)) UNION select * from arc where subj=? and active is true");
	$sth_init_subj_name->execute($nid, $p_name_id, $nid);
	my $recs = $sth_init_subj_name->fetchall_arrayref({});
	$sth_init_subj_name->finish;


	# TODO: Maby it woule be a litle mor efficient to start by the
	# extra name-nodes and after that initiate the arcs from this
	# node. Then, the name arcs will already be defined.

	my @extra_nodes_initiated;
	my $cnt = 0;
	foreach my $rec ( @$recs )
	{
	    if( $rec->{'subj'} == $nid )
	    {
		$node->populate_rel( $rec );
	    }
	    else # A literal resource for pred name
	    {
		my $subjnode = $node->get( $rec->{'subj'} );
		$subjnode->populate_rel( $rec );
		push @extra_nodes_initiated, $subjnode;
	    }

	    # Handle long lists
	    unless( ++$cnt % 100 )
	    {
		debug "Populated $cnt";
		$Para::Frame::REQ->may_yield;
		die "cancelled" if $Para::Frame::REQ->cancelled;
	    }
	}

	# Mark up all individual preds for the node as initiated
	foreach my $name ( keys %{$node->{'relarc'}} )
	{
	    $node->{'initiated_relprop'}{$name} = 2;
	}

	foreach my $subnode ( @extra_nodes_initiated )
	{
	    foreach my $name ( keys %{$subnode->{'relarc'}} )
	    {
		$subnode->{'initiated_relprop'}{$name} = 2;
	    }
	    $subnode->{'initiated_rel'} = 1;
	}
#    warn "End   init all props of node $node->{id}\n";

	$node->{'initiated_rel'} = 1;
    }
}


#########################################################################

=head2 initiate_rev

=cut

sub initiate_rev
{
    my( $node, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act();

    my $nid = $node->id;

#    debug "initiating rev for $nid with A$active I$inactive";
#    if( $_[0]->{'initiated_rev'} )
#    {
#	debug "  initiated_rev";
#    }

    my $sql = "select * from arc where obj=?";

    if( $active and not $inactive )
    {
	return if $_[0]->{'initiated_rev'};
    }
    elsif( $inactive and not $active )
    {
	return if $_[0]->{'initiated_rev_inactive'};
    }
    elsif( $active and $inactive )
    {
	if( $_[0]->{'initiated_rev'} and
	    $_[0]->{'initiated_rev_inactive'} )
	{
	    return;
	}
    }

    # TODO:
    # Here we have to make an intelligent guess if it's faster to
    # initiate all the arcs or just the ones that are asked for.

    # The revarc list may be much larger than the relarc list

    my( $arclim_sql, $extralim ) = $arclim->sql;
    if( $arclim_sql )
    {
	$sql .= " and ".$arclim_sql;
    }

    my $sth_init_obj = $Rit::dbix->dbh->prepare($sql);
    $sth_init_obj->execute($nid);
    my $recs = $sth_init_obj->fetchall_arrayref({});
    $sth_init_obj->finish;

    my $rowcount = $sth_init_obj->rows;
    if( $rowcount > 100 )
    {
	debug "initiate_rev $node->{id}";
	debug "Populating $rowcount arcs";
	debug "ARGS: ".query_desig($args);
    }

    my $cnt = 0;
    foreach my $rec ( @$recs )
    {
	$node->populate_rev( $rec, undef );

	# Handle long lists
	unless( ++$cnt % 100 )
	{
	    debug "Populated $cnt";
	    $Para::Frame::REQ->may_yield;
	    die "cancelled" if $Para::Frame::REQ->cancelled;
	}
    }

    unless( $extralim )
    {
	if( $active )
	{
	    $node->{'initiated_rev'} = 1;

	    # Mark up all individual preds for the node as initiated
	    foreach my $name ( keys %{$node->{'revarc'}} )
	    {
		$node->{'initiated_revprop'}{$name} = 2;
	    }

	}

	if( $inactive )
	{
	    $node->{'initiated_rev_inactive'} = 1;
	}
    }
}

#########################################################################

=head2 initiate_prop

Returns undef if no values for this prop

=cut

sub initiate_prop
{
    my( $node, $pred, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;
    my $name = $pred->plain;

    unless( ref $node and UNIVERSAL::isa $node, 'Rit::Base::Resource' )
    {
	confess "Not a resource: ".datadump($node);
    }

    if( $inactive and not $active )
    {
	if( $node->{'initiated_rel_inactive'} )
	{
	    # Keeps key nonexistent if nonexistent
	    return $node->{'relarc_inactive'}{ $name };
	}
    }
    elsif( $active and not $inactive )
    {
	if( $node->{'initiated_relprop'}{$name} and
	    $node->{'initiated_relprop'}{$name} > 1
	  )
	{
	    # Keeps key nonexistent if nonexistent
	    return $node->{'relarc'}{ $name };
	}

	if( $node->{'initiated_rel'} )
	{
	    # Keeps key nonexistent if nonexistent
	    return $node->{'relarc'}{ $name };
	}
    }
    elsif( $active and $inactive )
    {
	if( $node->{'initiated_relprop'}{$name} and
	    $node->{'initiated_relprop'}{$name} > 1 and
	    $node->{'initiated_rel_inactive'} )
	{
	    return 1;
	}
    }

    my $extralim = 0; # Getting less than all?
    if( $active )
    {
	$node->{'initiated_relprop'}{$name} = 1;
    }


    my $nid = $node->id;
    confess "Node id missing: ".datadump($node,3) unless $nid;

    # Keep $node->{'relarc'}{ $name } nonexistant if no such arcs, since
    # we use the list of preds as meaning that there exists props with
    # those preds

    # arc_id and arc->name is connected. don't clear one

    if( my $pred_id = $pred->id )
    {
#	debug "initiate_prop $node->{id} $name";
	if( debug > 3 )
	{
	    $Rit::Base::timestamp = time;
	}

	my $recs;
	if( ($name eq 'name') and not $inactive ) # Optimization...
	{
	    my $sth_init_subj_pred_name = $Rit::dbix->dbh->prepare("select * from arc where subj in(select obj from arc where (subj=? and pred=? and active is true)) UNION select * from arc where (subj=? and pred=? and active is true)");
	    $sth_init_subj_pred_name->execute( $nid, $pred_id, $nid, $pred_id );
	    $recs = $sth_init_subj_pred_name->fetchall_arrayref({});
	    $sth_init_subj_pred_name->finish;
	}
	else
	{
	    my $sql = "select * from arc where subj=$nid and pred=$pred_id";
	    if( $inactive and not $active )
	    {
		$sql .= " and active is false";
	    }
	    if( $active and not $inactive )
	    {
		$sql .= " and active is true";
	    }

	    my $sth_init_subj_pred = $Rit::dbix->dbh->prepare($sql);
	    $sth_init_subj_pred->execute();
	    $recs = $sth_init_subj_pred->fetchall_arrayref({});
	    $sth_init_subj_pred->finish;

	    my $rowcount = $sth_init_subj_pred->rows;
	    if( $rowcount > 20 )
	    {
		if( UNIVERSAL::isa $proplim, "Rit::Base::Resource" )
		{
		    my $obj_id = $proplim->id;
		    debug 2, "  rowcount > 20. Using obj_id from proplim $obj_id";
		    $sql = "select * from arc where subj=$nid and pred=$pred_id and obj=$obj_id";
		    my( $arclim_sql, $extralim_sql ) = $arclim->sql;
		    if( $arclim_sql )
		    {
			$sql .= " and ".$arclim_sql;
		    }

		    my $sth = $Rit::dbix->dbh->prepare($sql);
		    $sth->execute();
		    $recs = $sth->fetchall_arrayref({});
		    $sth->finish;
		    $extralim ++;
		    $rowcount = $sth->rows;
		}
	    }

	    if( $rowcount > 100 )
	    {
		debug "initiate_prop $node->{id} $name";
		debug "Populating $rowcount arcs";
		debug "ARGS: ".query_desig($args);
	    }
	}


	my @extra_nodes_initiated;
	foreach my $rec ( @$recs )
	{
	    debug "  populating with ".datadump($rec,4)
	      if debug > 4;
	    if( $rec->{'subj'} == $nid )
	    {
		$node->populate_rel( $rec, $args );
	    }
	    else
	    {
		my $subnode = $node->get_by_id( $rec->{'subj'} );
		$subnode->populate_rel( $rec, $args );
		push @extra_nodes_initiated, $subnode;
	    }
	}

	# Only for active statements
	foreach my $subnode ( @extra_nodes_initiated )
	{
	    foreach my $name ( keys %{$subnode->{'relarc'}} )
	    {
		$subnode->{'initiated_relprop'}{$name} = 2;
	    }
	    $subnode->{'initiated_rel'} = 1;
	}

#	debug "* prop $name for $nid is now initiated";
    }
    else
    {
	debug "* prop $name does not exist!";
    }

    if( $extralim )
    {
	$node->{'initiated_relprop'}{$name} = 0;
    }
    elsif( $active )
    {
#	debug "prop $nid $name initiaded to 2";
	$node->{'initiated_relprop'}{$name} = 2;
    }


    # Keeps key nonexistent if nonexistent
    if( $active and not $inactive )
    {
	return $node->{'relarc'}{ $name };
    }
    elsif( $inactive and not $active )
    {
	return $node->{'relarc_inactive'}{ $name };
    }
    else
    {
	return $node->{'relarc'}{ $name } ||
	  $node->{'relarc_inactive'}{ $name };
    }
 }

#########################################################################

=head2 initiate_revprop

Returns undef if no values for this prop (regardless proplim and arclim)

TODO: Use custom DBI fetchrow

=cut

sub initiate_revprop
{
    my( $node, $pred, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);
    my( $active, $inactive ) = $arclim->incl_act;
    my $extralim = 0;
    my $nid = $node->id;
    my $name = $pred->plain;

    if( $inactive and not $active )
    {
	if( $node->{'initiated_rev_inactive'} )
	{
	    # Keeps key nonexistent if nonexistent
	    return $node->{'revarc_inactive'}{ $name };
	}
    }
    elsif( $active and not $inactive )
    {
	if( $node->{'initiated_revprop'}{$name} and
	    $node->{'initiated_revprop'}{$name} > 1
	  )
	{
	    # Keeps key nonexistent if nonexistent
	    return $node->{'revarc'}{ $name };
	}

	if( $node->{'initiated_rev'} )
	{
	    # Keeps key nonexistent if nonexistent
	    return $node->{'revarc_inactive'}{ $name };
	}
    }
    elsif( $active and $inactive )
    {
	if( $node->{'initiated_revprop'}{$name} and
	    $node->{'initiated_revprop'}{$name} > 1 and
	    $node->{'initiated_rev_inactive'} )
	{
	    return 1;
	}
    }

    if( $active )
    {
	$node->{'initiated_revprop'}{$name} = 1;
    }


    debug 3, "Initiating revprop $name for $nid";

    # Keep $node->{'revarc'}{ $name } nonexistant if no such arcs,
    # since we use the list of preds as meaning that there exists
    # props with those preds

    # arc_id and arc->name is connected. don't clear one

    if( my $pred_id = $pred->id )
    {
	if( debug > 1 )
	{
	    $Rit::Base::timestamp = time;
	}

	my $sql = "select * from arc where obj=$nid and pred=$pred_id";

	my $arclim_sql;
	( $arclim_sql, $extralim ) = $arclim->sql;
	if( $arclim_sql )
	{
	    $sql .= " and ".$arclim_sql;
	}


	my $sth_init_obj_pred = $Rit::dbix->dbh->prepare($sql);
	$sth_init_obj_pred->execute();
	my $recs = $sth_init_obj_pred->fetchall_arrayref({});
	$sth_init_obj_pred->finish;

	my $num_of_arcs = scalar( @$recs );
	if( debug > 1 )
	{
	    my $ts = $Rit::Base::timestamp;
	    $Rit::Base::timestamp = time;
	    debug sprintf("Got %d arcs in %2.2f secs",
			  $num_of_arcs, time - $ts);
	}

	my $cnt = 0;
	my $ts = time;

	my $rowcount = $sth_init_obj_pred->rows;
	if( $rowcount > 100 )
	{
	    debug "initiate_revprop $node->{id} $name";
	    debug "Populating $rowcount arcs";
	    debug "ARGS: ".query_desig($args);
	}

	foreach my $rec ( @$recs )
	{
	    $node->populate_rev( $rec, $args );

	    # Handle long lists
	    unless( ++$cnt % 100 )
	    {
		debug "Populated $cnt";
		$Para::Frame::REQ->may_yield;
		die "cancelled" if $Para::Frame::REQ->cancelled;
	    }
	}

	debug 3, "* revprop $name for $node->{id} is now initiated";
    }
    else
    {
	debug "* revprop $name does not exist!";
    }

    unless( $extralim )
    {
	if( $active )
	{
	    $node->{'initiated_revprop'}{$name} = 2;
	}
    }

    # Keeps key nonexistent if nonexistent
    if( $active and not $inactive )
    {
	return $node->{'revarc'}{ $name };
    }
    elsif( $inactive and not $active )
    {
	return $node->{'revarc_inactive'}{ $name };
    }
    else
    {
	return $node->{'revarc'}{ $name } ||
	  $node->{'revarc_inactive'}{ $name };
    }
}

#########################################################################

=head2 populate_rel

Insert data from a rel record into node

=cut

sub populate_rel
{
    my( $node, $rec ) = @_;

    my $class = ref($node);

    # Oh, yeah? Like I care?!?
    my $pred_name = Rit::Base::Pred->get( $rec->{'pred'} )->plain;
#    debug "Populating node $node->{id} prop $pred_name"; ### DEBUG
    if( $rec->{'active'} and (($node->{'initiated_relprop'}{$pred_name} ||= 1) > 1))
    {
	debug 4, "NOT creating arc";
	return;
    }

#    debug "Creating arc for $node with $rec";
    my $arc = Rit::Base::Arc->get_by_rec_and_register( $rec, $node );
#    debug "  Created";

#    debug "**Add prop $pred_name to $node->{id}";

    return 1;
}

#########################################################################

=head2 populate_rev

Insert data from a rev record into node

=cut

sub populate_rev
{
    my( $node, $rec ) = @_;

    my $class = ref($node);

    # Oh, yeah? Like I care?!?
    debug 3, timediff("populate_rev");
    my $pred_name = Rit::Base::Pred->get( $rec->{'pred'} )->plain;
    if( $rec->{'active'} and (($node->{'initiated_revprop'}{$pred_name} ||= 1) > 1))
    {
	debug 4, "NOT creating arc";
	return;
    }

    if( debug > 3 )
    {
	debug "Creating arc for $node->{id} with ".datadump($rec,4);
#	debug timediff("new arc");
    }
    my $arc = Rit::Base::Arc->get_by_rec_and_register( $rec, undef, $node );
    if( debug > 3 )
    {
	debug "  Created";
	debug "**Add revprop $pred_name to $node->{id}";
	debug timediff("done");
    }

    return 1;
}


#########################################################################

=head2 resolve_obj_id

Same as get_by_anything, but returns the node id

=cut

sub resolve_obj_id
{
    return map $_->id, shift->get_by_anything( @_ );
}

#########################################################################

=head2 dereference_nesting

=cut

sub dereference_nesting
{
    my( $node ) = @_;

    die "not implemented";
}

#########################################################################

=head2 set_arc

Called for literal resources. Ignored here but active for literal nodes

=cut

sub set_arc
{
    return $_[1]; # return the arc
}


#########################################################################

=head2 session_history_add

=cut

sub session_history_add
{
    my( $node, $table ) = @_;
    $table ||= 'visited';
    my $list = $Para::Frame::REQ->session->{'nodes'}{$table}
      ||= Rit::Base::List->new();
    $list->unshift_uniq($node);
    return $list;
}


#########################################################################

=head2 coltype

  $node->coltype()

C<$node> must be a class (used as a range of a predicate).

Literal classes handled by L<Rit::Base::Literal::Class>. All other are
coltype C<obj>.

returns: the plain string of table column name

See also: L<Rit::Base::Pred/coltype>, L<Rit::Base::Arc/coltype>,
L<Rit::Base::Literal::Class/coltype>

TODO: Move this to L<Rit::Base::Resource::Class>

=cut

sub coltype
{
    return 'obj';
}


#########################################################################

=head2 coltype_id

  $node->coltype_id()

C<$node> must be a class (used as a range of a predicate).

Literal classes handled by L<Rit::Base::Literal::Class>. All other are
coltype C<obj>.

returns: the id of table column

See also: L<Rit::Base::Pred/coltype>, L<Rit::Base::Arc/coltype>,
L<Rit::Base::Literal::Class/coltype>

TODO: Move this to L<Rit::Base::Resource::Class>

=cut

sub coltype_id
{
    return 1;
}


#########################################################################

=head2 this_valtype

  $node->this_valtype( \%args )

This would be the same as the C<is> property of this resource. But it
must only have ONE value. It's important for literal values.

This method will return the literal valtype for value resoruces and
return the C<resource> resource for other resources.

See also: L<Rit::Base::Literal/this_valtype>, L</is_value_node>.

=cut

sub this_valtype
{
    my( $node, $args_in ) = @_;

    if( my $arc = $_[0]->first_arc('value',undef, $args_in) )
    {
	return $arc->valtype;
    }
    else
    {
	return Rit::Base::Resource->get_by_label('resource');
    }
}


#########################################################################

=head2 this_coltype

  $node->this_coltype()

This is a resource. It has tha C<obj> coltype.

returns: the plain string of table column name

See also: L<Rit::Base::Literal/this_coltype>

=cut

sub this_coltype
{
    return 'obj';
}


#########################################################################

=head2 instance_class

  $node->instance_class

Compatible with L<Rit::Base::Literal::Class/instance_class>. This will
return the class in the same manner as L</find_class>, as given by
C<class_handled_by_perl_module> and defaults to
C<Rit::Base::Resource>. Even for value resources.

TODO: make value resources literal objects

=cut

sub instance_class
{
    my $package = 'Rit::Base::Resource';

    # Maby a small optimization
    my $p_chbpm = Rit::Base::Pred->
      get_by_label('class_handled_by_perl_module');

    if( my $class_node = $_[0]->first_prop($p_chbpm) )
    {
	eval
	{
	    # Mirrors find_class()
	    my $key = $class_node->id;
	    if( $package = $Rit::Base::Cache::Class{ $key } )
	    {
		return $package;
	    }

	    my $p_code = Rit::Base::Pred->get_by_label('code');
	    my $classname = $class_node->first_prop($p_code)->plain
	      or confess "No classname found for class $class_node->{id}";

	    require(package_to_module($classname));

	    $package = "Rit::Base::Metaclass::$classname";
	    no strict "refs";
	    @{"${package}::ISA"} = ($classname, "Rit::Base::Resource");
	    $Rit::Base::Cache::Class{ $key } = $package;
	    1;
	};
	if( $@ )
	{
	    debug $@;
	    $package = 'Rit::Base::Resource';
	}
    }

    return $package;
}


#########################################################################
################################ misc functions #########################

=head1 Functions

=cut

#########################################################################

=head2 handle_query_newsubjs

  handle_query_newsubjs( $q, $param, \%args )

Return number of changes

=cut

sub handle_query_newsubjs
{
    my( $q, $newsubj_params, $args ) = @_;

    $args ||= {};
    my $res = $args->{'res'} ||= Rit::Base::Resource::Change->new;
    my $changes_prev = $res->changes;

    my %newsubj;
    my %keysubjs;

    foreach my $param (@$newsubj_params)
    {
	my $arg = parse_form_field_prop($param);

	#debug "Newsubj param: $param: ". $q->param($param);
	if( $arg->{'newsubj'} =~ m/^(main_)?(.*?)$/ )
	{
	    next unless $q->param( $param );
	    my $main = $1;
	    my $no = $2;

	    $keysubjs{$no} = 'True'
	      if( $main );
	    debug " adding $no"
	      if( $main );

	    $newsubj{$no} = {} unless $newsubj{$no};
	    $newsubj{$no}{$arg->{'pred'}} = $q->param( $param );

	    # Cleaning up newsubj-params to get a clean form...
	    $q->delete($param);
	}
    }

    foreach my $ns (keys %keysubjs)
    {
	debug "Newsubj creating a node: ". datadump $newsubj{$ns};
	Rit::Base::Resource->create( $newsubj{$ns}, $args );
    }

    return $res->changes - $changes_prev;
}

#########################################################################

=head2 timediff

=cut

sub timediff
{
    my $ts = $Rit::Base::timestamp || time;
    $Rit::Base::timestamp = time;
    return sprintf "%20s: %2.2f\n", $_[0], time - $ts;
}


#########################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>,
L<Rit::Base::Literal::Time>

=cut
