#  $Id$  -*-cperl-*-
package Rit::Base::Resource;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Resource

=cut

use Carp qw( cluck confess croak carp shortmess );
use strict;
use vars qw($AUTOLOAD);
use Time::HiRes qw( time );
use LWP::Simple (); # Do not import get
use Template::PopupTreeSelect 0.9;


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
use Rit::Base::Arc;
use Rit::Base::Literal;
use Rit::Base::Time qw( now );
use Rit::Base::Pred;
use Rit::Base::Metaclass;
#use Rit::Base::Constants qw( );

use Rit::Base::Utils qw( cache_sync valclean translate getnode getarc
			 getpred parse_query_props cache_update
			 parse_form_field_prop is_undef arc_lock
			 arc_unlock truncstring
			 convert_query_prop_for_creation );

### Inherit
#
use base qw( Rit::Base::Node Rit::Base::Resource::Compatible );

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

  $n->get( $id )

  $n->get( $anything )

get() is the central method for getting things.  It expects node id,
but also takes labels and searches.  It will call L</new> and
L</init>.  Anything other than id is given to L</get_by_label>.  Those
methods are reimplemented in the subclasses.  L</new> must only take
the node id.  L</get_by_label> must take any form of identification,
but expects and returns only ONE node.  The coresponding
L</find_by_label> returns a List.

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

Returns:

a node object

Exceptions:

See L</get_by_label> then called with anything but $id

=cut

sub get
{
    my( $this, $id ) = @_;
    my $class = ref($this) || $this;

    return undef unless $id;
    my $node;

#    debug "Getting $id ($class)";

    # Get the resource id
    #
    if( $id !~ /^\d+$/ )
    {
	if( ref $id and UNIVERSAL::isa($id, 'Rit::Base::Resource::Compatible') )
	{
	    # This already is a (node?) obj
#	    debug "Got     $id";
	    return $id;
	}

	my $resolved_id;
	# $id could be a hashref, but those are not chached
	unless( $resolved_id = $Rit::Base::Cache::Label{$class}{ $id } )
	{
	    $node = $class->get_by_label( $id ) or return is_undef;
	    my $resolved_id = $node->id;

	    # Cache name lookups
	    unless( ref $id ) # Do not cache searches
	    {
		$Rit::Base::Cache::Label{$class}{ $id } = $resolved_id;
		$node->{'lables'}{$class}{$id} ++;
	    }

	    # Cache id lookups
	    #
#	    debug "Got    $id: Caching node $resolved_id: $node";
	    $Rit::Base::Cache::Resource{ $resolved_id } = $node;

	    return $node;
	}
	$id = $resolved_id;
    }


    # Is the resource cached?
    #
    if( $node = $Rit::Base::Cache::Resource{ $id } )
    {
#	debug "Got     $id from Resource cache: $node";
	return $node;
    }

    $node = $class->new( $id );
    # The node will be cached by the new()

    $node->first_bless;

#    debug "Got     $id ($node)";

    return $node;
}


#######################################################################

=head2 get_by_rec

  $n->get_by_rec( $rec, @extra )

Returns: a node

Exceptions: see L</init>.

=cut

sub get_by_rec
{
    my $this = shift;

    my $id = $_[0]->{id} or
      croak "get_by_rec misses the id param: ".datadump($_[0],2);
    return $Rit::Base::Cache::Resource{$id} || $this->new($id)->init(@_);
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

=head2 find_by_label

  1. $n->find_by_label( $node, $datatype )

  2. $n->find_by_label( $query, $datatype )

  3. $n->find_by_label( "$any_name ($props)", $datatype )

  4. $n->find_by_label( "$called ($predname)", $datatype )

  5. $n->find_by_label( "$id: $name", $datatype )

  6. $n->find_by_label( "#$id", $datatype )

  7. $n->find_by_label( $name, $datatype );

  8. $n->find_by_label( $id, $datatype );

  9. $n->find_by_label( $list );

C<$node> is a node object.

C<$query> is defined in L</find>.

In case C<3>, C<$any_name> is either name, name_short or code.
C<$props> is a list of criterions of the form "pred value" spearated
by comma, there the value is everything after the first space and
before the next comma or end of string.

In case C<4>, we can identify a node by the predicate of our choosing.
The node myst have a property C<$predname> with value C<$called>.

A C<$list> returns itself.

If C<$datatype> is defined and anyting other than C<obj>, the text
value is returned for cases C<7> and C<8>.  The other cases is provided for
supporting C<value> nodes.  This limits the possible content of a
literal string if this method is called with a string as value.

Returns:

a list of zero or more node objects

Exceptions:

validation : C<"$id: $name"> mismatch

See also L</find> if C<$query> or C<$props> is used.

=cut

sub find_by_label
{
    my( $this, $val, $coltype ) = @_;
    return is_undef unless defined $val;

    unless( ref $val )
    {
	trim(\$val);
    }

    my( @new );
    $coltype ||= 'obj';

#    debug 3, "find_by_label: $val ($coltype)";

    # obj as object
    #
    if( ref $val and UNIVERSAL::isa( $val, 'Rit::Base::Resource::Compatible') )
    {
	debug 3, "  obj as object";
	push @new, $val;
    }
    #
    # obj as subquery
    #
    elsif( ref $val and ref $val eq 'HASH' )
    {
	debug 3, "  obj as subquery";
	debug "    query: ".datadump($val,4) if debug > 3;
	my $objs = $this->find($val);
	unless( $objs->size )
	{
	    return is_undef;
	}

	push @new, $objs->as_array;
    }
    #
    # obj is not an obj.  Looking at coltype
    #
    elsif( $coltype ne 'obj' )
    {
	debug 3, "  obj as not an obj, It's a $coltype";
	if( not ref $val )
	{
	    if( $coltype eq 'valtext' or
		$coltype eq 'valint'  or
		$coltype eq 'valfloat' )
	    {
		$val = Rit::Base::String->new( $val );
	    }
	    elsif( $coltype eq 'valdate' )
	    {
		$val = Rit::Base::Time->get( $val );
	    }
	    else
	    {
		confess "not implemented; coltype $coltype. Value $val";
	    }
	}
	elsif( ( $coltype eq 'valtext' or
		 $coltype eq 'valint'  or
		 $coltype eq 'valfloat'
		 ) and
	       ( ref $val eq 'Rit::Base::String' or
		 ref $val eq 'Rit::Base::Undef'
	       ))
	{
	    # OK
	}
	elsif( $coltype eq 'valdate' )
	{
	    $val = Rit::Base::Time->get($val);
	}
	else
	{
	    confess "Value should be of $coltype type but is: $val";
	}

	push @new, $val;
    }
    #
    # obj as list
    #
    elsif( ref $val and UNIVERSAL::isa( $val, 'Rit::Base::List') )
    {
	debug 3, "  obj as list";
	push @new, $val;
    }
    #
    # obj as name of obj with criterions
    #
    elsif( $val =~ /^\s*(.*?)\s*\(\s*(.*?)\s*\)\s*$/ )
    {
	debug 3, "  obj as name of obj with criterions";
	my $name = $1; #(trimmed)
	my $spec = $2; #(trimmed)
	my $objs;
	if( $spec !~ /\s/ ) # just one word
	{
	    debug 3, "    Finding nodes with $spec = $name";
	    $objs = $this->find({$spec => $name});
	}
	else
	{
	    my $props = parse_query_props( $spec );
	    $props->{'predor_name_-_code_-_name_short_clean'} = $name;
	    debug "    Constructing props for find: ".datadump($props,4)
	      if debug > 3;
	    $objs = $this->find($props);
	}

	unless( $objs->size )
	{
	    croak "No obj with name '$val' found\n";
	    return is_undef;
	}

	push @new, $objs->as_array;
    }
    #
    # obj as obj id and name
    #
    elsif( $val =~ /^(\d+):\s*(.*?)\s*$/ )
    {
	debug 3, "  obj as obj id and name";
	my $id = $1;
	my $name = $2;

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
		throw('validation', "id/name mismatch.\nid $id is called '$desig'");
	    }
	}
	push @new, $obj;
    }
    #
    # obj as obj id with prefix '#'
    #
    elsif( $val =~ /^#(\d+)$/ )
    {
	debug 3, "  obj as obj id with prefix '#'";
	my $id = $1;
	my $obj = $this->get( $id );
	push @new, $obj;
    }
    #
    # no value
    #
    elsif( not length $val )
    {
	# Keep @new empty
    }
    #
    # obj as name of obj
    #
    elsif( $val !~ /^\d+$/ )
    {
	debug 3, "  obj as name of obj";
	# TODO: Handle empty $val

	# Used to use find_simple.  But this is a general find
	# function and can not assume the simple case

	@new = $this->find({ name_clean => $val })->as_array;
    }
    #
    # obj as obj id
    #
    else
    {
	debug 3, "  obj as obj id";
	push @new, $this->get_by_id( $val );
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
    my( $this, $label ) = @_;
    my $class = ref($this) || $this;

    return undef unless defined $label;
    my $id;
    unless( $id = $Rit::Base::Cache::Label{$class}{ $label } )
    {
	my $node = $class->get_by_label( $label ) or return is_undef;
	$id = $node->id;
	# Cache name lookups
	unless( ref $label ) # Do not cache searches
	{
	    $Rit::Base::Cache::Label{$class}{ $label } = $id;
	    $node->{'lables'}{$class}{$label} ++;
	}
    }
    return $id;
}


#######################################################################

=head2 find

  $class->find( $query )

  $node->find( $query )

  $list->find( $query )

  $node->find( $pred => $value )

  $node->find( $name )

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
    my( $this, $tmpl, $default ) = @_;

    # TODO: set priority by number of values of specific type
#    warn timediff("find");

    unless( ref $tmpl )
    {
	if( defined $default )
	{
	    $tmpl = { $tmpl => $default };
	}
	else
	{
	    $tmpl = { 'name' => $tmpl };
	}
	$default = undef;
    }

    ## Default attrs
    $default ||= {};
    foreach my $key ( keys %$default )
    {
	$tmpl->{$key} ||= $default->{$key};
    }

    if( ref $this )
    {
	if( UNIVERSAL::isa($this, 'Rit::Base::Resource::Compatible') )
	{
	    $this = Rit::Base::List->new([$this]);
	}

	if( UNIVERSAL::isa($this, 'Rit::Base::List') )
	{
	    return $this->find($tmpl);
	}
    }
    my $class = ref($this) || $this;

    my $search = Rit::Base::Search->new({maxlimit =>
					 Rit::Base::Search::TOPLIMIT});
    $search->modify($tmpl);
    $search->execute();

    my $result = $search->result;
    $result->set_type($class);
    return $result;
}


#######################################################################

=head2 find_simple

  $class->find_simple( $pred, $value )

  $node->find( $pred, $value )

Searches all nodes for those having the property with pred C<$pred>
and text C<$value>.

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

    my $pred = Rit::Base::Pred->get( $pred_in );
    my $pred_id = $pred->id;

    my $value = valclean($value_in);
    my $list = $Rit::Base::Cache::find_simple{$pred_id}{$value};
    unless( defined $list ) # Avoid using list overload
    {
	my @nodes;
	my $st = "select sub from rel where pred=? and valclean=?";
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

Does a L</find>, but excpect to fins just one.

If more than one match is found, tries one more time to find exact
matchas.

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
    my( $this, $props ) = @_;

    my $nodes = $this->find( $props )->as_arrayref;

    if( $nodes->[1] )
    {
	debug "Found more than one match";

	# Look for an exact match
	debug "Trying to exclude some matches";
	my $new_nodes = $nodes->find($props);

	# Go with the original search result if te exclusion excluded all matches
	unless( $new_nodes->[0] )
	{
	    $new_nodes = $nodes;
	}

	if( $new_nodes->[1] )
	{
	    # TODO: Explain 'kriterierna'

	    my $result = $Para::Frame::REQ->result;
	    $result->{'info'}{'alternatives'}{'alts'} = $nodes;
	    $result->{'info'}{'alternatives'}{'query'} = $props;
	    throw('alternatives', "Flera noder matchar kriterierna");
	}

	$nodes = $new_nodes;
    }

    unless( $nodes->[0] )
    {
	my $req = $Para::Frame::REQ;
	my $result = $req->result;
	$result->{'info'}{'alternatives'}{'alts'} = undef;
	$result->{'info'}{'alternatives'}{'query'} = $props;
	$result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	$req->set_error_response_path('/node_query_error.tt');
	throw('notfound', "No nodes matches query (1)");
    }

    return $nodes->[0];
}


#######################################################################

=head2 find_set

  $n->find_set( $query )

  $n->find_set( $query, $default )

Finds the nodes matching $query, as would L</find_one>.  But if no
node are found, one is created using the C<$query> and C<$default> as
properties.

Properties specified in C<$defult> is used unless corresponding
properties i C<$query> is defined.  The resulting properties are
passed to L</create>.

Returns:

a node

Exceptions:

alternatives : more than one nodes matches the criterions

See also L</find_one> and L</set_one>

See also L</find> and L</create>.

=cut

sub find_set  # Find the one matching node or create one
{
    my( $this, $props, $default ) = @_;

    # Do this here, since the values will be needed later here
    unless( ref $props eq 'HASH' )
    {
	$props = $props->plain if ref $props;
	if( defined $default )
	{
	    $props = { $props => $default };
	}
	else
	{
	    $props = { 'name' => $props };
	}
	$default = undef;
    }

    my $nodes = $this->find( $props )->as_arrayref;

    if( $nodes->[1] )
    {
	debug "Found more than one match";

	# Look for an exact match
	debug "Trying to exclude some matches";
	$nodes = $nodes->find($props); # looks in list

	if( $nodes->[1] )
	{
	    my $result = $Para::Frame::REQ->result;
	    $result->{'info'}{'alternatives'}{'alts'} = $nodes;
	    $result->{'info'}{'alternatives'}{'query'} = $props;
	    throw('alternatives', "Flera noder matchar kriterierna");
	}
    }

    my $node = $nodes->[0];
    unless( $node )
    {
	$default ||= {};
	my $props_new = convert_query_prop_for_creation($props);
	foreach my $pred ( keys %$default )
	{
	    $props_new->{$pred} ||= $default->{$pred};
	}
	return $this->create($props_new);
    }

    return $node;
}


#######################################################################

=head2 set_one

  $n->set_one( $query )

  $n->set_one( $query, $default )

Just as L</find_set>, but merges all found nodes to one, if more than
one is found.

If a merging occures, one node is selected.  All
L<explicit|Rit::Base::Arc/explicit> arcs going to and from
the other nodes are copied to the selected node and then removed from the
other nodes.

Returns:

a node

Exceptions:

See L</find> and L</create>.

See also L</find_set> and L</find_one>

=cut

sub set_one  # get/set the one node matching. Merge if necessery
{
    my( $this, $props_in, $default ) = @_;


    my $nodes = $this->find( $props_in );
    my $node = $nodes->get_first_nos;

    while( my $enode = $nodes->get_next_nos )
    {
	$enode->merge($node,1); # also move literals
    }

    unless( $node )
    {
	my $props = convert_query_prop_for_creation($props_in);

	$default ||= {};
	foreach my $pred ( keys %$default )
	{
	    $props->{$pred} ||= $default->{$pred};
	}
	return $this->create($props);
    }

    return $node;
}


#######################################################################

=head2 create

  $n->create( $props )

Creates a node with the specified props.

C<$props> is a hashref there the keys are the predicate names and the
value is either a node or a array(ref) of nodes or a
L<List|Rit::Base::List> of nodes.  And the nodes can be given
as anything that L</get> will accept.

Returns:

a node

Exceptions:

See L</get>.

=cut

sub create
{
    my( $this, $props ) = @_;

    my $subj_id = $Rit::dbix->get_nextval('node_seq');

    # Any value props should be added after datatype props
    my @props_list;
    if( defined $props->{'value'} )
    {
	@props_list =  grep{ $_ ne 'value'} keys(%$props);
	push @props_list, 'value';
    }
    else
    {
	@props_list =  keys(%$props);
    }

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

	if( $pred_name =~ /^rev_(.*)$/ )
	{
	    $pred_name = $1;

	    foreach my $val ( $vals->as_array )
	    {
		Rit::Base::Arc->create({
		    subj    => $val,
		    pred    => $pred_name,
		    obj_id  => $subj_id,
		});
	    }
	}
	elsif( $pred_name =~ /^adr_(.*)$/ and $vals->size )
	{
	    # TODO: generalize this!
	    $adr ||= {};
	    $adr->{ $1 } = $vals;
	    debug 3, "Defining address data $1";
	}
	else
	{
	    foreach my $val ( $vals->as_array )
	    {
		Rit::Base::Arc->create({
		    subj_id => $subj_id,
		    pred    => $pred_name,
		    value   => $val,
		});
	    }
	}
    }

    my $node = Rit::Base::Resource->get( $subj_id );

    if( $adr ) # Set the address data of the node
    {
	# TODO: generalize this!
	$node->update_adr( $adr );
    }

    arc_unlock;

    return $node;
}


#######################################################################

=head2 create_if_unique

  $n->create_if_unique( $props )

Creates a node with the specified props, if its unique

Same as C<$n->create> except that it checks if some key params are
unique. If the test passes, the node will be created.

The tests will be bypassed if the property C<checked> is true.

=cut

sub create_if_unique
{
    my( $this, $props ) = @_;

    if( $props->{'checked'} )
    {
	delete $props->{'checked'};
    }
    else
    {
	foreach my $pred_name ('name', 'telephone', 'facsimile', 'url_main', 'email_main')
	{
	    if( my $val = $props->{$pred_name} )
	    {
		next unless $val;
		die "not implemented" if ref $val;

		my $list = $this->find({$pred_name => $val });
		if( $list->size )
		{
		    # A duplicate was found. But ignore that if ...


		    my $val_other = $list->get_first_nos->sysdesig;
		    throw('validation', "\u$pred_name are the same as $val_other");
		}
	    }
	}
    }

    return $this->create( $props );
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
	$path = "rb/node/translation/node.tt";
    }
    else
    {
	if( my $path_node = $n->is->class_form_url->get_first )
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

The unique node id.

=cut

sub id { $_[0]->{'id'} }


#######################################################################

=head2 score

Used by L<Rit::Base::Seach> class.

Default: 0

TODO: Remove

=cut

sub score { $_[0]->{'score'}||0 } ## Used by Seach class


#######################################################################

=head2 random

  $n->random

Used by L<Rit::Base::Seach> class.  Must be set by some other
method.

Default: 0

TODO: Remove

=cut

sub random { $_[0]->{'random'}||0 } ## Used by Seach class


#######################################################################

=head2 is_resource

  $n->is_resource

Returns true.

=cut

sub is_resource { 1 };


#######################################################################

=head2 is_value_node

  $n->is_value_node

Returns true if this node is a Literal Resource (aka value node).

Returns: boolean

=cut

sub is_value_node
{
    if( $_[0]->first_prop('value') )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}


#######################################################################

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


#######################################################################

=head2 list

  $n->list

Retuns a ref to a list of all property names. Also availible as
L</list_preds>.

  $n->list( $predname )

Returns a L<Rit::Base::List> of all values of the propertis
whith the preicate C<$predname>.

  $n->list( $predname, $value );

Returns C<true> if $value is not a hash and no more params exist, and
this node has a property with predicate C<$predname> and value
C<$value>.  This construct, that uses the corresponding feature in
L<Rit::Base::List/find>, enables you to say things like: C<if(
$item->is($C_city) )>

  $n->list( $predname, $proplim );

Returns a L<Rit::Base::List> of all values of the propertis
whith the preicate C<$predname>, those values has the properties
specified in C<$proplim>. A C<find()> is done on the list, using
C<$proplim>.

  $n->list( $predname, $proplim, 'direct' )

Same, but restrict list to values of
L<direct|Rit::Base::Arc/direct> property arcs.

  $n->list( $predname, $pred => $value )

Accepts proplim without {} for the simple case of only one criterion.

  $n->list( $predname, $pred => $value, 'direct' )

Same, but restrict list to values of
L<direct|Rit::Base::Arc/direct> property arcs.

Note that C<list> is a virtual method in L<Template>. Use it via
autoload in TT.

=cut

sub list
{
    my( $node, $name, $proplim, $arclim, $arclim2 ) = @_;

    if( $name )
    {
	if( ref $name eq 'Rit::Base::Pred' )
	{
	    confess "Now why did you go and do that?";
	    $name = $name->name;
	}

	my @arcs;
	if( $node->initiate_prop( $name ) )
	{
	    @arcs = @{ $node->{'relarc'}{$name} };
	}
	else
	{
	    debug 3, "No values for $node->{id} prop $name found!";
	}


	# Do *not* accept undef arclim, for this construct
	if( $proplim and not ref $proplim and $arclim )
	{
	    $proplim = { $proplim => $arclim };
	    $arclim = $arclim2;
	}

	if( $arclim )
	{
	    if( $arclim eq 'direct' )
	    {
		@arcs = grep $_->direct, @arcs;
	    }
	    elsif( $arclim eq 'explicit' )
	    {
		@arcs = grep $_->explicit, @arcs;
	    }
	    elsif( $arclim eq 'not_disregarded' )
	    {
		@arcs = grep $_->not_disregarded, @arcs;
	    }
	    else
	    {
		confess "not implemented: ".datadump($arclim);
	    }
	}

        my $vals = Rit::Base::List->new([ map $_->value, @arcs ]);

	if( $proplim )
	{
	    $vals = $vals->find($proplim);
	}
	return $vals;
    }
    else
    {
	return $node->list_preds;
    }
}


#######################################################################

=head2 list_preds

  $n->list_preds

The same as L</list> with no args.

Retuns: a ref to a list of all property names.

=cut

sub list_preds
{
    my( $node ) = @_;
    $node->initiate_rel;
    return Rit::Base::List->new([map Rit::Base::Pred->get_by_label($_), keys %{$node->{'relarc'}}]);
}


#######################################################################

=head2 revlist

  $n->revlist

Retuns a ref to a list of all reverse property names. Also availible as
L</revlist_preds>.

  $n->revlist( $predname )

Returns a L<Rit::Base::List> of all values of the reverse
propertis whith the predicate C<$predname>.

  $n->revlist( $predname, 'direct' )

Same, but restrict list to values of
L<direct|Rit::Base::Arc/direct> reverse property arcs.

=cut

sub revlist
{
    my( $node, $name, $proplim, $arclim ) = @_;

    # Gives a List of nodes for rev property $name
    # Without $name: returns a list of rev property names

    if( debug > 2 )
    {
	my $arclim_str = $arclim || "";
	my $proplim_str = $proplim || "";
	debug "Revlist $name for $node->{id} with $proplim and $arclim";
    }

    if( $name )
    {
	$name = $name->name if ref $name eq 'Rit::Base::Pred';

	my @arcs;
	if( $node->initiate_revprop( $name ) )
	{
	    @arcs = @{ $node->{'revarc'}{$name} };
	}
	else
	{
	    debug 3, "  No values for revprop $name found!";
	}

	if( $arclim )
	{
	    if( $arclim eq 'direct' )
	    {
		@arcs = grep $_->direct, @arcs;
	    }
	    elsif( $arclim eq 'explicit' )
	    {
		@arcs = grep $_->explicit, @arcs;
	    }
	    else
	    {
		die "not implemented: $arclim";
	    }
	}

	my $vals = Rit::Base::List->new([ map $_->subj, @arcs ]);

	debug "VALS IS NOW: ".datadump($vals,4)
	  if debug > 3;

	if( $proplim )
	{
	    $vals = $vals->find($proplim);
	}
	return $vals;
    }
    else
    {
	return $node->revlist_preds;
    }
}


#######################################################################

=head2 revlist_preds

  $n->revlist_preds

The same as L</revlist> with no args.

Retuns: a ref to a list of all reverse property names.

=cut

sub revlist_preds
{
    my( $node ) = @_;
    $node->initiate_rev;
    return Rit::Base::List->new([map Rit::Base::Pred->get_by_label($_), keys %{$node->{'revarc'}}]);
}


#######################################################################

=head2 prop

  $n->prop( $predname )

  $n->prop( $predname, $query )

Returns the values of the property with predicate C<$predname>.  If
C<$query> is given, restritcts the result to the matching nodes, using
L</find>.

Use L</first_prop> or L</list> instead if that's what you want!

Returns:

If more then one node found, returns a L<Rit::Base::List>.

If one node found, returns the node.

In no nodes found, returns C<undef>.

=cut

sub prop
{
    my( $node, $name, $proplim, $arclim ) = @_;

    $name or confess "No name param given";
    return  $node->id if $name eq 'id';

    debug 3, "!!! get ".$node->id."-> $name";

    if( 0 )### DEBUG
    {
	cluck;
	if( $Rit::tmpcount ++ > 100 )
	{
	    confess;
	}
    }

    confess "WRONG" if $name eq 'loc';
    confess "WRONG" if $name eq 'subj';

    $node->initiate_prop( $name );
    my $values = $node->list($name, $proplim, $arclim);

    if( $values->size > 1 ) # More than one element
    {
#	debug 3, "=== Ret ".$node->id."-> $name: (List with ".(scalar @$values)." nodes)";
	return $values;  # Returns list
    }
    else
    {
	# Return Resource, or undef if no such element
	if( debug > 2 )
	{
	    if( debug > 4 )
	    {
		debug "=== Ret ".$node->id."-> $name: ".datadump($values->[0], 2);
	    }
	    else
	    {
		debug "=== Ret ".$node->id."-> $name: ".($values->[0]||'<undef>');
	    }
	}

	if( $values->size )
	{
	    return $values->get_first_nos;
	}
	else
	{
	    return is_undef;
	}
    }
}


#######################################################################

=head2 revprop

  $n->revprop( $predname )

  $n->revprop( $predname, $query )

Returns the values of the reverse property with predicate
C<$predname>.  If C<$query> is given, restritcts the result to the
matching nodes, using L</find>.

Returns:

If more then one node found, returns a L<Rit::Base::List>.

If one node found, returns the node.

In no nodes found, returns C<undef>.

=cut

sub revprop     # Get first value or the list.
{
    my( $node, $name, $proplim, $arclim ) = @_;
    #
    # Use first_revprop() or list() explicitly if that's what you want!

    $node->initiate_revprop( $name );

    my $values = $node->revlist($name, $proplim, $arclim);

    if( $values->size > 1 ) # More than one element
    {
	return $values;  # Returns list
    }
    else
    {
	# Return Resource, or undef if no such element
	if( $values->size )
	{
	    return $values->get_first_nos;
	}
	else
	{
	    return is_undef;
	}
    }
}


#######################################################################

=head2 first_prop

  $n->first_prop( $pred_name )

Returns the value of one of the properties with predicate C<$pred_name>

=cut

sub first_prop    # Just get first value
{
    # TODO: We should make sure that if a relarc key exists, that the
    # list never is empty

    my( $node, $name ) = @_;
    $node->initiate_prop( $name );
    return is_undef unless defined $node->{'relarc'}{$name};
    $node->{'relarc'}{$name}[0] or confess "Empty list for $name in ".$node->id;
    return $node->{'relarc'}{$name}[0]->value;
}


#######################################################################

=head2 first_revprop

  $n->first_revprop( $pred_name )

Returns the value of one of the reverse properties with predicate
C<$pred_name>

=cut

sub first_revprop    # Just get first value
{
    my( $node, $name ) = @_;
    $node->initiate_revprop( $name );
    return is_undef unless defined $node->{'revarc'}{$name};
    return $node->{'revarc'}{$name}[0]->subj;
}


#######################################################################

=head2 has_prop

Same as L</has_value>.

=cut

sub has_prop
{
    return shift->has_value(@_);
}


#######################################################################

=head2 has_pred

Return true if the node has at least one property with this predicate.
The return values makes this method usable as a filter.

Example:

  m.revlist('our_reference').has_pred('contact_next').sorted('contact_next')

Returns:

True: The node

False: is_undef

=cut

sub has_pred
{
    if( $_[0]->list($_[1])->size )
    {
	return $_[0];
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

=head2 has_revpred

The reverse of has_pred.  Return true if the node has at least one
reverse property with this predicate.

Returns:

True: The node

False: is_undef

=cut

sub has_revpred
{
    if( $_[0]->revlist($_[1])->size )
    {
	return $_[0];
    }
    else
    {
	return is_undef;
    }
}


#######################################################################

=head2 has_value

  $n->has_value( $pred, $value )

  $n->has_value({ $pred, $value })

Returns true if one of the node properties has a combination of any of
the properties and any of the values.

Predicate can be a name, object or array.  Value can be a list of
values or anything that L<Rit::Base::List/find> takes.

Examples:

See if node C<$n> has the name or short name 'olle' or a name (or short
name) that is an alias.

  $n->has_value( ['name','name_short'], ['olle', {is => 'alias'}] )

Returns:

If true, returns one of the relevant arcs.

If false, returns 0.  Not the undef object.

If it's a dynamic property (a method) returns -1, that is true.

TODO: Scalars (i.e strings) with properties not yet supported.

Consider $n->has_value('some_pred', is_undef)

=cut

sub has_value
{
    my( $node, $pred_name, $value ) = @_;

    $pred_name or confess;

    if( ref($pred_name) and ref($pred_name) eq 'HASH' )
    {
	( $pred_name, $value ) = each( %$pred_name );
    }

    my $pred;
    if( ref $pred_name )
    {
	if( UNIVERSAL::isa( $pred_name, 'Rit::Base::Literal') )
	{
	    $pred = $pred_name->literal;
	}
	elsif( ref $pred_name eq 'Rit::Base::Pred' )
	{
	    $pred = $pred_name;
	}
	elsif( ref $pred_name eq 'ARRAY' )
	{
	    # Either predicate can have the value
	    foreach my $pred ( @$pred_name )
	    {
		my $arc = $node->has_value( $pred, $value );
		return $arc if $arc;
	    }
	    return 0;
	}
	else
	{
	    die "has_value pred $pred_name not supported";
	}
    }
    else
    {
	$pred = Rit::Base::Pred->get( $pred_name );
    }

    $pred_name = $pred->name->plain;

    if( debug > 2 )
    {
	my $value_str = defined($value)?$value:"<undef>";
	debug "  Checking if node $node->{'id'} has $pred_name $value_str";
    }

### Should not be needed (and is wrong)
#    # Convert from name to sub query ***
#    if( not ref $value and $pred->coltype eq 'obj')
#    {
#	$value = { name => $value };
#    }

    # Sub query
    if( ref $value eq 'HASH' )
    {
	if( debug > 3 )
	{
	    debug "  Checking if ".$node->desig.
	      " has $pred_name with the props ".
		datadump($value,4);
	}

	foreach my $arc ( $node->arc_list($pred_name)->as_array )
	{
	    if( $arc->obj->find($value)->size )
	    {
		return $arc;
	    }
	}
	return 0;
    }

    # $value holds alternative values
    elsif( ref $value eq 'ARRAY' )
    {
	foreach my $val (@$value )
	{
	    my $arc = $node->has_value($pred_name, $val);
	    return $arc if $arc;
	}
	return 0;
    }


    # Check the dynamic properties (methods) for the node
    if( $node->can($pred_name) )
    {
	debug 3, "  check method $pred_name";
	return -1 if $node->$pred_name eq $value;
    }

    foreach my $arc ( $node->arc_list($pred_name)->as_array )
    {
	debug 3, "  check arc ".$arc->id;
	return $arc if $arc->value_equals( $value );
    }
    if( debug > 2 )
    {
	my $value_str = defined($value)?$value:"<undef>";
	debug "  no such value $value_str for ".$node->desig;
    }

    return 0;
}


#######################################################################

=head2 has_revprop

  $n->has_revprop( $pred_name, $subj)

The reverse of L</has_prop>, but this versin is more limited.

Takes only a predicate name.  $subj can be anything that L</equals>
takes.

Examples:

Check if the region C<$n> contains the city Göteborg.

  $n->has_revprop( 'in_region', { name => 'Göteborg', is => 'city' } )

=cut

sub has_revprop
{
    my ($node, $pred_name, $subj) = @_;

    foreach my $arc ( $node->revarc_list($pred_name)->as_array )
    {
	return 1 if $arc->subj->equals( $subj );
    }
    return 0;
}


#######################################################################

=head2 count

  $n->count( $pred )

  $n->count( $pred, $obj, $props ) # not implemented

Counts the number of prperties the node has with a specific property.

Examples:

This can be used in C<Rit::Base::List-E<gt>find()> by count_pred
pattern. Example from TT; select active (direct) subclasses that has
10 or more instances:

  [% nodes = node.revarc_list('scof').direct.subj.find(inactive_ne=1, rev_count_pred_is_gt = 9).as_list %]

=cut

sub count
{
    my ($node, $pred_name, $obj, $props ) = @_;

    $obj and throw('action',"count( \$pred, \$obj, \$props ) not implemented");
    my $pred_id = Rit::Base::Pred->get_id( $pred_name );

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare( "select count(id) as cnt from rel where pred=? and sub=?" );
    $sth->execute( $pred_id, $node->id );
    my( $cnt ) =  $sth->fetchrow_array;
    return $cnt;
}


#######################################################################

=head2 revcount

  $n->revcount( $pred )

  $n->revcount( $pred, $obj, $props ) # not implemented

Counts the number of prperties the node has with a specific property.

Examples:

This can be used in C<Rit::Base::List-E<gt>find()> by count_pred
pattern. Example from TT; select active (direct) subclasses that has
10 or more instances:

  [% nodes = node.revarc_list('scof').direct.subj.find(inactive_ne=1, rev_count_pred_is_gt = 9).as_list %]

=cut

sub revcount
{
    my ($node, $pred_name, $obj, $props ) = @_;

    $obj and throw('action',"revcount( \$pred, \$obj, \$props ) not implemented");
    my $pred_id = Rit::Base::Pred->get_id( $pred_name );

    my $dbh = $Rit::dbix->dbh;
    my $sth = $dbh->prepare( "select count(id) as cnt from rel where pred=? and obj=?" );
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
    my( $node ) = @_;

    return Rit::Base::Constants->get_by_id($node->id)->label;
}


#######################################################################

=head2 desig

  $n->desig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub desig  # The designation of obj, meant for human admins
{
    my( $node ) = @_;

    my $desig;

    if(    $node->name->defined       ){ $desig = $node->name         }
    elsif( $node->name_short->defined ){ $desig = $node->name_short   }
    elsif( $node->value->defined      ){ $desig = $node->value        }
    elsif( $node->code->defined       ){ $desig = $node->code         }
    else                               { $desig = $node->id           }

    $desig = $desig->loc if ref $desig; # Could be a Literal Resource

    return truncstring( \$desig );
}


#######################################################################

=head2 sysdesig

  $n->sysdesig()

The designation of an object, to be used for node administration or
debugging.  This version of desig indludes the node id.

=cut

sub sysdesig  # The designation of obj, including node id
{
    my( $node ) = @_;

    my $desig;

    if(    $node->name->defined       ){ $desig = $node->name         }
    elsif( $node->name_short->defined ){ $desig = $node->name_short   }
    elsif( $node->value->defined      ){ $desig = $node->value        }
    elsif( $node->code->defined       ){ $desig = $node->code         }
    else
    {
	return( $node->id );
    }

    $desig = $desig->loc if ref $desig; # Could be a Literal Resource

    return truncstring("$node->{'id'}: $desig");
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

=cut

sub literal
{
    my( $node ) = @_;

    if( UNIVERSAL::isa($node,'Para::Frame::List') )
    {
	croak "deprecated";

	return $node->loc;
    }

    debug "Turning node ".$node->{'id'}." to literal";
    return $node->desig;
}


#######################################################################

=head2 loc

  $n->loc()

Asking to translate this word.  But there is only one value.  This is
probably a lone literal resource.

Used by L<Rit::Base::List/loc>.

=cut

sub loc
{
    return shift->value->loc(@_);
}


#######################################################################

=head2 arc_list

  $n->arc_list( $pred_name )

  $n->arc_list()

Returns a L<Rit::Base::List> of the arcs that have C<$n> as
subj and C<$pred_anme> as predicate.

With no C<$pred_name>, all arcs from the node is returned.

=cut

sub arc_list
{
    my( $node, $name ) = @_;
    #
    # Return List of arcs with $name
    # Return all arcs if $name not given

    if( $name )
    {
	$name = $name->name if ref $name eq 'Rit::Base::Pred';
	$node->initiate_prop( $name );
 	my $lr = $node->{'relarc'}{$name} || [];
	return Rit::Base::List->new($lr);
    }
    else
    {
	$node->initiate_rel;
	my @arcs;
	foreach my $pred_name ( keys %{$node->{'relarc'}} )
	{
	    push @arcs, @{ $node->{'relarc'}{$pred_name} };
	}
	return Rit::Base::List->new(\@arcs);
    }
}


#######################################################################

=head2 revarc_list

  $n->revarc_list( $pred_name )

  $n->revarc_list()

Returns a L<Rit::Base::List> of the arcs that have C<$n> as
subj and C<$pred_anme> as predicate.

With no C<$pred_name>, all revarcs from the node is returned.

=cut

sub revarc_list
{
    my( $node, $name ) = @_;

    if( $name )
    {
	$name = $name->plain if ref $name;
	$node->initiate_revprop( $name );
	my $lr = $node->{'revarc'}{$name} || [];
	return Rit::Base::List->new($lr);
    }
    else
    {
	$node->initiate_rev;
	my @arcs;
	foreach my $pred_name ( keys %{$node->{'revarc'}} )
	{
	    push @arcs, @{ $node->{'revarc'}{$pred_name} };
	}
	return Rit::Base::List->new(\@arcs);
    }
}


#######################################################################

=head2 first_arc

  $n->first_arc( $pred_name )

Returns one of the arcs that have C<$n> as subj and C<$pred_anme> as
predicate.

=cut

sub first_arc
{
       my( $node, $name ) = @_;
       $node->initiate_prop( $name );
       return is_undef unless defined $node->{'relarc'}{$name};
       return $node->{'relarc'}{$name}[0] || is_undef;
}


#######################################################################

=head2 first_revarc

  $n->first_revarc( $pred_name )

Returns one of the arcs that have C<$n> as obj and C<$pred_anme> as
predicate.

=cut

sub first_revarc
{
       my( $node, $name ) = @_;
       $node->initiate_revprop( $name );
       return is_undef unless defined $node->{'revarc'}{$name};
       return $node->{'revarc'}{$name}[0] || is_undef;
}


#######################################################################

=head2 arc

  $n->arc( $pred_name )

As L</arc_list>, but returns the only value, if only one.  Else, it
returns an array ref to the list of values.

Use L</first_arc> or L</arc_list> explicitly if that's what you want!

=cut

sub arc
{
    my( $node, $name ) = @_;

    $node->initiate_prop( $name );

    my $arcs = $node->{'relarc'}{$name} || [];

    if( defined $arcs->[1] ) # More than one element
    {
	return Rit::Base::List->new($arcs);
    }
    else
    {
	# Return arc hash or undef
	if( defined $arcs->[0] )
	{
	    return $arcs->[0];
	}
	else
	{
	    return is_undef;
	}
    }
}


#######################################################################

=head2 revarc

  $n->revarc( $pred_name )

As L</revarc_list>, but returns the only value, if only one.  Else, it
returns an array ref to the list of values.

Use L</first_revarc> or L<revarc_list> explicitly if that's what you want!

=cut

sub revarc
{
    my( $node, $name ) = @_;
    #

    $node->initiate_revprop( $name );

    my $arcs = $node->{'revarc'}{$name} || [];

    if( defined $arcs->[1] ) # More than one element
    {
	return Rit::Base::List->new($arcs);
    }
    else
    {
	# Return arc hash or undef
	if( defined $arcs->[0] )
	{
	    return $arcs->[0];
	}
	else
	{
	    return is_undef;
	}
    }
}



#######################################################################

=head2 get_related_arc_by_id

  $n->get_related_arc_by_id($id)

Returns the arc registred in node, or L<Rit::Base::Undef>.

TODO: could as well get it wihout initiate whole node

=cut

sub get_related_arc_by_id
{
    my( $node, $arc_id ) = @_;

    $node->initiate_rel;
    return $node->{'arc_id'}{$arc_id} || is_undef;
}



#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

#######################################################################

=head2 add

  $n->add( $pred => $value )

  $n->add({ $pred1 => $value1, $pred2 => $value2, ... })

=cut

sub add
{
    my( $node, $props, $val ) = @_;

    # either name/value pairs in props, or one name/value
    unless( ref $props eq 'HASH' )
    {
	$props = $props->plain if ref $props;
	$props = {$props, $val};
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
	    });
	  }
    }
    return $node;
}


#######################################################################

=head2 update

  $n->update( \%props )

  $n->update( $pred => $value )

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

Returns:

The number of arcs created or removed.

Exceptions:

See L</replace>

=cut

sub update
{
    my( $node, $props, $val ) = @_;

    # Update specified props to their values

    # Does not update props not mentioned

    # either name/value pairs in props, or one name/value
    unless( ref $props eq 'HASH' )
    {
	$props = $props->plain if ref $props;
	$props = {$props => $val};
    }

    my $changes = 0;

    # - existing specified values is unchanged
    # - nonexisting specified values is created
    # - existing nonspecified values is removed

    my @arcs_old = ();

    # Start by listing all old values for removal
    foreach my $pred_name ( keys %$props )
    {
	my $old = $node->arc_list( $pred_name );
	push @arcs_old, $old->as_array;
    }

    $changes += $node->replace(\@arcs_old, $props);

    return $changes;
}


#######################################################################

=head2 replace

  $n->replace( \@arclist, \%props )

See L</update> for description of what is done.

But here we explicitly check against the given list of arcs.

Adds arcs with L<Rit::Base::Arc/create> and removes arcs with
L<Rit::Base::Arc/remove>.

The C<%props> are processed by L</construct_proplist> and C<@arclist>
are processed by L</find_arcs>.

We use valclean of the value syskey for a key for what strings to
replace.

Debug:

  3 = detailed info
  4 = more details

Returns:

The number of arcs created or removed.

=cut

sub replace
{
    my( $node, $oldarcs, $props ) = @_;

    # Determine new and old arcs

    # - existing specified arcs is unchanged
    # - nonexisting specified arcs is created
    # - existing nonspecified arcs is removed

    my( %del );

    $oldarcs = $node->find_arcs($oldarcs);
    $props   = $node->construct_proplist($props);

    debug "Normalized oldarcs ".($oldarcs->sysdesig)." and props ".datadump($props,4)
      if debug > 3;

    my $changes = 0;

    foreach my $arc ( $oldarcs->as_array )
    {
	my $val_str = valclean( $arc->value->syskey );

	debug 3, "    old val: $val_str (".$arc->value.")";
	$del{$val_str} = $arc;
    }

    # go through the new values and remove existing values from the
    # remove list and add nonexisting values to the add list

    foreach my $pred_name ( keys %$props )
    {
	debug 3, "  pred: $pred_name";
	my( %add );
	my $pred = Rit::Base::Pred->get( $pred_name );

	foreach my $val_in ( @{$props->{$pred_name}} )
	{
	    my $val  = Rit::Base::Resource->get_by_label( $val_in, $pred->coltype );

	    my $val_str = valclean( $val->syskey );

	    debug 3, "    new val: '$val_str' (".$val.")";

	    if( $del{$val_str} )
	    {
		debug 3, "    keep $val_str";
		delete $del{$val_str};
	    }
	    elsif( defined $val_str )
	    {
		debug 3, "    add  '$val_str'";
		$add{$val_str} = $val;
	    }
	    else
	    {
		debug 3, "    not add <undef>";
	    }
	}

	# By first adding new arcs, some of the arcs shedueld for
	# removal may become indirect (infered), and therefore not
	# removed

	foreach my $key ( keys %add )
	{
	    debug 3, "    now adding $key";
	    Rit::Base::Arc->create({
		subj => $node,
		pred => $pred,
		value => $add{$key},
	    }, \$changes );
	}
    }

    foreach my $key ( keys %del )
    {
	debug 3, "    now removing $key";
	$changes += $del{$key}->remove;
    }

    debug 3, "  -- done";
    return $changes;
}


#######################################################################

=head2 remove

  $n->remove

Removes the node with all arcs pointing to and from the node.

It does not do a recursive remove.  You will have to traverse the tree
by yourself.

TODO: Count the changes correctly

Returns: The number of arcs removed

=cut

sub remove
{
    my( $node ) = @_;

    my $changes = 0;


    # Remove value arcs before the corresponding datatype arc
    my( @arcs, $value_arc );
    my $pred_value_id = getpred('value')->id;

    foreach my $arc ( $node->arc_list->nodes )
    {
	if( $arc->pred->id == $pred_value_id )
	{
	    $value_arc = $arc;
	}
	else
	{
	    push @arcs, $arc;
	}
    }

    # Place it first
    unshift @arcs, $value_arc if $value_arc;


    foreach my $arc ( @arcs, $node->revarc_list->nodes )
    {
	$changes += $arc->remove;
    }

    # Remove from cache
    #
    delete $Rit::Base::Cache::Resource{ $node->id };

    return $changes;
}


#######################################################################

=head2 find_arcs

  $n->find_arcs( $pred => $value )

  $n->find_arcs( [ @crits ] )

C<@crits> can be a mixture of arcs, hashrefs or arc numbers. Hashrefs
holds pred/value pairs that is added as arcs.

Returns: A L<Rit::Base::List> of found L<Rit::Base::Arc>s

=cut

sub find_arcs
{
    my( $node, $crits, $extra ) = @_;

    # Returns the union of all results from each criterion

    if( ref $crits eq 'Rit::Base::Pred' )
    {
	$crits = $crits->plain if ref $crits;
    }

    if( not(ref $crits) and defined $extra )
    {
	$crits = { $crits => $extra };
    }

    unless( ref $crits and (ref $crits eq 'ARRAY' or
			   ref $crits eq 'Rit::Base::List' )
	  )
    {
	$crits = [$crits];
    }

    my $arcs = [];

    foreach my $crit ( @$crits )
    {
	if( ref $crit and UNIVERSAL::isa($crit, 'Rit::Base::Arc') )
	{
	    push @$arcs, $crit;
	}
	elsif( ref($crit) eq 'HASH' )
	{
	    foreach my $pred ( keys %$crit )
	    {
		my $val = $crit->{$pred};
		my $found = $node->arc_list($pred)->find(value=>$val);
		push @$arcs, $found->as_array if $found->size;
	    }
	}
	elsif( $crit =~ /^\d+$/ )
	{
	    push @$arcs, getarc($crit);
	}
	else
	{
	    die "not implemented".datadump($crits,4);
	}
    }

    if( debug > 3 )
    {
	debug "Finding arcs: ".datadump($crits,2);

	if( @$arcs )
	{
	    debug "Found values:";
	}
	else
	{
	    debug "Found no values";
	}

	foreach my $arc (@$arcs)
	{
	    debug "  ".$arc->sysdesig;
	}
    }

    return new Rit::Base::List $arcs;
}


#######################################################################

=head2 construct_proplist

  $n->construct_proplist(\%props)

Checks that the values has the right format. If a value is a hashref;
looks up an object with those properties using L</find_set>.

Used by L</replace>.

Returns:

the normalized hashref of props.

Exceptions:

confesses if a value is an object of an unknown class.

=cut

sub construct_proplist
{
    my( $node, $props_in ) = @_;

    my $props_out = {};

    foreach my $pred ( keys %$props_in )
    {
	# Not only objs
	my $vals = Para::Frame::List->new_any( $props_in->{$pred} );

	# Only those alternatives. Not other objects based on ARRAY,

	foreach my $val ( $vals->as_array )
	{
	    if( ref $val )
	    {
		if( ref $val eq 'HASH' )
		{
		    ## find_set node
		    $val = Rit::Base::Resource->find_set($val);
		}
		elsif( ref $val eq 'Rit::Base::Undef' )
		{
		    # OK
		}
		elsif( UNIVERSAL::isa($val, 'Rit::Base::Literal') )
		{
		    # OK
		}
		elsif( UNIVERSAL::isa($val, 'Rit::Base::Resource::Compatible') )
		{
		    # OK
		}
		else
		{
		    debug datadump($val,4) if debug > 2;
		    confess "Not implemented: ".ref($val);
		}
	    }
	    else
	    {
		$val = Rit::Base::Literal->new( $val );
	    }
	}

	$props_out->{$pred} = $vals;
    }

    return $props_out;
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
node. This search is done using L</find_simple> which dosnät handle
literal nodes.


=cut

sub equals
{
    my( $node, $node2 ) = @_;

    return 0 unless defined $node2;

    if( ref $node2 )
    {
	if( UNIVERSAL::isa $node2, 'Rit::Base::Resource::Compatible' )
	{
	    return( ($node->id == $node2->id) ? 1 : 0 );
	}
	elsif( ref $node2 eq 'HASH' )
	{
	    return Rit::Base::List->new([$node])->find($node2)->size;
	}
	elsif( ref $node2 eq 'Rit::Base::List' )
	{
	    foreach my $val ( $node2->as_array )
	    {
		return 1 if $node->equals($val);
	    }
	    return 0;
	}
	elsif( ref $node2 eq 'ARRAY' )
	{
	    foreach my $val (@$node2 )
	    {
		return 1 if $node->equals($val);
	    }
	    return 0;
	}
	elsif( ref $node2 eq 'Rit::Base::Undef' )
	{
	    return 0; # Resource is defined
	}
	elsif( ref $node2 and UNIVERSAL::isa($node2, 'Rit::Base::Literal') )
	{
	    $node2 = $node2->literal;
	}
	else
	{
	    die "not implemented: $node2";
	}
    }

    if( $node2 =~ /^\d+$/ )
    {
	return( ($node->id == $node2) ? 1 : 0 );
    }
    else
    {
	my $nodes = Rit::Base::Resource->find_simple( name => $node2 );
	return $node->equals( $nodes );
    }
}


#######################################################################

=head2 update_by_query

  $n->update_by_query

Overall plan:

update_by_query maps through all parameters in the current request.
It sorts into 4 groups, depending on what the parameter begins with:

 1. Add / update properties  (arc/prop)
 2. Complemnt those props with second order atributes (row)
 3. Check if some props should be removed (check)
 4. Add new resources (newsubj)

Returns: the number of changes

4. Add new resources

To create a new resource and add arcs to it, the parameters should be
in the format "newsubj_$key__pred_$pred", where $key is used to group
parameters together.  $key can be prefixed with "main_".  At least one
$key should have the main-prefix set for the new resource to be
created.  $pred can be prefixed with "rev_".

Example1: Adding a new node if certain values are set

 Params
 newsubj_main_contact__pred_contact_next => 2006-10-05
 newsubj_contact__pred_is => C.contact_info.id
 newsubj_contact__pred_rev_contact_info => org.id

...where 'contact' is the key for the newsubj, regarding all with the
same key as the same node.  A new resource is created IF at least one
main-parameter is supplied (no 1 above).  There can be several
main-parameters.  If no main-parameter is set, the other
newsubj-parameters with that number are ignored.


=comment

  Document all field props:

pred
revpred
arc
desig
type
scof
rowno
subj
newsubj
is

=cut

sub update_by_query
{
    my( $node ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $id = $node->id;
    $q->param('id', $id); # Just in case...


    # Sort params
    my @arc_params;
    my @row_params;
    my @check_params;
    my @newsubj_params;

    foreach my $param ($q->param)
    {
	if( $param =~ /^(arc|prop)_.*$/ )
	{
	    next if $q->param("check_$param"); #handled by check below
	    push @arc_params, $param;
	}
	elsif( $param =~ /^row_.*$/ )
	{
	    push @row_params, $param;
	}
	elsif( $param =~ /^check_(.*)/)
	{
	    push @check_params, $param;
	}
	elsif( $param =~ /^newsubj_.*$/ )
	{
	    push @newsubj_params, $param;
	}
    }

    my $row = {}; # Holds relating field info for row
    my $deathrow = {}; # arcs to remove
    my $changes = 0; # Actual things changed

    foreach my $param (@arc_params)
    {
	if( $param =~ /^arc_.*$/ )
	{
	    $changes += $node->handle_query_arc( $param, $row, $deathrow );
        }
	elsif($param =~ /^prop_(.*?)/) # Was previously only be used for locations
	{
	    $changes += $node->handle_query_prop( $param );
	}
    }

    foreach my $param (@row_params)
    {
	$changes += $node->handle_query_row( $param, $row, $deathrow );
    }

    foreach my $param (@check_params)
    {
	next unless $q->param( $param );

	### Remove all check_arc params that is ok. All check_arc
	### params left now represent arcs that should be removed

	# Check row is a copy of similar code above
	#
	if( $param =~ /^check_row_.*$/ )
	{
	    $changes += $node->handle_query_check_row( $param, $row );
	}
	elsif($param =~ /^check_arc_(.*)/)
        {
	    my $arc_id = $1 or next;
	    $changes += $node->handle_query_check_arc( $param, $arc_id, $deathrow );
        }
        elsif($param =~ /^check_prop_(.*)/)
        {
	    my $pred_name = $1;
	    $changes += $node->handle_query_check_prop( $param, $pred_name );
        }
        elsif($param =~ /^check_revprop_(.*)/)
        {
	    my $pred_name = $1;
	    $changes += $node->handle_query_check_revprop( $param, $pred_name );
        }
	elsif($param =~ /^check_node_(.*)/)
	{
	    my $node_id = $1 or next;
	    $changes += $node->handle_query_check_node( $param, $node_id );
	}
    }

    $changes += handle_query_newsubjs( $q, \@newsubj_params );

    # Remove arcs on deathrow
    #
    # Arcs on deathrow do not count during inference.
    foreach my $arc ( values %$deathrow )
    {
	debug 3, "Arc $arc->{id} on deathwatch";
	$arc->{'disregard'} ++;
    }

    foreach my $arc ( values %$deathrow )
    {
	########################################
	# Authenticate removal of arc
	#
	$node->authenticate_update( $arc->pred );

	$changes += $arc->remove;
    }

    foreach my $arc ( values %$deathrow )
    {
	# If they got removed, they will still have positive disregard
	# value
	$arc->{'disregard'} --;
	debug 3, "Arc $arc->{id} now at $arc->{'disregard'}";
    }



    # Complement query with request to update the timestamp of node change
    #
    if( $changes )
    {
	$node->update({ updated => now() });

	# We used to call cache_sync here. But do it later. Should
	# only save changes if no exceptions are introduced
    }

    # Clear out used query params
    # TODO: Also remove revprop_has_member ...
    foreach my $param ( @arc_params, @row_params, @check_params )
    {
	$q->delete( $param );
    }

    return $changes;
}


#######################################################################

=head2 vacuum

  $n->vacuum

Vacuums each arc of the resource

Returns: The node

=cut

sub vacuum
{
    my( $node ) = @_;

    foreach my $arc ( $node->arc_list->nodes )
    {
	$arc->remove_duplicates;
    }

    my $pred_name_list = $node->list;
    foreach my $pred_name ( $pred_name_list->as_array )
    {
	my $pred = getpred( $pred_name );
	debug( sprintf "vacuum --> Check %s\n", $pred->name->plain);
	my $coltype = $pred->coltype($node);

	if( $coltype eq 'obj' )
	{
	    foreach my $arc ( $node->arc_list( $pred_name )->as_array )
	    {
		$Para::Frame::REQ->may_yield;
		$arc->vacuum;
	    }
	}
    }
    return $node;
}


#######################################################################

=head2 add_note

  $n->add_note( $text )

Adds a C<note>

=cut

sub add_note
{
    my( $node, $note ) = @_;

    $note =~ s/\n+$//; # trim
    unless( length $note )
    {
	confess "No note given";
    }
    debug $node->desig.">> $note";
    $node->add('note', $note);
}


#######################################################################

=head2 merge

  $node1->merge($node2)

  $node1->merge($node2, $move_literals)

Copies all arcs from C<$node1> to C<$node2>. And remove the arcs from
C<$node1>.  Copies both arcs and reverse arcs.

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
    my( $node1, $node2, $move_literals ) = @_;

    if( $node1->equals( $node2 ) )
    {
	throw('validation', "You can't merge a node into itself");
    }

    debug sprintf("Merging %s with %s", $node1->sysdesig, $node2->sysdesig);

    foreach my $arc ( $node1->arc_list->explicit->nodes )
    {
	my $pred_name = $arc->pred->name->plain;
	if( my $obj = $arc->obj )
	{
	    debug sprintf "  Moving %s", $arc->sysdesig;
	    $node2->add( $pred_name => $obj );
	}
	elsif( $move_literals )
	{
	    if( $pred_name eq 'created' or
		$pred_name eq 'updated' )
	    {
		debug sprintf "  Ignoring %s", $arc->sysdesig;
	    }
	    else
	    {
		debug sprintf "  Moving %s", $arc->sysdesig;
		$node2->add( $pred_name => $arc->value );
	    }
	}
	$arc->remove;
    }

    foreach my $arc ( $node1->revarc_list->explicit->nodes )
    {
	my $pred_name = $arc->pred->name->plain;
	if( my $subj = $arc->subj )
	{
	    $subj->add( $pred_name => $node2 );
	}
	$arc->remove;
    }

    return $node2;
}


#######################################################################

=head2 link_paths

  $n->link_paths

Create a list of paths leading up to this node. A list of a list of
nodes. The list of nodes is the path from the base down to the leaf.

This can be used to generate a path with links to go up in the tree.

=cut

sub link_paths
{
    my( $node, $lvl ) = @_;

    $lvl ||= 0;
    $lvl ++;

    my @link_paths;

    debug 3, '  'x$lvl . "link_paths for ".$node->id;
    my @parents = $node->list('scof', {inactive_ne=>1}, 'direct')->nodes;

    foreach my $parent ( @parents )
    {
	debug 3, '  'x$lvl . "  parent ".$parent->id;
	foreach my $part ( @{ $parent->link_paths($lvl) } )
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

=head2 tree_select_widget

  $n->tree_select_widget

Returns: a HTML widget that draws the C<scof> tree.

=cut

sub tree_select_widget
{
    my( $node, $pred_in ) = @_;

    my $pred = Rit::Base::Pred->get($pred_in)
      or die "no pred ($pred_in)";

    my $data = $node->tree_select_data($pred);

    my $select = Template::PopupTreeSelect->new(
						name => 'Ritbase_tsw',
						data => $data,
						title => 'Select a node',
						button_label => 'Choose',
						include_css => 0,
						image_path => $Para::Frame::REQ->site->home_url_path . '/images/PopupTreeSelect/'
					       );
    return $select->output;
}


#######################################################################

=head2 tree_select_data

  $n->tree_select_data

Used by L</tree_select_widget>

=cut

sub tree_select_data
{
    my( $node, $pred ) = @_;

    $pred or confess "param pred missing";

    my $id = $node->id;
    my $pred_id = $pred->id;

    my $name = $node->name->loc;
    debug 2, "Processing treepart $id: $name";
    my $rec = $Rit::dbix->select_record("select count(id) as cnt from rel where pred=? and obj=?", $pred_id, $id);
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

    my $childs = $node->revlist('scof',undef,'direct');

    if( $childs->size )
    {
	debug 2, "                   $id got ".($childs->size)." childs";
	$data->{children} = [];

	foreach my $subnode ( $childs->nodes )
	{
	    push @{ $data->{children} }, $subnode->tree_select_data($pred);
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

Checks if the resource has a property C<is> to a class that has the
property C<class_handled_by_perl_module>.

This tells that the resource object should be blessd into the class
represented bu the object pointet to by
C<class_handled_by_perl_module>.  The package name is given by the
nodes C<code> property.

If no such classes are found, L<Rit::Base::Resource> is used.  We make
a special check for L<Rit::Base::Arc> but L<Rit::Base::Pred> uses
C<class_handled_by_perl_module>.

A Class can only be handled by one perl class. But a resource can have
propertis C<is> to more than one class. Special perl packages may be
constructed for this, that inherits from all the given classes.

Returns: A scalar with the package name

=cut

sub find_class
{
    my( $node ) = @_;

    # I guess this is sufficiently efficient

    # This is an optimization for:
    # my $classes = $islist->list('class_handled_by_perl_module');
    #
    my $islist = $node->list('is',undef,'not_disregarded');
    my @classes;
    foreach my $elem ($islist->as_array)
    {
	foreach my $class ($elem->list('class_handled_by_perl_module')->nodes )
	{
	    push @classes, $class;
	}
    }

    if( $classes[1] ) # Multiple inheritance
    {
	my $key = join '_', map $_->id, @classes;
	unless( $Rit::Base::Cache::Class{ $key } )
	{
	    no strict "refs";
	    my @classnames =  map $_->first_prop('code')->plain, @classes;
	    my $package = "Rit::Base::Metaclass::$key";
#	    debug "Creating package $package";
	    @{"${package}::ISA"} = ("Rit::Base::Metaclass",
				    @classnames,
				    "Rit::Base::Resource");
	    foreach my $classname ( @classnames )
	    {
		require(package_to_module($classname));
	    }
	    $Rit::Base::Cache::Class{ $key } = $package;
	}
#	debug "Class Multi $key -> ".$node->desig;
	return $Rit::Base::Cache::Class{ $key };
    }
    elsif( $classes[0] )
    {
	no strict "refs";
	my $classname = $classes[0]->first_prop('code')->plain;
	require(package_to_module($classname));

	my $metaclass = "Rit::Base::Metaclass::$classname";
#	    debug "Creating package $package";
	@{"${metaclass}::ISA"} = ($classname, "Rit::Base::Resource");

#	debug "Class $classname -> ".$node->desig;
	return $metaclass;
    }
    else
    {
	return "Rit::Base::Resource";
    }
}


#########################################################################

=head2 first_bless

  $node->first_bless()

Used by L</get> and L<Rit::Base::Lazy::AUTOLOAD>.

Uses C<%Rit::Base::LOOKUP_CLASS_FOR>

=cut

sub first_bless
{
    my( $node ) = @_;

    # get the right class
    my( $class ) = ref $node;
    if( $Rit::Base::LOOKUP_CLASS_FOR{ $class } )
    {
	# We assume that Arcs et al are retrieved directly. Thus,
	# only look for 'is' arcs. Pred and Rule nodes should have an
	# is arc. Lastly, look if it's an arc if it's nothing else.

	$class = $node->find_class;
	if( $class eq 'Rit::Base::Resource' )
	{
	    # Check if this is an arc
	    #
	    my $sth_id = $Rit::dbix->dbh->prepare("select * from rel where id = ?");
	    $sth_id->execute($node->{'id'});
	    my $rec = $sth_id->fetchrow_hashref;
	    $sth_id->finish;
	    if( $rec )
	    {
		bless $node, "Rit::Base::Arc";
		return $node->init($rec);
	    }
	}
	else
	{
	    bless $node, $class;
	}
    }

    confess $node unless ref $node;

    $node->init;

#    debug sprintf "Node %d initiated as $node", $node->id;

    return $node;
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

  $node->rebless()

Called by L<Rit::Base::Arc/create_check> and
L<Rit::Base::Arc/remove_check> for updating the blessing of the
resource object.

This checks the class by calling L</find_class>.

If the class has changed, calls L</on_unbless> in the old class,
reblesses in the new class and then calls L</on_bless>. This should
work also for metaclasses L<Rit::Base::Metaclass>.

The new package are required if necessary.

Returns: the resource object

=cut

sub rebless
{
    my( $node ) = @_;

    my $class_old = ref $node;
    my $class_new = $node->find_class;
    if( $class_old ne $class_new )
    {
#	debug "Reblessing ".$node->sysdesig;
#	debug "  from $class_old\n    to $class_new";
	unless($class_new =~ /^Rit::Base::Metaclass::/ )
	{
	    require(package_to_module($class_new));
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
			    &{$method}($node, $class_new);
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
			    &{$method}($node, $class_new);
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
			&{$method}($node, $class_new);
		    }
		}
	    }
	    else
	    {
		$node->on_unbless( $class_new );
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
			    &{$method}($node, $class_old);
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
			    &{$method}($node, $class_old);
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
			    &{$method}($node, $class_old);
			}
		    }
		}
	    }
	    else
	    {
		$node->on_bless( $class_old );
	    }
	}
    }

    return $node;
}


#########################################################################

=head2 on_unbless

  $node->on_unbless( $class_new )

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

  $node->on_bless( $class_old )

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

  $node->on_arc_add( $arc, $pred_name )

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

  $node->on_arc_del( $arc, $pred_name )

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

The caller must take care of using the cache
C<$Rit::Base::Cache::Resource{$id}> before calling this constructor!

=cut

sub new
{
    my( $this, $id ) = @_;
    my $class = ref($this) || $this;

    # Resources not stored in DB can have negative numbers
    unless( $id =~ /^-?\d+$/ )
    {
	confess "Invalid id for node: $id";
    }

    my $node = bless
    {
	'id' => $id,
    }, $class;


#    debug "Caching node $id: $node";
    $Rit::Base::Cache::Resource{ $id } = $node;

    $node->initiate_cache;

#    warn("Set up new node $node for -->$id<--\n");

    return $node;
}

#########################################################################

=head2 get_by_label

=cut

sub get_by_label
{
    my $class = shift;

    # Look in lable cache
    unless( ref($_[0]) or $_[1] ) # Do not lookup complex searches from cache
    {
	if( my $id = $Rit::Base::Cache::Label{$class}{ $_[0] } )
	{
	    return $class->get( $id );
	}
    }

    my $list = $class->find_by_label(@_);

    my $req = $Para::Frame::REQ;
    confess "No REQ" unless $req;

    unless( $list->size )
    {
	my $msg = "";
	if( $req->is_from_client )
	{
	    my $result = $req->result;
	    $result->{'info'}{'alternatives'}{'query'} = $_[0];
	    $result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	    $req->set_error_response_path("/node_query_error.tt");
	}
	else
	{
	    $msg .= datadump($_[0]);
	    $msg .= Carp::longmess;
	}
	throw('notfound', "No nodes matches query:\n$msg");
    }

    if( $list->size > 1 )
    {
	# Did we make the choice for this?

	# TODO: Handle situations with multipple choices (in sequence (nested))

	unless( $req->is_from_client )
	{
	    confess "We got a list: ".datadump( $list,4 );
	}

	my $home = $req->site->home_url_path;
	if( my $item_id = $req->q->param('route_alternative') )
	{
	    $req->q->delete('route_alternative');
	    return Rit::Base::Resource->get( $item_id );
	}

	# Ask for which alternative; redo

	$req->session->route->bookmark;
	$req->set_page_path("/alternatives.tt");
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
	     my $tstr = $item->list('is', '', 'direct')->name->loc || '';
	     my $cstr = $item->list('scof', '', 'direct')->name->loc;
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
	  ['Backa', $req->referer(), 'skip_step'],
	 ],
	};
	$req->q->delete_all();
	throw('alternatives', 'Specificera alternativ');
    }

    my $first = $list->get_first_nos;

    # Cache name lookups
    unless( ref($_[0]) or $_[1] ) # Do not cache complex searches
    {
	my $id = $first->id;
	$Rit::Base::Cache::Label{$class}{ $_[0] } = $id;
	$first->{'lables'}{$class}{ $_[0] } ++;
    }

    return $first;
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

    # Reset registred cached lable lookups
    my $lables = $node->{'lables'} ||= {};
    foreach my $class ( keys %$lables )
    {
	my $class_hash = $lables->{$class};
	foreach my $label ( keys %$class_hash )
	{
	    delete $Rit::Base::Cache::Label{$class}{ $label };
	}
    }

    $node->{'arc_id'}            = {};
    $node->{'relarc'}            = {};
    $node->{'revarc'}            = {};
    $node->{'initiated_relprop'} = {};
    $node->{'initiated_revprop'} = {};
    $node->{'initiated_rel'}     = 0;
    $node->{'initiated_rev'}     = 0;
    $node->{'lables'}            = {};

    return $node;
}


#########################################################################

=head2 initiate_rel

=cut

sub initiate_rel
{
    return if $_[0]->{'initiated_rel'};

    my( $node ) = @_;

    my $nid = $node->id;

    $node->{'initiated_rel'} = 1;

    # Get statements for node $id
    my $sth_init_sub_name = $Rit::dbix->dbh->prepare("select * from rel where sub in(select obj from rel where (sub=? and pred=11)) UNION select * from rel where sub=?");
    $sth_init_sub_name->execute($nid, $nid);
    my $stmts = $sth_init_sub_name->fetchall_arrayref({});
    $sth_init_sub_name->finish;

    my @extra_nodes_initiated;
    my $cnt = 0;
    foreach my $stmt ( @$stmts )
    {
	if( $stmt->{'sub'} == $nid )
	{
	    $node->populate_rel( $stmt );
	}
	else # A literal resource for pred name
	{
	    my $subnode = $node->get( $stmt->{'sub'} );
	    $subnode->populate_rel( $stmt );
	    push @extra_nodes_initiated, $subnode;
	}

	# Handle long lists
	unless( ++$cnt % 25 )
	{
	    $Para::Frame::REQ->may_yield;
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
}

#########################################################################

=head2 initiate_rev

=cut

sub initiate_rev
{
    return if $_[0]->{'initiated_rev'};

    my( $node ) = @_;

    my $nid = $node->id;

    $node->{'initiated_rev'} = 1;

    my $sth_init_obj = $Rit::dbix->dbh->prepare("select * from rel where obj=?");
    $sth_init_obj->execute($nid);
    my $revstmts = $sth_init_obj->fetchall_arrayref({});
    $sth_init_obj->finish;

    my $cnt = 0;
    foreach my $stmt ( @$revstmts )
    {
	$node->populate_rev( $stmt );

	# Handle long lists
	unless( ++$cnt % 25 )
	{
	    debug "Populated $cnt";
	    $Para::Frame::REQ->may_yield;
	    die "cancelled" if $Para::Frame::REQ->cancelled;
	}
    }

    # Mark up all individual preds for the node as initiated
    foreach my $name ( keys %{$node->{'revarc'}} )
    {
	$node->{'initiated_revprop'}{$name} = 2;
    }

#    warn "End   init all props of node $node->{id}\n";
}

#########################################################################

=head2 initiate_prop

Returns undef if no values for this prop

=cut

sub initiate_prop
{
    my( $node, $name ) = @_;

    confess datadump \@_ unless ref $node; ### DEBUG
    return $node->{'relarc'}{ $name } if $node->{'initiated_relprop'}{$name};
    return undef if $node->{'initiated_rel'};

    debug 4, "Initiating prop $name for $node->{id}";

    my $nid = $node->id;
    confess "Node id missing: ".datadump($node,3) unless $nid;

    $node->{'initiated_relprop'}{$name} = 1;

    # Keep $node->{'relarc'}{ $name } nonexistant if no such arcs, since
    # we use the list of preds as meaning that there exists props with
    # those preds

    # arc_id and arc->name is connected. don't clear one

    if( my $pred_id = Rit::Base::Pred->get_id( $name ) )
    {
	if( debug > 3 )
	{
	    $Rit::Base::Resource::timestamp = time;
	}
	my $stmts;
	if( $pred_id == 11 ) # Optimization...
	{
	    my $sth_init_sub_pred_name = $Rit::dbix->dbh->prepare("select * from rel where sub in(select obj from rel where (sub=? and pred=?)) UNION select * from rel where (sub=? and pred=?)");
	    $sth_init_sub_pred_name->execute( $nid, $pred_id, $nid, $pred_id );
	    $stmts = $sth_init_sub_pred_name->fetchall_arrayref({});
	    $sth_init_sub_pred_name->finish;
	}
	else
	{
	    my $sth_init_sub_pred = $Rit::dbix->dbh->prepare("select * from rel where sub=? and pred=?");
	    $sth_init_sub_pred->execute( $nid, $pred_id );
	    $stmts = $sth_init_sub_pred->fetchall_arrayref({});
	    $sth_init_sub_pred->finish;
	}

	if( debug > 3 )
	{
	    my $ts = $Rit::Base::Resource::timestamp;
	    $Rit::Base::Resource::timestamp = time;
	    debug sprintf("Got %d arcs in %2.3f secs for pred %d sub %d",
			 scalar( @$stmts ), time - $ts, $pred_id, $nid);

	    debug "Before populating:\n";
	    if( $node->{'relarc'}{ $name } )
	    {
		foreach my $arc (@{$node->{'relarc'}{ $name }})
		{
		    debug "  ".$arc->sysdesig_nosubj;
		}
	    }
	}

	my @extra_nodes_initiated;
	foreach my $stmt ( @$stmts )
	{
	    debug "  populating with ".datadump($stmt,4)
	      if debug > 4;
	    if( $stmt->{'sub'} == $nid )
	    {
		$node->populate_rel( $stmt );
	    }
	    else
	    {
		my $subnode = $node->get_by_id( $stmt->{'sub'} );
		$subnode->populate_rel( $stmt );
		push @extra_nodes_initiated, $subnode;
	    }
	}

	foreach my $subnode ( @extra_nodes_initiated )
	{
	    foreach my $name ( keys %{$subnode->{'relarc'}} )
	    {
		$subnode->{'initiated_relprop'}{$name} = 2;
	    }
	    $subnode->{'initiated_rel'} = 1;
	}

	debug 4, "* prop $name for $nid is now initiated";
    }
    else
    {
	debug 4, "* prop $name does not exist!";
    }

    $node->{'initiated_relprop'}{$name} = 2;
    return $node->{'relarc'}{ $name };
 }

#########################################################################

=head2 initiate_revprop

Returns undef if no values for this prop

TODO: Use custom DBI fetchrow

=cut

sub initiate_revprop
{
    my( $node, $name ) = @_;

    debug 3, "May initiate prop $name for $node->{id}";
    return $node->{'revarc'}{ $name } if $node->{'initiated_revprop'}{$name};
    return undef if $node->{'initiated_rev'};

    debug 3, "Initiating revprop $name for $node->{id}";

    $node->{'initiated_revprop'}{$name} = 1;

    # Keep $node->{'revarc'}{ $name } nonexistant if no such arcs,
    # since we use the list of preds as meaning that there exists
    # props with those preds

    # arc_id and arc->name is connected. don't clear one

    if( my $pred_id = Rit::Base::Pred->get_id( $name ) )
    {
	if( debug > 1 )
	{
	    $Rit::Base::timestamp = time;
	}

	my $sth_init_obj_pred = $Rit::dbix->dbh->prepare("select * from rel where obj=? and pred=?");
	$sth_init_obj_pred->execute( $node->id, $pred_id );
	my $stmts = $sth_init_obj_pred->fetchall_arrayref({});
	$sth_init_obj_pred->finish;

	if( debug > 1 )
	{
	    my $ts = $Rit::Base::timestamp;
	    $Rit::Base::timestamp = time;
	    debug sprintf("Got %d arcs in %2.2f secs",
			 scalar( @$stmts ), time - $ts);
	}
	foreach my $stmt ( @$stmts )
	{
	    debug "  populating with ".datadump($stmt,4)
	      if debug > 4;
	    $node->populate_rev( $stmt, undef );
	}
	debug 3, "* revprop $name for $node->{id} is now initiated";
    }
    else
    {
	debug "* revprop $name does not exist!";
    }

    $node->{'initiated_revprop'}{$name} = 2;
#    debug 3, "  Will now return '$node->{'revarc'}{ $name }' from initiate_revprop"; ### HEAVY!!!
    return $node->{'revarc'}{ $name };
}

#########################################################################

=head2 populate_rel

Insert data from a rel record into node

=cut

sub populate_rel
{
    my( $node, $stmt, $nocount ) = @_;

    my $class = ref($node);

    # Oh, yeah? Like I care?!?
    my $pred_name = Rit::Base::Pred->get( $stmt->{'pred'} )->name;
    if(($node->{'initiated_relprop'}{$pred_name} ||= 1) > 1)
    {
	debug 4, "NOT creating arc";
	return;
    }

    debug 4, "Creating arc for $node with $stmt";
    my $arc = Rit::Base::Arc->get_by_rec_and_register( $stmt, $node );
    debug 4, "  Created";

    debug 3, "**Add prop $pred_name to $node->{id}";

    return 1;
}

#########################################################################

=head2 populate_rev

Insert data from a rev record into node

=cut

sub populate_rev
{
    my( $node, $stmt, $nocount ) = @_;

    my $class = ref($node);

    # Oh, yeah? Like I care?!?
    debug 3, timediff("populate_rev");
    my $pred_name = Rit::Base::Pred->get( $stmt->{'pred'} )->name;
    if(($node->{'initiated_revprop'}{$pred_name} ||= 1) > 1)
    {
	debug 4, "NOT creating arc";
	return;
    }

    if( debug > 3 )
    {
	debug "Creating arc for $node->{id} with ".datadump($stmt,4);
	debug timediff("new arc");
    }
    my $arc = Rit::Base::Arc->get_by_rec_and_register( $stmt, undef, $node );
    if( debug > 3 )
    {
	debug "  Created";
	debug "**Add revprop $pred_name to $node->{id}";
	debug timediff("done");
    }

    return 1;
}


#########################################################################

=head2 handle_query_arc

Return number of changes

=cut

sub handle_query_arc
{
    my( $node, $param, $row, $deathrow ) = @_;

    my $changes = 0;
    foreach my $value ( $Para::Frame::REQ->q->param($param) )
    {
	$changes += $node->handle_query_arc_value( $param, $row, $deathrow, $value );
    }

    return $changes;
}

#########################################################################

=head2 handle_query_arc_value

Return number of changes

=cut

sub handle_query_arc_value
{
    my( $node, $param, $row, $deathrow, $value ) = @_;

    die "missing value" unless defined $value;

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $site = $page->site;
    my $q = $req->q;
    my $id = $node->id;

    my $arg = parse_form_field_prop($param);

    my $pred_name = $arg->{'pred'};     # In case we should create the prop
    my $rev       = $arg->{'revpred'};  # In case we should create the prop
    my $arc_id    = $arg->{'arc'};      # arc to update. Create arc if undef
    my $desig     = $arg->{'desig'};    # look up obj that has $value as $desig
    my $type      = $arg->{'type'};     # desig obj must be of this type
    my $scof      = $arg->{'scof'};     # desig obj must be a scof of this type
    my $rowno     = $arg->{'row'};      # rownumber for matching props with new/existing arcs

    # Switch node if subj is set
    if( $arg->{'subj'} and $arg->{'subj'} =~ /^\d+$/ )
    {
	$id = $arg->{'subj'};
	$node = Rit::Base::Resource->get($id);
    }

    my $changes = 1;

    # Sanity check of value
    #
    if( $value =~ /^Rit::Base::/ )
    {
	throw('validation', "Form gave faulty value '$value' for $param\n");
    }
    elsif( ref $value )
    {
	throw('validation', "Form gave faulty value '$value' for $param\n");
    }


    if( debug > 3 )
    {
	debug "handle_query_arc $arc_id\n";
	debug "  param $param = $value\n";
	debug "  type : $type\n";
	debug "  scof : $scof\n";
	debug "  desig: $desig\n";
    }

    if( $rev ) # reverse arc
    {
	$pred_name = $rev;
	$rev = 1;
    }

    my $pred = getpred( $pred_name );
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
    my $valtype = $pred->valtype;
    $row->{$rowno}{'pred_id'} = $pred_id if $rowno;

    if( $arc_id eq 'singular' ) # Only one prop of this type
    {
	# Sort out those of the specified type
	my $arcs;
	if( $rev )
	{
	    $arcs = $node->revarc_list($pred_name);
	}
	else
	{
	    $arcs = $node->arc_list($pred_name);
	}

	if( $type and  $arcs->size )
	{
	    if( $rev )
	    {
		$arcs = $arcs->find( subj => { is => $type } );
	    }
	    else
	    {
		$arcs = $arcs->find( obj => { is => $type } );
	    }
	}

	if( $scof and  $arcs->size )
	{
	    if( $rev )
	    {
		$arcs = $arcs->find( subj => { scof => $type } );
	    }
	    else
	    {
		$arcs = $arcs->find( obj => { scof => $type } );
	    }
	}

	if( $arcs->size > 1 ) # more than one
	{
	    debug 3, "prop $pred_name had more than one value";

	    # Keep the first arc found
	    my @arclist = $arcs->as_array;
	    my $arc = shift @arclist;
	    $arc_id = $arc->id;

	    # TODO: Should remove extra arcs
	    foreach my $arc ( @arclist )
	    {
		$changes += $arc->remove;
	    }
	}
	elsif( $arcs->size ) # Replace this
	{
	    $arc_id = $arcs->get_first_nos->id;
	    debug 3, "Updating existing arc $arc_id";
	}
	else
	{
	    $arc_id = '';
	}
    }


    if( $rev ) # reverse arc
    {
	$pred_name = $rev;
	$rev = 1;

	if(length $value )
	{
	    debug 3, "  Reversing arc update";

	    my $subjs = Rit::Base::Resource->find_by_label( $value );
	    if( $type )
	    {
		$subjs = $subjs->find( is => $type );
	    }
	    if( $scof )
	    {
		$subjs = $subjs->find( scof => $scof );
	    }
	    $subjs->materialize_all;


	    $value = $node;
	    $node = $subjs->find_one; # Expect only one value
	    $id = $node->id;

	    if( debug > 3 )
	    {
		debug sprintf "  New node : %s", $node->sysdesig;
		debug sprintf "  New value: %s", $value->sysdesig;
	    }

	}
	elsif( $arc_id )
	{
	    my $arc = getarc($arc_id);
	    $deathrow->{ $arc_id } = $arc;
	}
	elsif( not $arc_id and not length $value )
	{
	    # nothing changed
	    return 0;
	}
	else
	{
	    die "not implemented";
	}
    }


    if( $desig and length( $value ) ) # replace $value with the node id
    {
	debug 3, "    Set value to a $type with $desig $value";
	$value = Rit::Base::Resource->find_one({
	    $desig => $value,
	    'is' => $type,
	})->id;
	# Convert back to obj later. (We expect id)
    }

    if( debug > 3 )
    {
	debug "We have arc_id: $arc_id";
	my $arc = $node->get_related_arc_by_id($arc_id);
	debug "The arc_id got us $arc";
    }
    if( $arc_id and $node->get_related_arc_by_id($arc_id)) # check old value
    {
	debug 3, "  Check old arc $arc_id";
	my $arc = $node->get_related_arc_by_id($arc_id);

	########################################
	# Authenticate change of arc
	$node->authenticate_update( $pred );

	if( $arc->pred->id != $pred_id )
	{
	    $changes += $arc->set_pred( $pred_id );
	}

	my $present_value = $arc->value;

	# set the value to obj id if obj
	if( $coltype eq 'obj' )
	{
	    if( $value )
	    {
		if( ref $value )
		{
		    $value = Rit::Base::Resource->get( $value );
		}
		else
		{
		    my $list = Rit::Base::Resource->find_by_label( $value );

		    my $props = {};
		    if( $type )
		    {
			$props->{'is'} = $type;
		    }

		    if( $scof )
		    {
			$props->{'scof'} = $scof;
		    }

		    $value = $list->get($props);
		}

		$changes += $arc->set_value( $value );
	    }
	    else
	    {
		$deathrow->{ $arc_id } = $arc;
	    }
	}
	else
	{
	    if( length $value )
	    {
		$changes += $arc->set_value( $value );
	    }
	    else
	    {
		$deathrow->{ $arc_id } = $arc;
	    }
	}

	# Store row info
	$row->{$rowno}{'arc_id'} = $arc_id if $rowno;

	# This arc has been taken care of
	debug 2, "Removing check_arc_${arc_id}";
	$q->delete("check_arc_${arc_id}");
    }
    else # create new arc
    {
	########################################
	# Authenticate creation of prop
	#
	$node->authenticate_update( $pred );

	if( length $value )
	{
	    debug 3, "  Creating new property";
	    debug 3, "  Value is $value" if not ref $value;
	    debug 3, sprintf "  Value is %s", $value->sysdesig if ref $value;
	    if( $pred->objtype )
	    {
		debug 3, "  Pred is of objtype";

		# Support adding more than one obj value with ','
		#
		my @values;
		if( ref $value )
		{
		    push @values, $value;
		}
		else
		{
		    push @values, split /\s*,\s*/, $value;
		}

		foreach my $val ( @values )
		{
		    my $objs = Rit::Base::Resource->find_by_label($val);

		    unless( $rev )
		    {
			if( $type )
			{
			    $objs = $objs->find( is => $type );
			}

			if( $scof )
			{
			    $objs = $objs->find( scof => $scof );
			}
		    }

		    $objs->materialize_all;



		    if( $objs->size > 1 )
		    {
			$req->session->route->bookmark;
			my $home = $req->site->home_url_path;
			my $uri = $page->url_path_slash;
			$req->set_page_path("/alternatives.tt");
			my $result = $req->result;

			$result->{'info'}{'alternatives'} =
			{
			 title => "Välj $pred_name",
			 text  => "Flera noder har namnet '$val'",
			 alts => $objs,
			 rowformat => sub
			 {
			     my( $item ) = @_;
			     # TODO: create cusom label
			     my $label = $item->desig;

			     # Replace this value part with the selected
			     # object id
			     #
			     my $value_new = $value;
			     my $item_id = $item->id;
			     $value_new =~ s/$val/$item_id/;

			     my $args =
			     {
			      step_replace_params => $param,
			      $param => $value_new,
			      run => 'next_step',
			     };
			     my $link = Para::Frame::Widget::forward( $label, $uri, $args );
			     my $tstr = $item->list('is', '', 'direct')->name->loc;
			     my $view = Para::Frame::Widget::jump('visa',
								  $item->form_url->as_string,
								 );
			     return "$tstr $link - ($view)";
			 },
			 button =>
			 [
			  ['Backa', $req->referer(), 'skip_step'],
			 ],
			};
			$q->delete_all();
			throw('alternatives', 'Specificera alternativ');
		    }
		    elsif( not $objs->size )
		    {
			$req->session->route->bookmark;
			my $home = $site->home_url_path;
			$req->set_page_path('/confirm.tt');
			my $result = $req->result;
			$result->{'info'}{'confirm'} =
			{
			 title => "Skapa $type $val?",
			 button =>
			 [
			  ['Ja', undef, 'node_update'],
			  ['Backa', undef, 'skip_step'],
			 ],
			};

			$q->delete_all();
			$q->init({
				  arc___pred_name => $val,
				  prop_is         => $type,
				 });
			throw('incomplete', "Nod saknas");
		    }

		    my $arc = Rit::Base::Arc->
		      create({
			      subj_id => $id,
			      pred_id => $pred_id,
			      value   => $val,
			     }, \$changes );

		    # Store row info
		    if( $rowno )
		    {
			if( $row->{$rowno}{'arc_id'} )
			{
			    throw('validation', "Row $rowno has more than one new value\n");
			}
			$row->{$rowno}{'arc_id'} = $arc->id;
		    }
		}
	    }
	    else
	    {
		my $arc = Rit::Base::Arc->
		  create({
			  subj_id => $id,
			  pred_id => $pred_id,
			  value   => $value,
			 }, \$changes );
	    }
	}
    }
    return $changes;
}

#########################################################################

=head2 handle_query_prop

Return number of changes

=cut

sub handle_query_prop
{
    my( $node, $param ) = @_;

    my $changes = 0;
    foreach my $value ( $Para::Frame::REQ->q->param($param) )
    {
	$changes += $node->handle_query_prop_value( $param, $value );
    }

    return $changes;
}

#########################################################################

=head2 handle_query_prop_value

Return number of changes

TODO: translate this to a call to handle_query_arc

=cut

sub handle_query_prop_value
{
    my( $node, $param, $value ) = @_;

    die "missing value" unless defined $value;


    $param =~ /^prop_(.*?)(?:__(.*))?$/;
    my $pred_name = $1;
    my $obj_pred_name = $2;

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $site = $page->site;
    my $q = $req->q;
    my $id = $node->id;

    my $changes = 0;

    ########################################
    # Authenticate change
    #
    $node->authenticate_update( getpred($pred_name), );

    if( my $value = $value ) # If value is true
    {
	my $pred = getpred( $pred_name ) or die "Can't find pred $pred_name\n";
	my $pred_id = $pred->id;
	my $coltype = $pred->coltype;
	my $valtype = $pred->valtype;
	die "$pred_name should be of obj type" unless $coltype eq 'obj';

	my( $objs );
	if( $obj_pred_name )
	{
	    $objs = Rit::Base::Resource->find({$obj_pred_name => $value});
	}
	else
	{
	    $objs = Rit::Base::Resource->find_by_label($value);
	}

	if( $objs->size > 1 )
	{
	    my $home = $site->home_url_path;
	    $req->session->route->bookmark;
	    my $uri = $page->url_path_slash;
	    $req->set_page_path("/alternatives.tt");
	    my $result = $req->result;
	    $result->{'info'}{'alternatives'} =
	    {
	     # TODO: Create cusom title and text
	     title => "Välj $pred_name",
	     alts => $objs,
	     rowformat => sub
	     {
		 my( $node ) = @_;
		 # TODO: create cusom label
		 my $label = $node->sysdesig;
		 my $args =
		 {
		  step_replace_params => $param,
		  $param => $node->sysdesig,
		  run => 'next_step',
		 };
		 my $link = Para::Frame::Widget::forward( $label, $uri, $args );
		 my $view = Para::Frame::Widget::jump('visa',
						      $node->form_url->as_string,
						     );
		 $link .= " - ($view)";
		 return $link;
	     },
	     button =>
	     [
	      ['Backa', $req->referer(), 'skip_step'],
	     ],
	    };
	    $q->delete_all();
	    throw('alternatives', "Flera noder har namnet '$value'");
	}
	elsif( not $objs->size )
	{
	    throw('validation', "$value not found");
	}

	my $arc = Rit::Base::Arc->create({
	    subj_id => $id,
	    pred_id => $pred_id,
	    value   => $objs->get_first_nos,
	}, \$changes);

	$q->delete( $param ); # We will not add the same value twice
    }
    return $changes;
}

#########################################################################

=head2 handle_query_row

Return number of changes

=cut

sub handle_query_row
{
    my( $node, $param, $row, $deathrow ) = @_;

    my $changes = 0;
    foreach my $value ( $Para::Frame::REQ->q->param($param) )
    {
	$changes += $node->handle_query_row_value( $param, $row, $deathrow, $value );
    }

    return $changes;
}

#########################################################################

=head2 handle_query_row_value

Return number of changes

This sub is mainly about setting properties for arcs.  The
subjct is an arc id.  This can be used for saying that an arc is
inactive.

=cut

sub handle_query_row_value
{
    my( $node, $param, $row, $deathrow, $value ) = @_;

    die "missing value" unless defined $value;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $arg = parse_form_field_prop($param);

    my $pred_name = $arg->{'pred'};  # In case we should create the prop
    my $arc_id    = $arg->{'arc'};   # arc to update. Create arc if undef
    my $subj_id    = $arg->{'sub'} || $arg->{'subj'};;  # sub for this arc
    my $desig     = $arg->{'desig'}; # look up obj that has $value as $desig
    my $type      = $arg->{'type'};  # desig obj must be of this type
    my $rowno     = $arg->{'row'};   # rownumber for matching props with new/existing arcs

    # Switch node if subj is set. May be 'arc' if the arc is the subj
    if( $subj_id  and $subj_id =~ /^\d+$/ )
    {
	$node = Rit::Base::Resource->get($subj_id);
    }

    my $pred = getpred( $pred_name );
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
    my $valtype = $pred->valtype;
    if( $coltype eq 'obj' )
    {
	$value = Rit::Base::Resource->get( $value );
    }

    my $changes = 0;

#    warn "Modify row $rowno\n";

    if( $arc_id ){ die "Why is arc_id defined?" };
    my $referer_arc_id = $row->{$rowno}{'arc_id'}; # Refering to existing arc
    if( $subj_id eq 'arc' )
    {
	$subj_id = $referer_arc_id;

	## Creating arc for nonexisting arc?
	if( not $subj_id )
	{
	    if( length $value )
	    {
		# Setup undef arc of right type. That is: In order for
		# us to setting the property for this arc, the arc
		# must exist, even if the arc has an undef value.

		########################################
		# Authenticate change of arc
		#
		# (how do we determine what user can do?)
		# Accept changes if the pred of the arc that is
		# the subj is allowed, and if the pred for this
		# arc also is allowed. (The later thing later)
		my $pred = Rit::Base::Pred->
		    get_id( $row->{$rowno}{'pred_id'} );
		$node->authenticate_update( $pred );

		my $subj = Rit::Base::Resource->find_set({
		    subj    => $node,
		    pred_id => $row->{$rowno}{'pred_id'},
		}, undef, \$changes );
		$row->{$rowno}{'arc_id'} = $subj_id = $subj->id;
	    }
	    else
	    {
		# Nothing to do for this row
		next;
	    }
	}
    }
    else
    {
	die "Not refering to arc?";
    }

    ########################################
    # Authenticate change of arc
    #
    $node->authenticate_update( $pred );

    eval
    {
	my $arc = Rit::Base::Arc->find_set(
						   {subj_id => $subj_id,
						    pred_id => $pred_id,
						}, undef, \$changes);

	if( not length $value )
	{
	    $deathrow->{ $arc->id } = $arc;  # Put arc on deathrow
	}
	else
	{
	    $changes += $arc->set_value( $value );
	    $q->delete("check_$param");

	    # Remove the subject (that is an arc) from deathrow
	    my $subj_id = $arc->subj->id;
	    delete $deathrow->{ $subj_id };
	}
    };
    if( $@ )
    {
	debug "  Don't bother?";
#	    my $error = catch( $@ );
#
#	    if( $error->type eq 'notfound' )
#	    {
#
#	    }
	die $@; # don't bother
    }
    return $changes;
}

#########################################################################

=head2 handle_query_check_row

Return number of changes

=cut

sub handle_query_check_row
{
    my( $node, $param, $row ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $arg = parse_form_field_prop($param);

    my $pred_name = $arg->{'pred'};  # In case we should create the prop
    my $arc_id    = $arg->{'arc'};   # arc to update. Create arc if undef
    my $subj_id    = $arg->{'sub'} || $arg->{'subj'};  # sub for this arc
    my $desig     = $arg->{'desig'}; # look up obj that has $value as $desig
    my $type      = $arg->{'type'};  # desig obj must be of this type
    my $rowno     = $arg->{'row'};   # rownumber for matching props with new/existing arcs

    # Switch node if subj is set. May be 'arc' if the arc is the subj
    if( $subj_id and $subj_id =~ /^\d+$/ )
    {
	$node = Rit::Base::Resource->get($subj_id);
    }

    my $changes = 0;

    if( $arc_id ){ die "Why is arc_id defined?" };
    my $referer_arc_id = $row->{$rowno}{'arc_id'}; # Refering to existing arc
    if( $subj_id eq 'arc' )
    {
	$subj_id = $referer_arc_id;

	## Creating arc for nonexisting arc?
	if( not $subj_id )
	{
	    # No arc present
	    return $changes;
	}
	else
	{
#	    warn "  Arc set to $subj_id for row $rowno\n";
	}
    }
    else
    {
	die "Not refering to arc?";
    }

    my $pred = getpred( $pred_name );
    my $pred_id = $pred->id;

    ########################################
    # Authenticate remove of arc
    #
    $node->authenticate_update( $pred );

    my $arcs = Rit::Base::Arc->find({subj_id => $subj_id, pred_id => $pred_id});
    # Remove found arcs
    foreach my $arc ( $arcs->as_array )
    {
	$changes += $arc->remove;
    }
    return $changes;
}

#########################################################################

=head2 handle_query_check_arc

Return number of changes

=cut

sub handle_query_check_arc
{
    my( $node, $param, $arc_id, $deathrow ) = @_;

    # Now uses deathrow for removing arcs
    $deathrow->{ $arc_id } = Rit::Base::Arc->get( $arc_id );

    return 0;
}

#########################################################################

=head2 handle_query_check_node

Return number of changes

=cut

sub handle_query_check_node
{
    my( $this, $param, $node_id ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    unless( grep( /^node_${node_id}/, $q->param ) )
    {
	my $node = Rit::Base::Resource->get( $node_id );
	debug "Removing node: ${node_id}";
	return $node->remove;
    }
    debug "Saving node: ${node_id}. grep: ". grep( /^node_${node_id}/, $q->param );
}

#########################################################################

=head2 handle_query_check_prop

=cut

sub handle_query_check_prop
{
    my( $node, $param, $pred_name ) = @_;

    my $id = $node->id;
    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $changes = 0;

    my $pred = getpred( $pred_name );
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
    my $valtype = $pred->valtype;

    ########################################
    # Authenticate change of prop
    #
    $node->authenticate_update( $pred );

    # Remember the values this node has for the pred
    my %has_val;
    foreach my $val ( $node->list($pred_name)->as_array )
    {
	my $val_str = $val->id ? $val->id : $val->literal;
	$has_val{$val_str} ++;
    }

    my %is_set;
    foreach my $value ( $q->param("prop_${pred_name}") )
    {
	$is_set{$value} ++;
    }


    foreach my $val_key ( $q->param($param) )
    {
	my $value = $val_key;
	if( $coltype eq 'obj' )
	{
	    $value = Rit::Base::Resource->get( $val_key );
	}

	# Remove rel
	if( $has_val{$val_key} and not $is_set{$val_key} )
	{
	    my $arcs = Rit::Base::Arc->find({
		subj_id => $id,
		pred_id => $pred_id,
		value   => $value,
	    });

	    foreach my $arc ( $arcs->as_array )
	    {
		$changes += $arc->remove;
	    }
	}
	# Add rel
	elsif( not $has_val{$val_key} and $is_set{$val_key} )
	{
	    my $arc = Rit::Base::Arc->create({
		subj_id => $id,
		pred_id => $pred_id,
		value   => $value,
	    }, \$changes );
	}
    }
    return $changes;
}


sub handle_query_newsubjs
{
    my( $q, $newsubj_params ) = @_;

    my %newsubj;
    my %keysubjs;
    my $changes = 0;

    foreach my $param (@$newsubj_params)
    {
	my $arg = parse_form_field_prop($param);

	if( $arg->{'newsubj'} =~ m/^(main_)?(.*?)/ )
	{
	    next unless $q->param( $param );
	    my $main = $1;
	    my $no = $2;

	    $keysubjs{$no} = 'True'
	      if( $main );

	    $newsubj{$no} = {} unless $newsubj{$no};
	    $newsubj{$no}{$arg->{'pred'}} = $q->param( $param );
	}
    }

    foreach my $ns (keys %keysubjs)
    {
	debug "Newsubj creating a node: ". datadump $newsubj{$ns};
	Rit::Base::Resource->create( $newsubj{$ns} );
	$changes += keys %{$newsubj{$ns}};
    }

    return $changes;
}

#########################################################################

=head2 handle_query_check_revprop

Return number of changes

=cut

sub handle_query_check_revprop
{
    my( $node, $param, $pred_name ) = @_;

    my $id = $node->id;
    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $changes = 0;

    my $pred = getpred( $pred_name );
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
    my $valtype = $pred->valtype;

    ########################################
    # Authenticate change of prop
    #
    $node->authenticate_update( $pred );

    # Remember the values this node has for the pred
    my %has_val;
    foreach my $val ( $node->revlist($pred_name)->as_array )
    {
	my $val_str = $val->id ? $val->id : $val->literal;
	$has_val{$val_str} ++;
    }

    my %is_set;
    foreach my $value ( $q->param("revprop_${pred_name}") )
    {
	$is_set{$value} ++;
    }

    foreach my $val_key ( $q->param($param) )
    {
	my $value = $val_key;
	if( $coltype eq 'obj' )
	{
	    $value = Rit::Base::Resource->get( $val_key );
	}

	# Remove rel
	if( $has_val{$val_key} and not $is_set{$val_key} )
	{
	    my $arcs = Rit::Base::Arc->find({
		subj_id => $val_key,
		pred_id => $pred_id,
		obj_id  => $id,
	    });

	    foreach my $arc ( $arcs->as_array )
	    {
		$changes += $arc->remove;
	    }
	}
	# Add rel
	elsif( not $has_val{$val_key} and $is_set{$val_key} )
	{
	    my $arc = Rit::Base::Arc->create({
		subj_id => $val_key,
		pred_id => $pred_id,
		value   => $id,
	    }, \$changes );
	}
    }
    return $changes;
}


#########################################################################

=head2 authenticate_update

=cut

sub authenticate_update
{
    my( $node, $pred ) = @_;

    my $req = $Para::Frame::REQ;
    return 1 if $req->user->level >= 20;

    ref $pred or confess "pred should be an object";

    unless( $req->{'s'}{'allow_change'}{$node->id}{$pred->name->plain} )
    {
	debug datadump($req->{'s'}{'allow_change'},4);
	debug "node: ".$node->id;
	debug "pred: ".$pred->name->plain;
	use Text::Autoformat;
	my $desig = $node->desig;
	my $pred_name = $pred->name;
	throw('denied',
	      autoformat("Ert val innebär att fältet '$pred_name' ".
			 "för objektet '$desig' behöver uppdateras. ".
			 "Ni har dock inte tillgång till detta fält. "
			 )
	      );
    }
    return 1;
}

#########################################################################

=head2 resolve_obj_id

=cut

sub resolve_obj_id
{
    return map $_->id, shift->get_by_label( @_ );
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
################################ misc functions #########################

=head1 Functions

=cut

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

=head1 AUTOLOAD

  $n->$method()

  $n->$method( $proplim )

  $n->$method( $proplim, $arclim )

If C<$method> ends in C<_$arclim> there C<$arclim> is one of
C<direct>, C<indirect>, C<explicit> and C<implicit>, the param
C<$arclim> is set to that value and the suffix removed from
C<$method>.

If C<$proplim> or C<$arclim> are given, we return the result of
C<$n-E<gt>L<list|/list>( $proplim, $arclim )>. In the other case, we return the
result of C<$n-E<gt>L<prop|/prop>( $proplim, $arclim )>.

But if C<$method> begins with C<rev_> we instead call the
corresponding L</revlist> or L</revprop> correspondingly, with the
prefix removed.

Note that the L<Rit::Base::List/AUTOLOAD> will distribute the method
calls so that C<$list-E<gt>$method> will via this C<AUTOLOAD> call each
elements C<$method> and return the new list.

=cut

AUTOLOAD
{
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;
    return if $method =~ /DESTROY$/;
    my $node = shift;
    my $class = ref($node);

#    warn "Calling $method\n";
    confess "AUTOLOAD $node -> $method"
      unless UNIVERSAL::isa($node, 'Rit::Base::Resource');

#    die "deep recurse" if $Rit::count++ > 200;

    # Set arclim
    #
    if( $method =~ s/_(direct|indirect|explicit|implicit)$// )
    {
	$_[1] = $1;
    }


    # This part is returning the corersponging value in the object
    #
    my $res =  eval
    {
	if( $method =~ s/^rev_?// )
	{
	    if( @_ )
	    {
		return $node->revlist($method, @_);
	    }
	    else
	    {
		return $node->revprop($method);
	    }
	}
	else
	{
	    if( @_ )
	    {
		return $node->list($method, @_);
	    }
	    else
	    {
		return $node->prop($method);
	    }
	}
    };

#    debug "Res $res err $@";


    if( $@ )
    {
	my $err = catch($@);
	die sprintf "While calling %s for %s (%s):\n%s",
	  $method, $node->sysdesig, $node->code_class_desig, $err;
    }
    else
    {
	return $res;
    }
}

#########################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::List>,
L<Rit::Base::Search>,
L<Rit::Base::Time>

=cut
