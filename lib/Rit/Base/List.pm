#  $Id$  -*-cperl-*-
package Rit::Base::List;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource List class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::List

=cut

use Carp qw(carp croak cluck confess);
use strict;
use vars qw($AUTOLOAD);
use List::Util;


BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump  );
use Para::Frame::List;

use Rit::Base::Utils qw( is_undef valclean );

### Inherit
#
use base qw( Para::Frame::List Rit::Base::Object );

# Can't overload stringification. It's called in some stage of the
# process before it should.
# use overload '""'   => 'desig'; # Too much trouble...

#use overload 'cmp'  => 'cmp';
#use overload 'bool' => sub{ scalar @{$_[0]} };

=head1 DESCRIPTION

Represents lists of nodes.

Boolean operations are overloaded to L</size>. And C<cmp> are
overloaded to L</cmp>.

It's not compatible with L<Para::Frame::List> but may/should work as a
L<Template::Iterator>.

=cut


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

=head2 new

  $l->new( \@list )

This constructor takes an array ref, a L<Rit::Base::List> object or a
L<Para::Frame::List> object.  The Rit::Base::List object will be
returned unchanged. The Para::Frame::List object will be used for
extracting the elements and creating a new separate Rit::Base::List
object.

Returns the object.

Exceptions:

Dies on other type of input.

=cut

sub new
{
    my( $this, $listref ) = @_;
    my $class = ref($this) || $this;

    $listref ||= [];

    if( ref $listref eq "ARRAY" )
    {
	return $class->SUPER::new($listref);
    }
    elsif( ref $listref eq "Rit::Base::List" )
    {
	return $listref;
    }
    elsif( ref $listref eq "Para::Frame::List" )
    {
	return $class->SUPER::new([@$listref]);
    }
    else
    {
	die "Malformed listref: $listref";
    }
}

#######################################################################

=head2 init

=cut

sub init
{
    my( $l, $args ) = @_;
    # Add the materializer to the args
    $args->{'materializer'} = \&materialize;
}


#########################################################################
################################  Searches  #############################

=head1 Searches

Methods that returnes new modified lists

=cut

#######################################################################

=head2 find

  # Returns true/false
  $l->find( $value )

  # Returns true/false
  $l->find( \@list )

  # Returns a list
  $l->find( $key => $value )

  # Returns a list
  $l->find({ $key1 => $value1, $key2 => $value2, ... })

  # Returns the same object
  $l->find()

The first two forms calls L</contains> with the params and returns 1
or 0. It will call L</contains> for all cases where there is one
parameter that is not a hashref.

The second two forms find the elements in the list that has the given
properties and returns a new L<Para::Frame::List> with those elements.

For the last form, the same list object will be returned if there is
no param or if the first param is interpreted as false.

=head3 Details

The corresponding search method in L<Rit::Base::Search/modify>
should not be confused with this one, but we tries to proviede the
same syntax for making searches. Except that we here search in a given
list instead of the whole DB.

Only nodes that matches all the given properties are placed in the new
list.

If the key has dots ('.'), that sequence of methods will be called to
get the property to be compared with the value. For example, for the
key C<a.b.c> we will call $element->a. At least one of the elements
returned must match the value. A new find will be called as
$subelement->find('b.c' => $value ). This find will make the next step
by doing $subsubelement->b and $subsubsubelement->find('c' => $value
).

If the key begins with C<rev_> a reverse property will be looked for,
there the element is the subject and the value is the object.

If the key ends with C<_$matchtype> there C<$matchtype> is any of C<eq>,
C<exact>, C<like>, C<begins>, C<gt>, C<lt> and C<ne>, the
corresponding comparsion to the value will be used. The default is
C<eq> for mathing the elements those property is the same as the
value. C<ne> matches if the property is not the same as the
value. (The other matchtypes are not implemented here).

If the key begins with C<count_pred_> we counts the number of
properties the element has with the given predicate. Use C<rev_>
prefix for couting reverse properties. The value is compared with the
resulting number. For this comparsion, the matchtypes C<eq>, C<exact>,
C<ne>, C<gt> and C<lt> are supported, using numerical comparsion.

If the key begins with C<predor_> the rest of the key is expected to
be a list of predicate names separated by C<_-_>. There is a match if
at least one of the properties matches the value.

The value can be a C<*> for matching all values of the property. That
would be a test for the existence of that property.

The value can be a list of values. There is a match if at least one of
the values in the list matches. The list may be an arrayref or a
L<Rit::Base::List> or L<Para::Frame::List> object.

The actual comparsion for the C<eq> and C<ne> matchtypes are done by
the L<Rit::Base::Resource/has_value> method.

=head3 See also

The combination of this and other methods creates a very powerful
query language. See L</AUTOLOAD>, L</contains>,
L<Rit::Base::Resource/AUTOLOAD>, L<Rit::Base::Resource/has_value>,
L<Rit::Base::Resource/find_by_label> and L</sorted> for some of the
methods you can combine.

=head3 Example 1

  [% item.in_region(is='city').name %]

This is translated to

  [% item.list('in_region', {is='city'}).name %]

that in the next step translates to

  [% item.list('in_region').find({is='city'}).name %]

and will thus give the names of the regions the item is in that is
cities, ie; the name of the city of the item.

=head3 Example 2

  [% FOREACH arc IN node.revarc_list('has_member').find(subj={is=C.partner_group}).sorted %]

Iterates through the arcs that points to the node and is of the
predicate has_member, those subj node is a partner_group (as given in
the constant), sorted in the default way (on the arc desig).

=head3 Example 3

  [% node.is('organization') %]

This expands to

  [% node.list('is').find('organization') %]

which is the same as

  [% node.list('is').contains('organization') %]

and Contains uses L<Rit::Base::Resource/equals> for the comparsion
which in turn uses L<Rit::Base::Resource/find_simple> looking for a
node with the corresponding name. (Note that will not work if the name
is containd in a literal resource.)

This will return true if the node is an organization. That is; has an
arc C<node --is--E<gt> organization>.

=head3 Example 4

  [% node.has_subscription([sub_010, sub_030]).name %]

This expands to

  [% node.list('has_subscription').find([sub_010, sub_030]).name %]

TODO: Is example 4 correct..?


=cut

# TODO: make value nodes transparent.  Or are they? (haven't found any
# trouble)

sub find
{
    my( $self, $tmpl, $val ) = @_;
    my $class = ref $self;            # confess;

    my $DEBUG = debug();
    $DEBUG and $DEBUG --;

    # either name/value pairs in props, or one name/value
    if( defined $val )
    {
	$tmpl = {$tmpl, $val};
    }

    return $self unless $tmpl; # Support finds with no criterions


    # Two ways to use find:

    # This is a kind of has_value
    #
    unless( ref $tmpl and ref $tmpl eq 'HASH' )
    {
#	debug 2, "Does list contain $tmpl?";
	return $self->contains( $tmpl );
    }

    if( $DEBUG > 1 )
    {
	debug "Find: ".datadump($tmpl, 3);
    }


    # En empty tmpl matches the whole list
    return $self unless keys %$tmpl;

    # Takes a list and check each value in the list against the
    # template.  Returned those that matches the template.

    my @newlist;

  NODE:
    foreach my $node ( $self->nodes )
    {
	debug "Resource ".$node->id if $DEBUG;

	# Check each prop in the template.  All must match.  One
	# failed match and this $node in not placed in @newlist

      PRED:
	foreach my $pred_part ( keys %$tmpl )
	{
	    my $target_value =  $tmpl->{$pred_part};
	    if( $DEBUG )
	    {
		debug "  Pred $pred_part";
		debug "  Target $target_value (".ref($target_value).")";
	    }

	    # Target value may be a plain scalar or undef or an object !!!

	    if( $pred_part =~ /^(\w+)\.(.*)/ )
	    {
		my $pred_first = $1;
		my $pred_after = $2;

		debug "  Found a nested pred_part: $pred_first -> $pred_after" if $DEBUG;

		my $subres = $node->$pred_first;

		unless(  UNIVERSAL::isa($subres, 'Rit::Base::List') )
		{
		    unless( UNIVERSAL::isa($subres, 'ARRAY') )
		    {
			$subres = [$subres];
		    }
		    $subres = Rit::Base::List->new($subres);
		}

		my $found = 0;
		foreach my $subnode ( $subres->nodes )
		{
		    if( $subnode->find($pred_after, $target_value)->size )
		    {
			$found ++;
			last;
		    }
		}

		if( $found )
		{
		    next PRED;
		}

		next NODE;
	    }


	    unless( $pred_part =~ m/^(rev_)?(\w+?)(?:_(direct|indirect|explicit|implicit))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/x )
	    {
		$Para::Frame::REQ->result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
		unless( $pred_part )
		{
		    if( debug )
		    {
			debug "No pred_part?";
			debug "Template: ".datadump($tmpl,2);
			debug "For node ".$node->sysdesig;
		    }
		}
		die "wrong format in find: $pred_part\n";
	    }

	    my $rev    = $1;
	    my $pred   = $2;
	    my $arclim = $3;
	    my $clean  = $4 || 0;
	    my $match  = $5 || 'eq';
	    my $prio   = $6; #not used

	    if( $pred =~ s/^predor_// )
	    {
		my( @prednames ) = split /_-_/, $pred;
		my( @preds ) = map Rit::Base::Pred->get($_), @prednames;
		$pred = \@preds;
	    }

	    # match '*' handled below (but not matchtype 'exist')

	    if( ref $node eq 'Rit::Base::Arc' )
	    {
		## TODO: Handle preds in the form 'obj.scof'

		if( ($match ne 'eq' and $match ne 'begins') or
		    $arclim or $clean )
		{
		    confess "Not implemented: $pred_part";
		}

		debug "node is an arc" if $DEBUG;
		if( $pred =~ /^(obj|value)$/ )
		{
		    debug "  pred is value" if $DEBUG;
		    my $value = $node->value; # Since it's a pred
		    next PRED if $target_value eq '*'; # match all
		    if( ref $value )
		    {
			if( $match eq 'eq' )
			{
			    next PRED # Passed test
			      if $value->equals( $target_value );
			}
			elsif( $match eq 'begins' )
			{
			    confess "Matchtype 'begins' only allowed for strings, not ". ref $value
			      unless( ref $value eq 'Rit::Base::String' );

			    if( $value->begins( $target_value ) )
			    {
				next PRED; # Passed test
			    }
			    else
			    {
				next NODE; # Failed test
			    }
			}
			else
			{
			    confess "Matchtype not implemented: $match";
			}
		    }
		    else
		    {
			die "not implemented";
		    }
		}
		elsif( $pred eq 'subj' )
		{
		    debug "  pred is subj" if $DEBUG;
		    my $subj = $node->subj;
		    next PRED if $subj->equals( $target_value );
		}
		else
		{
		    debug "Asume pred '$pred' for arc is a node prop" if $DEBUG;
		}
	    }

	    if( $arclim )
	    {
		confess "arclim not implemented: $pred_part";
	    }

	    if( $pred =~ /^count_pred_(.*)/ )
	    {
		$pred = $1;

		if( $clean )
		{
		    confess "clean for count_pred not implemented";
		}

		if( $target_value eq '*' )
		{
		    $target_value = 0;
		    $match = 'gt';
		}

		debug "    count pred $pred" if $DEBUG;

		my $count;
		if( $rev )
		{
		    $count = $node->revcount($pred);
		    debug "      counted $count (rev)" if $DEBUG;
		}
		else
		{
		    $count = $node->count($pred);
		    debug "      counted $count" if $DEBUG;
		}

		my $matchtype =
		{
		 eq    => '==',
		 ne    => '!=',
		 gt    => '>',
		 lt    => '<',
		};

		if( my $cmp = $matchtype->{$match} )
		{
		    unless( $target_value =~ /^\d+/ )
		    {
			throw('action', "Target value must be a number");
		    }

		    if( eval "$count $cmp $target_value" )
		    {
			debug 3,"      MATCH";
			next PRED; # test passed
		    }
		}
		else
		{
		    confess "Matchtype '$match' not implemented";
		}

	    }
	    elsif( $match eq 'eq' )
	    {
		debug "    match is eq" if $DEBUG;
		if( $rev )
		{
		    debug "      (rev)\n" if $DEBUG;
		    # clean not sane in rev props
		    next PRED # Check next if this test pass
			if $target_value->has_value( $pred, $node, );
		}
		else
		{
		    next PRED # Check next if this test pass
			if $node->has_value( $pred, $target_value,
					     'eq', $clean);
		}
	    }
	    elsif( $match eq 'ne' )
	    {
		debug "    match is ne" if $DEBUG;
		if( $rev )
		{
		    debug "      (rev)" if $DEBUG;
		    # clean not sane in rev props
		    next PRED # Check next if this test pass
			unless $target_value->has_value( $pred, $node );
		}
		else
		{
		    # Matchtype is 'eq'. Result is negated here

		    next PRED # Check next if this test pass
			unless $node->has_value( $pred, $target_value,
						 'eq', $clean );
		}
	    }
	    elsif( ($match eq 'begins') or ($match eq 'like') )
	    {
		debug "    match is $match" if $DEBUG;
		if( $rev )
		{
		    confess "      rev not supported for matchtype $match";
		}

		next PRED # Check next if this test pass
		  if $node->has_value( $pred, $target_value, $match, $clean );
	    }
	    else
	    {
		confess "Matchtype '$match' not implemented";
	    }

	    # This node failed the test.  Check next node
	    next NODE;
	}
	debug "  Add node to list" if $DEBUG;
	push @newlist, $node;
    }
    debug "Return ".(scalar @newlist)." results" if $DEBUG;

    return Rit::Base::List->new(\@newlist);
}


#######################################################################

=head2 find_one

  $l->find_one({ $key1 => $value1, $key2 => $value2, ... })

Expects a hashref as the only param.

Calls L</find> with the hashref.

Returns: The first element found.

Exceptions:

If more than one match found:
  alternatives: Flera noder matchar kriterierna

If no matches are found:
  notfound: No nodes matches query

=cut

sub find_one
{
    my( $list, $props ) = @_;

    my $nodes = $list->find( $props );

    if( $nodes->[1] )
    {
	my $result = $Para::Frame::REQ->result;
	$result->{'info'}{'alternatives'}{'alts'} = $nodes;
	$result->{'info'}{'alternatives'}{'query'} = $props;
	throw('alternatives', "Flera noder matchar kriterierna");
    }

    unless( $nodes->[0] )
    {
	my $req = $Para::Frame::REQ;
	my $result = $req->result;
	my $site = $req->site;
	$result->{'info'}{'alternatives'}{'alts'} = undef;
	$result->{'info'}{'alternatives'}{'query'} = $props;
	$result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
	my $home = $req->site->home_url_path;
	$req->set_error_response($home.'/node_query_error.tt');
	throw('notfound', "No nodes matches query");
    }

    return $nodes->[0];
}


#######################################################################

=head2 direct

  $l->direct

Should only be called for lists of L<Rit::Base::Arc> elements.

Returns: A new list with the arcs that are L<Rit::Base::Arc/direct>

This method is only an optimization, for the same effect would be get
via L</AUTOLOAD>.

=cut

sub direct  # Exclude indirect arcs
{
#    if( $_[0][0] and  not (ref $_[0][0] eq 'Rit::Base::Arc') )
#    {
#	confess "->direct() called in wrong context: OBJ $_[0] CONTENT @{$_[0]}\n";
#    }
#    warn sprintf("List %s has %d nodes. The first is %s\n",
#		 $_[0], scalar(@{$_[0]}), $_[0][0] );

    $_[0]->new([grep $_->direct, @{$_[0]}]);
}

#######################################################################

=head2 explicit

  $l->explicit

Should only be called for lists of L<Rit::Base::Arc> elements.

Returns: A new list with the arcs that are L<Rit::Base::Arc/explicit>

This method is only an optimization, for the same effect would be get
via L</AUTOLOAD>.

=cut

sub explicit  # Exclude implicit arcs
{
    $_[0]->new([grep $_->explicit, @{$_[0]}]);
}

#######################################################################

=head2 limit

  $list->limit()

  $list->limit( $limit )

  $list->limit( 0 )

Limit the number of elements in the list. Returns the first C<$limit>
items.

Default C<$limit> is 10.  Set the limit to 0 to get all items.

Returns: A List with the first C<$limit> items.

=cut

sub limit
{
    my( $list, $limit ) = @_;

    $limit = 10 unless defined $limit;
    return $list if $limit < 1;
    return $list if $list->size <= $limit;
    return $list->new( [@{$list}[0..($limit-1)]] );
}

#######################################################################

=head2 sorted

  $list->sorted()

  $list->sorted( $prop )

  $list->sorted( $prop, $dir )

  $list->sorted( [$prop1, $prop2, ...] )

  $list->sorted( [$prop1, $prop2, ...], $dir )

  $list->sorted( { on => $prop1, dir => $dir } )

  $list->sorted( [{ on => $prop1, dir => $dir },
                  { on => $prop2, dir => $dir2 },
                  ...
                 ] )

Returns a list of nodes, sorted by the selected proprty of the node.

The default sorting property is C<desig>.

C<$dir> is the direction of the sort.  It can be C<asc> or C<desc> and
defaults to C<asc>. It can also be C<exists> (for a SQL search).

C<$prop> can be of the form C<p1.p2.p3> which translates to a property
lookup in several steps.  For example; C<$arcs->sorted('obj.name')>

The type of sort (numeric or string) id secided by the predicate type.
Numeric predicates will give numeric sorts.

Examples:

Sort all predicates on id:

  my $predlist = Rit::Base::Pred->find->sorted('id');

Loop over the name arcs of a node, sorted by firstly on the language
code and secondly on the weight in reverse order:

  [% FOREACH arc IN n.arc_list('name').sorted(['obj.language.code',{on='obj.weight' dir='desc'}]) %]

Returns:

A List object with 0 or more Resources.

Exceptions:

Dies if given faulty parameters.

=cut

sub sorted
{
    my( $list, $args, $dir ) = @_;

    my $DEBUG = 0;

    $args ||= 'desig';

    unless( ref $args and ( ref $args eq 'ARRAY' or
			    ref $args eq 'Rit::Base::List' )
	  )
    {
	$args = [ $args ];
    }

    if( $dir )
    {
	unless( $dir =~ /^(asc|desc)$/ )
	{
	    die "direction '$dir' out of bound";
	}

	for( my $i = 0; $i < @$args; $i++ )
	{
	    unless( ref $args->[$i] eq 'HASH' )
	    {
		$args->[$i] =
		{
		 on => $args->[$i],
		 dir => $dir,
		};
	    }
	}
    }

    $list->materialize_all; # for sorting on props

    my @sort;
    for( my $i = 0; $i < @$args; $i++ )
    {
#	debug 3, "i: $i";
#	debug 3, sprintf("args: %d\n", scalar @$args);
	unless( ref $args->[$i] eq 'HASH' )
	{
	    $args->[$i] =
	    {
		on => $args->[$i],
	    };
	}

	$args->[$i]->{'dir'} ||= 'asc';

	# Find out if we should do a numeric or literal sort
	#
	my $on =  $args->[$i]->{'on'};
	if( ref $on )
	{
	    die "not implemented ($on)";
	}
	$on =~ /([^\.]+)$/; #match last part
	my $pred_str = $1;
	my $cmp = 'cmp';

	# Silently ignore dynamic props (that isn't preds)
	if( my $pred = Rit::Base::Pred->find_by_label( $pred_str, 1 ) )
	{
	    if( $pred->coltype eq 'valint' )
	    {
		$cmp = '<=>';
	    }
	}

	$args->[$i]->{'cmp'} = $cmp;

	if( $args->[$i]->{'dir'} eq 'desc')
	{
#	    push @sort, "\$b->[$i] cmp \$a->[$i]";
	    push @sort, "\$props[$i][\$b] $cmp \$props[$i][\$a]";
	}
	else
	{
#	    push @sort, "\$a->[$i] cmp \$b->[$i]";
	    push @sort, "\$props[$i][\$a] $cmp \$props[$i][\$b]";
	}
    }
    my $sort_str = join ' || ', @sort;

#    debug 3, "--- SORTING: $sort_str";

    my @props;
    foreach my $item ( $list->as_array )
    {
	debug 2, sprintf("  add item %s", $item->sysdesig);
	for( my $i=0; $i<@$args; $i++ )
	{
	    my $method = $args->[$i]{'on'};
#	    debug 3, sprintf("    arg $i: %s", $args->[$i]{'on'});
	    my $val = $item;
	    foreach my $part ( split /\./, $method )
	    {
		$val = $val->$part;
#		debug 3,sprintf("      -> %s", $val);
	    }

	    # Make it a string
	    $val = $val->loc if ref $val;

#	    debug 3, sprintf("      => %s", $val);

	    push @{$props[$i]}, $val;
#	    push @{$props[$i]}, $item->$method;
	}
    }

    if( debug>2 )
    {
	debug "And the props is: \n";
	for( my $i=0; $i<=$#$list; $i++ )
	{
	    my $out = "  ".$list->[$i]->desig.": ";
	    for( my $x=0; $x<=$#props; $x++ )
	    {
		$out .= $props[$x][$i] .' - ';
	    }
	    debug $out;
	}
    }

    # The Schwartzian transform:
    # This method should be fast and efficient. Read up on it
    my @new = @{$list}[ eval qq{ sort { $sort_str } 0..$#$list } ];
    die "Sort error for '$sort_str': $@" if $@; ### DEBUG

    return $list->new( \@new );
}

#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

#######################################################################

=head2 get

  $l->get(@params)

Calls L</find> with the params and expects just one match.

Returns:

A L<Rit::Base::Resource> object.

Exceptions:

See L<Rit::Base::Resource/get_by_label>

=cut

sub get
{
    my $list = shift->find(@_);

    return Rit::Base::Resource->get_by_label($list);
}


#######################################################################

=head2 as_string

  $l->as_string

Deprecated...

=cut

sub as_string
{
    my ($self) = @_;

    unless( ref $self )
    {
#	warn "  returning $self\n";
	return $self;
    }

    my $list = $self->as_list;

    my $val = "";

    if( $#$list ) # More than one element
    {
	for( my $i = 0; $i<= $#$list; $i++)
	{
	    $val .= "* ";
	    $val .= $list->[$i]->as_string;
	    $val .= "\n";
	}
    }
    else
    {
	$val .= $self->[0];
    }

    return $val;
}


#######################################################################

=head2 literal

  $l->literal

Selects the best literal from the nodes.  The list could be diffrent
translations of a text.

It could also be a list of names, each having its own translations.

Returns: A string

=cut

sub literal
{
    my( $list ) = @_;

    if( @$list == 1 )
    {
	$list->[0]->literal;
    }
    elsif( @$list == 0 )
    {
	return is_undef->as_string;
    }
    else
    {
#	confess "More than one value returned: ".$list->desig;
#	debug "Tryning to turn the list to a literal\n";
	return $list->loc;
    }
}


#######################################################################

=head2 loc

  $l->loc

  $l->loc(@params)

Choose a value, based on language option.  After that; sort on weight.

Params are given to L<Para::Frame::L10N/compute>.

The language priority should have been set by
L<Para::Frame::Resource/set_language> for the request.

Returns: A string

=cut

sub loc
{
    my $list = shift;

    my $req = $Para::Frame::REQ;

    my %alts;
    my $default;

    debug 3,"Choosing among ".(scalar @$list)." values";

    foreach my $item ( @$list )
    {
	# TODO: correct?
	if( ref $item and UNIVERSAL::isa($item, 'Rit::Base::Resource::Compatible') )
	{
	    my $langs = $item->list('language');
	    if( @$langs )
	    {
		foreach my $lang ( @$langs )
		{
		    next unless $lang;
		    my $code = $lang->code->plain;
		    push @{$alts{$code}}, $item;
		    unless( $code )
		    {
			throw('dbi', sprintf("Language %s does not have a code", $lang->sysdesig));
		    }
		    debug 4,"Lang $code: $item->{'id'}";
		}
	    }
	    else
	    {
		push @{$alts{'c'}}, $item;
#		debug 4,"Lang c: $item->{'id'} ($langs)";
	    }
	}
	else
	{
	    $default = $item;
	    debug 3,"No translation";
	}
    }

    # TODO: Chose value even with no language priority

    foreach my $lang ( $req->language->alternatives, 'c' )
    {
#	debug "Checking lang $lang";
	# Try to handle the cases in order of commonality
	next unless $alts{$lang} and @{$alts{$lang}};
	unless( $alts{$lang}[1] )
	{
	    # Not using ->value, since this may be a Literal
	    return $alts{$lang}[0]->loc(@_);
	}

	# Order by highest weight
	my %list;
	foreach( @{$alts{$lang}} )
	{
	    my $weight = $_->weight->literal || 0;
	    $list{ $weight } = $_;
	}

	debug 3,"Returning (one) literal with highest weight";
	# Not using ->value, since this may be a Literal
	return $list{ List::Util::max( keys %list ) }->loc(@_);
    }

    ## Set default.  (*any* default)
    unless( defined $default )
    {
	if( $alts{'c'}[0] )
	{
	    $default = $alts{'c'}[0];
	}
    }
    unless( defined $default )
    {
	foreach my $lang ( keys %alts )
	{
	    if( $alts{$lang}[0] )
	    {
		$default = $alts{$lang}[0];
		last;
	    }
	}
    }

    if( defined $default )
    {
	# Special handling of Literal just to catch some errors
	if( UNIVERSAL::isa($default, 'Rit::Base::Literal' ) )
	{
	    return $default->loc(@_);
	}
	else
	{
	    # Not using ->value, since this may be a Literal
	    return $default->loc(@_);
	}
    }
    else
    {
	# Was this an empty list to begin with?
	unless( $list->size )
	{
	    return "";
	}

	die "No default found";
    }
}

#######################################################################

=head2 desig

  $l->desig

Return a SCALAR string with the elements designation concatenated with
C<' / '>.

See L<Rit::Base::Object/desig>

=cut

sub desig
{
#    warn "Stringifies object ".ref($_[0])."\n"; ### DEBUG
    return join ' / ', map $_->desig, $_[0]->nodes;
}

#######################################################################

=head2 sysdesig

  $l->sysdesig

Return a SCALAR string with the elements sysdesignation concatenated with
C<' / '>.

See L<Rit::Base::Object/sysdesig>

=cut

sub sysdesig
{
#    warn "Stringifies object ".ref($_[0])."\n"; ### DEBUG
    return join ' / ', map $_->sysdesig, $_[0]->nodes;
}

######################################################################

=head2 is_list

  $l->is_list

This is a list.

Returns: 1

=cut

sub is_list
{
    return 1;
}


#######################################################################

=head2 nodes

  $l->nodes(@args)

Just as L</as_list> but regards the SCALAR/ARRAY context.

=cut

sub nodes
{
#    warn " --> wantarray?\n"; ### DEBUG
    if( wantarray )
    {
	return @{shift->as_list(@_)};
    }
    else
    {
	return shift->as_list(@_);
    }
}

#######################################################################

=head2 is_true

  $l->is_true

Returns 1 if the list has more than one element or if the one
element is true.

Otherwise returns 0;

=cut

sub is_true
{
    return 1 if @{$_[0]};
    return 0 unless $_[0][0];

    if( ref $_[0][0] )
    {
	return $_[0][0]->is_true;
    }

    return $_[0][0] ? 1 : 0;
}

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut


#######################################################################

=head2 contains

  $list->contains( $node )

  $list->contains( $list2 )


Returns true if the list contains all mentioned items supplied as a
list, list objekt or single item.

Each element is compared with L<Para::Frame::Object/equals>.

TODO: Use iteration with the iterators

Returns: A boolean value

=cut

sub contains
{
    my( $list, $tmpl ) = @_;

    if( ref $tmpl )
    {
	if( ref $tmpl eq 'Rit::Base::List' )
	{
	    foreach my $val (@{$tmpl->as_list})
	    {
		return 0 unless $list->contains($val);
	    }
	    return 1;
	}
	elsif( ref $tmpl eq 'ARRAY' )
	{
	    foreach my $val (@$tmpl )
	    {
		return 0 unless $list->equals($val);
	    }
	    return 1;
	}
	elsif( ref $tmpl eq 'Para::Frame::List' )
	{
	    foreach my $val ($tmpl->as_list)
	    {
		return 0 unless $list->contains($val);
	    }
	    return 1;
	}
	elsif( ref $tmpl eq 'HASH' )
	{
	    die "Not implemented: $tmpl";
	}
    }

    # Default for simple values and objects:

    foreach my $node ( @{$list->as_list} )
    {
	return $node if $node->equals($tmpl);
    }
    return undef;
}


#######################################################################

=head2 contains_any_of

  $list->contains_any_of( $node )

  $list->contains_any_of( $list2 )


Returns true if the list contains at least one of the mentioned items
supplied as a list, list objekt or single item.

Each element is compared with L<Para::Frame::Object/equals>.

TODO: Use iteration with the iterators

Returns: A boolean value

=cut

sub contains_any_of
{
    my( $list, $tmpl ) = @_;

    my $DEBUG = 0;

    if( debug > 1 )
    {
	debug "Checking list with content:";
	foreach my $node ( $list->nodes )
	{
	    debug sprintf "  * %s", $node->sysdesig;
	}
    }

    if( ref $tmpl )
    {
	if( ref $tmpl eq 'Rit::Base::List' )
	{
	    foreach my $val (@{$tmpl->as_list})
	    {
		debug 2, sprintf "  check list item %s", $val->sysdesig;
		return 1 if $list->contains_any_of($val);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'ARRAY' )
	{
	    foreach my $val (@$tmpl )
	    {
		debug 2, sprintf "  check array item %s", $val->sysdesig;
		return 1 if $list->contains_any_of($val);
	    }
	    debug 2, "    failed";
	    return 0;
	}
	elsif( ref $tmpl eq 'Para::Frame::List' )
	{
	    foreach my $val ($tmpl->as_list)
	    {
		debug 2, sprintf "  check list item %s", $val->sysdesig;
		return 1 if $list->contains_any_of($val);
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

    foreach my $node ( @{$list->as_list} )
    {
	debug 2, sprintf "  check node %s", $node->sysdesig;
	debug 2, sprintf "  against %s", $tmpl->sysdesig;
	return $node if $node->equals($tmpl);
    }
    debug 2,"    failed";
    return undef;
}


#######################################################################

=head2 has_value

  $l->has_value($val)

To be used for lists of literal resources.

This calls translates to

  $l->find({value => $val })

See L</find>.

=cut

# TODO: Shouldn't this do the same as Resource->has_value() ???

sub has_value
{
    shift->find({value=>shift});
}

#######################################################################

=head2 materialize

=cut

sub materialize
{
    my( $l, $i ) = @_;

    confess "FIXME" unless defined $i;

    my $elem = $l->{'_DATA'}[$i];
    if( ref $elem )
    {
	return $elem;
    }
    else
    {
	my $obj = Rit::Base::Resource->get( $elem );
	if( debug > 1 )
	{
	    debug "Materializing element $i -> ".$obj->sysdesig;
	}
	return $obj;
    }
}

#######################################################################

=head2 initiate_rel

  $l->initiate_rel

Calls L<Para::Frame::Resource/initiate_rel> for each element.

Returns: C<$l>

=cut

sub initiate_rel
{
    foreach( @{$_[0]} )
    {
	$_->initiate_rel;
    }
    return $_[0];
}

#######################################################################

=head2 cmp

  $l->cmp( $val )

Comparing something with the list with cmp or <=> gives an is_undef
obj.

Returns: L<Rit::Base::Undef>

=cut

sub cmp
{
#    warn "Compares $_[0] to $_[1]\n";
    return is_undef;
}

#######################################################################

=head2 equals

  $l->equals( $value )

Check each of the elements with the value

Returns: A boolean value

=cut

sub equals
{
    foreach( $_[0]->nodes )
    {
	return 0 unless $_->equals($_[1]);
    }

    return 1;
}

#######################################################################

=head2 get_first_nos

Same as L<Para::Frame::List/get_first_nos>, but returns
L<Rit::Base::Undef> if no element found

=cut

sub get_first_nos
{
    my( $val, $err ) = $_[0]->get_first;
    if( $err )
    {
	return is_undef;
    }
    else
    {
	return $val;
    }
}

#######################################################################

=head2 get_next_nos

Same as L<Para::Frame::List/get_next_nos>, but returns
L<Rit::Base::Undef> if no element found

=cut

sub get_next_nos
{
    my( $val, $err ) = $_[0]->get_next;
    if( $err )
    {
	return is_undef;
    }
    else
    {
	return $val;
    }
}

#########################################################################
################################  Private methods  ######################

=head1 AUTOLOAD

  $l->$method( @args )

For all method calls not catched by defined methods in this class,
this AUTOLOAD is used.

All undefined values and L<Rit::Base::Undef> objects are filtered out.
All nonobjects are copied to the result list but ignored. For all
other objects, the C<$method> are called and given the C<@args> and
the result are placed in a resulting list.

If no elements comes through, a L<Rit::Base::Undef> is returned.

We guess the content of the list by the first element, defining the
element type. If it's not a type of object, its taken to be
L<Rit::Base::Literal>.

If the element type is L<Rit::Base::List> we flatten the list as much
as possible to just get a single list of values rather than a list of
lists.

If the element type is L<Rit::Base::Literal>, all elements in the
resulting list are converted to L<Rit::Base::Literal> objects and
returned.  But if the list only has one value, it's returned without
any convertion.

For the element types L<Rit::Base::Arc>, L<Rit::Base::Resource> and
L<Rit::Base::Time>, we retun a new L<Rit::Base::List> with the
elements.

TODO: Msake it work with the new subclass strutcture with subclasses
of L<Rit::Base::Object>.

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
    my $propname = $AUTOLOAD;
    my $self = shift;
    my $class = ref($self) eq 'Rit::Base::List'
	or confess "Wrong class: ".ref($self)."\n";
    my $thingtype = ref $self;

    debug 3, "List autoloading $propname for $thingtype";
    if( debug>3 )
    {
	debug "LIST params ".datadump(\@_,2);
	debug "LIST IN ".datadump($self,2);
    }

    my @templist = ();
    foreach my $elem ( @$self )
    {
	next unless defined $elem;
	if( ref $elem )
	{
	    my $res = $elem->$propname(@_);
	    if( UNIVERSAL::isa( $res, 'Rit::Base::List' ) )
	    {
		push @templist, @$res;
	    }
	    else
	    {
		push @templist, $res;
	    }
	}
	else
	{
	    push @templist, $elem;
	}
    }


    my @list = ();
    foreach( @templist )
    {
	next unless defined;
	if( UNIVERSAL::isa( $_, 'Rit::Base::Object::Compatible' ) )
	{
	    next unless $_->defined;
	}
	push @list, $_;
    }


#    my @list = (
#		grep{ defined and ((ref and $_->defined) or not ref ) }
#		map{ ref $_ ? $_->$propname(@_) : $_ }
#		grep defined,
#		@$self
#		);

    if( debug > 3 )
    {
	debug( "LIST WASHED ".datadump(\@list,2) );
    }
    elsif( debug > 2 )
    {
	debug( "LIST WASHED: @list" );
    }


    unless( @list )
    {
	debug 3, "  No value returned";
	return is_undef;
    }


    # determine type of elements returned
    my $eltype = ref $list[0];

    unless( $eltype )
    {
	# Literal strings
	$eltype = 'Rit::Base::Literal';
    }

    if( $eltype eq 'Rit::Base::List' )
    {
	if( $list[1] )
	{
	    debug 1, "  Returned a list of lists: flattening";
	    return $self->new( flatten_list( \@list ) );
	}
	else
	{
	    debug 3, "  Return the one node";
	    return $list[0];
	}
    }
    elsif( UNIVERSAL::isa($eltype, 'Rit::Base::Literal' ) )
    {
	# Asume all elements is literals (or maby valuenodes)

	if( $list[1] )
	{
	    debug 3, "  About to create list of literals";
	    foreach( @list )
	    {
		### CHANGE THE LIST DIRECTLY
		$_ = Rit::Base::Literal->new( $_ ) unless ref;
	    }
	    debug 3,"  Return list of literals";
	    return $self->new(\@list);
	}
	else
	{
	    debug 3, "  Return the one literal";
	    return $list[0];
	}
    }
    elsif( UNIVERSAL::isa($eltype, 'Rit::Base::Resource::Compatible' ) )
    {
	debug 3, "  Return list of resources";
	return $self->new(\@list);
    }
    else
    {
	confess "Autoloaded $propname returned a list of $eltype (may need to fix this code)".datadump(\@list,2);
    }


#    my $item = $self->[0];
#    return( ref $item ? $item->$propname(@_) : $item );
}

sub flatten_list
{
    my( $list_in, $seen ) = @_;

    $list_in  ||= [];
    $seen     ||= {};

    my @list_out;

    foreach my $elem ( @$list_in )
    {
	if( ref $elem )
	{
	    if( ref $elem eq 'Rit::Base::List' )
	    {
		push @list_out, @{ flatten_list($elem, $seen) };
	    }
	    else
	    {
		unless( $seen->{ $elem->syskey } ++ )
		{
		    push @list_out, $elem;
		}
	    }
	}
	else
	{
	    unless( $seen->{ $elem } ++ )
	    {
		push @list_out, $elem;
	    }
	}
    }
    return \@list_out;
}

#######################################################################

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
