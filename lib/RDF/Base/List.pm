package RDF::Base::List;
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

RDF::Base::List

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::List RDF::Base::Object );
use vars qw($AUTOLOAD);

use Carp qw(carp croak cluck confess);
use List::Util;
use Scalar::Util qw(blessed);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump trim  );
use Para::Frame::List;
use Para::Frame::Logging;

use RDF::Base::Arc::Lim;
use RDF::Base::Utils qw( is_undef valclean query_desig parse_propargs parse_query_value );


# Can't overload stringification. It's called in some stage of the
# process before it should.

#use overload 'cmp'  => 'cmp';
#use overload 'bool' => sub{ scalar @{$_[0]} };
use overload
  '""'         => 'desig',
  '.'          => 'concatenate_by_overload',
  'cmp'        => 'cmp_by_overload',
  'fallback'   => 0;            # This and NOTHING else!


=head1 DESCRIPTION

Represents lists of nodes.

Boolean operations are overloaded to L</size>. And C<cmp> are
overloaded to L</cmp>.

It's not compatible with L<Para::Frame::List> but may/should work as a
L<Template::Iterator>.

=cut


##############################################################################
################################  Constructors  #######################

=head1 Constructors

These can be called with the class name or any List object.

=cut

##############################################################################

=head2 new

  $l->new( \@list, \%args )

This constructor takes an array ref, a L<RDF::Base::List> object or a
L<Para::Frame::List> object.  The RDF::Base::List object will be
returned unchanged. The Para::Frame::List object will be used for
extracting the elements and creating a new separate RDF::Base::List
object.

If the first argument is undef, the list will be marked as
unpopulated.

The special arg C<initiate_rel> will cause the materialization of the
arc to initialize all rel properties directly


Returns the object.

Exceptions:

Dies on other type of input.

=cut

sub new
{
    my( $this, $listref, $args ) = @_;
    my $class = ref($this) || $this;

    if ( (ref $listref eq "ARRAY") or (not defined $listref) )
    {
        return $class->SUPER::new($listref, $args);
    }
    elsif ( ref $listref eq "RDF::Base::List" )
    {
        return $listref;
    }
    elsif ( ref $listref eq "Para::Frame::List" )
    {
        return $class->SUPER::new([@$listref], $args);
    }
    else
    {
        confess "Malformed listref: $listref";
    }
}


##############################################################################

=head2 init

=cut

sub init
{
    my( $l, $args ) = @_;

    ### CHANGED: now explicitly adding materializer in
    ###          in RDF::Base::Search->execute
    #
    # Add the materializer to the args
    #$args->{'materializer'} ||= \&materialize;

    $l->{'rb_initiate_rel'} = $args->{'initiate_rel'};
}


##############################################################################
################################  Searches  ###########################

=head1 Searches

Methods that returnes new modified lists

=cut

##############################################################################

=head2 find

  # Returns true/false
  $l->find( $value, \%args )

  # Returns true/false
  $l->find( \@list, \%args )

  # Returns a list
  $l->find( \%proplim, \%args )

  # Returns the same object
  $l->find()

The first two forms calls L</contains> with the params and returns 1
or 0. It will call L</contains> for all cases where the first
parameter is not a hashref.

The third form finds the elements in the list that meets the given
proplim, using L<RDF::Base::Resource/meets_proplim> and returns a new
L<Para::Frame::List> with those elements.

For the last form, the same list object will be returned if the first
param is undef or an empty hashref, regardless of C<\%args>.

=head3 Details

The corresponding search method in L<RDF::Base::Search/modify>
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

If the key begins with C<count_pred_> we count the number of
properties the element has with the given predicate. Use C<rev_>
prefix for couting reverse properties. The value is compared with the
resulting number. For this comparsion, the matchtypes C<eq>, C<exact>,
C<ne>, C<gt> and C<lt> are supported, using numerical comparsion.

If the key begins with C<predor_> the rest of the key is expected to
be a list of predicate names separated by C<_-_>. There is a match if
at least one of the properties matches the value.

If the key is C<not>, the value should be a C<\%proplim> that is
negated.

The value can be a C<*> for matching all values of the property. That
would be a test for the existence of that property.

The value can be a list of values. There is a match if at least one of
the values in the list matches. The list may be an arrayref or a
L<RDF::Base::List> or L<Para::Frame::List> object.

The actual comparsion for the C<eq> and C<ne> matchtypes are done by
the L<RDF::Base::Resource/has_value> method.

If an element in the list is a L<RDF::Base::List>, it will be searchd
in the same way.

The supported args are:

  private?
  clean
  arclim

unique_arcs_prio filter is NOT used here.  Do the filtering before or
after this find.

=head3 See also

The combination of this and other methods creates a very powerful
query language. See L</AUTOLOAD>, L</contains>,
L<RDF::Base::Resource/AUTOLOAD>, L<RDF::Base::Resource/has_value>,
L<RDF::Base::Resource/find_by_anything> and L</sorted> for some of the
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

and Contains uses L<RDF::Base::Resource/equals> for the comparsion
which in turn uses L<RDF::Base::Resource/find_simple> looking for a
node with the corresponding name. (Note that will not work if the name
is containd in a literal resource.)

This will return true if the node is an organization. That is; has an
arc C<node --is--E<gt> organization>.

=head3 Example 4

  [% node.has_subscription([sub_010, sub_030]).name %]

This expands to

  [% node.list('has_subscription').find([sub_010, sub_030]).name %]

TODO: Is example 4 correct..?

=head3 See also

L<Para::Frame::List/complement> for finding what is not matching criterions

=cut

sub find
{
    my( $l, $tmpl, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(4);

    my $DEBUG = Para::Frame::Logging->at_level(3);

#    # either name/value pairs in props, or one name/value
#    if( not(ref $tmpl) and $args )
#    {
#	$tmpl = {$tmpl, $args};
#	undef $args;
#    }

    # Support finds with no criterions
    return $l unless $tmpl;     # Handling tmpl={} later


    # Two ways to use find:

    # This is a kind of has_value
    #
    unless( ref $tmpl and ref $tmpl eq 'HASH' )
    {
#	debug 2, "Does list contain $tmpl?";
        return $l->contains( $tmpl, $args );
    }

    if ( $tmpl->{'arclim'} or $tmpl->{'res'} )
    {
        confess datadump(\@_,2);
    }

    if ( $DEBUG > 1 )
    {
        debug "QUERY ".query_desig($tmpl);
        debug  "ON LIST ".$l->sysdesig;
    }


    # En empty tmpl matches the whole list (regardless of args)
    unless( keys %$tmpl )
    {
        return $l;
    }

    # Takes a list and check each value in the list against the
    # template.  Returned those that matches the template.

    if ( $l->size > 100 )
    {
        $Para::Frame::REQ->note(sprintf "Filtering %d nodes", $l->size);
    }


    my @newlist;
    my $cnt = 0;
    my $index = $l->index;
    my( $node, $error ) = $l->get_first;

  NODE:
    while (! $error )
    {
        # Check each prop in the template.  All must match.  One
        # failed match and this $node in not placed in @newlist

        if ( not $node )
        {
            # just drop it
        }
        elsif ( $node->is_list )
        {
            CORE::push @newlist, $node->find( $tmpl, $args )->as_array;
        }
        elsif ( $node->meets_proplim( $tmpl, $args ) )
        {
            CORE::push @newlist, $node;
        }

        ( $node, $error ) = $l->get_next;

        if ( not $l->count % 500 )
        {
            $Para::Frame::REQ->note(sprintf "%5d", $l->count);
            $Para::Frame::REQ->may_yield;
        }
    }

    $l->set_index( $index );

    debug "Return ".(scalar @newlist)." results for ".
      query_desig($tmpl) if $DEBUG;

    my $class = ref $l;

    my $list_props = $l->clone_props;
    return $class->new(\@newlist, $list_props);
}


##############################################################################

=head2 find_one

  $l->find_one({ $key1 => $value1, $key2 => $value2, ... }, \%args )

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
    my( $list, $tmpl, $args ) = @_;

    my $nodes = $list->find( $tmpl, $args );

    if ( $nodes->[1] )
    {
        my $result = $Para::Frame::REQ->result;
        $result->{'info'}{'alternatives'}{'alts'} = $nodes;
        $result->{'info'}{'alternatives'}{'query'} = $tmpl;
        $result->{'info'}{'alternatives'}{'args'} = $args;
        throw('alternatives', "Flera noder matchar kriterierna");
    }

    unless( $nodes->[0] )
    {
        my $req = $Para::Frame::REQ;
        my $result = $req->result;
        my $site = $req->site;
        $result->{'info'}{'alternatives'}{'alts'} = undef;
        $result->{'info'}{'alternatives'}{'query'} = $tmpl;
        $result->{'info'}{'alternatives'}{'args'} = $args;
        $result->{'info'}{'alternatives'}{'trace'} = Carp::longmess;
        my $home = $req->site->home_url_path;
        $req->set_error_response($home.'/rb/node/query_error.tt');
        throw('notfound', "No nodes matches query");
    }

    return $nodes->[0];
}


##############################################################################

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


##############################################################################

=head2 sorted

  $list->sorted()

  $list->sorted( $prop )

  $list->sorted( $prop, $dir )

  $list->sorted( [$prop1, $prop2, ...] )

  $list->sorted( [$prop1, $prop2, ...], $dir )

  $list->sorted( { on => $prop1, dir => $dir } )

  $list->sorted( [{ on => $prop1, dir => $dir },
                  { on => $prop2, dir => $dir2, cmp => '<=>' },
                  ...
                 ] )

Returns a list of nodes, sorted by the selected proprty of the node.

The default sorting property is C<desig>.

C<$dir> is the direction of the sort.  It can be C<asc> or C<desc> and
defaults to C<asc>. It can also be C<exists> (for a SQL search).

C<$prop> can be of the form C<p1.p2.p3> which translates to a property
lookup in several steps.  For example; C<$arcs->sorted('obj.name')>

The type of sort (numeric or string) is decided by the predicate type.
Numeric predicates will give numeric sorts. If the sort property isn't
a predicate, we can tell the type of value by the C<cmp> argument.

Examples:

Sort all predicates on id:

  my $predlist = RDF::Base::Pred->find->sorted('id');

Loop over the name arcs of a node, sorted by firstly on the is_of_language
code and secondly on the weight in reverse order:

  [% FOREACH arc IN n.arc_list('name').sorted(['obj.is_of_language.code',{on='obj.weight' dir='desc'}]) %]

Returns:

A List object with 0 or more Resources, with properties cloned from
the soruce list.

If sort key is the same, the same object is returned without sorting

Exceptions:

Dies if given faulty parameters.

=cut

sub sorted
{
    my( $list, $sortargs, $dir_in, $args_in ) = @_;

    # sort_str, if given MUST match sortargs

    my $DEBUG = 0;

    return $list if $list->size < 2;

    my( $sort_str, $sort_key, $dir );

    if ( ref $dir_in eq 'HASH' )
    {
        $sort_str = $dir_in->{'sort_str'};
        $sort_key = $dir_in->{'sort_key'};
        $dir      = $dir_in->{'dir'};

        unless( $dir or $sort_str or $sort_key or $args_in )
        {
            $args_in = $dir_in;
            $dir_in = undef;
        }
    }
    elsif ( $dir_in )
    {
        $dir = $dir_in;
    }

    unless( $sort_key )
    {
        ( $sortargs, $sort_str, $sort_key ) =
          $list->parse_sortargs( $sortargs, $dir );
    }

    if ( $sort_key eq ($list->{'sorted_on_key'}||'') )
    {
        return $list;
    }


    $list->materialize_all;     # for sorting on props

    my( $args ) = parse_propargs($args_in);


    debug "--- SORTING: $sort_str" if $DEBUG;


    my $size = $list->size;
    if ( $size > 100 )
    {
        $Para::Frame::REQ->note(sprintf "Sorting %d nodes", $size);
    }


    my @props;

    my( $item, $error ) = $list->get_first;
    while (! $error )
    {
        $item->{'sort_arg'} = [];
        debug sprintf("  add item %s", $item->safedesig) if $DEBUG;
        for ( my $i=0; $i<@$sortargs; $i++ )
        {
            my $method = $sortargs->[$i]{'on'};
            debug sprintf("    arg $i: %s", $sortargs->[$i]{'on'}) if $DEBUG;
            my $val = $item;
            foreach my $part ( split /\./, $method )
            {
                unless( UNIVERSAL::isa $val, "RDF::Base::Object" )
                {
                    last;       # skipping undef values...
                }
                #         The position of $args varies!!! 
                #$val = $val->$part(undef,$args);
                $val = $val->$part(); ### FIXME
                debug sprintf("      -> %s", $val) if $DEBUG;
            }

            my $coltype = $sortargs->[$i]->{'coltype'} || '';
            if ( $coltype eq 'valfloat' )
            {
                if ( UNIVERSAL::isa $val, 'RDF::Base::List' )
                {
                    $val = List::Util::min( $val->as_array );
                }

                # Make it an integer
                $val ||= 0;
            }
            elsif ( $coltype eq 'valdate' )
            {
                if ( UNIVERSAL::isa $val, 'RDF::Base::List' )
                {
                    $val = List::Util::minstr( $val->as_array );
                }

                # Infinite future date
                use DateTime::Infinite;
                $val ||= DateTime::Infinite::Future->new;
                debug "Date value is $val" if $DEBUG;
            }
            elsif ( $coltype eq 'valtext' )
            {
                if ( UNIVERSAL::isa $val, 'RDF::Base::List' )
                {
                    $val = $val->loc;
                }

                $val ||= '';
            }

            debug sprintf("      => %s", $val) if $DEBUG;

            CORE::push @{$props[$i]}, $val;
#	    debug $item->safedesig .' : '.$val;
            CORE::push @{$item->{'sort_arg'}}, $val;
#	    CORE::push @{$props[$i]}, $item->$method;
        }
    }
    continue
    {
        ( $item, $error ) = $list->get_next;

        if ( not $list->count % 1000 )
        {
            $Para::Frame::REQ->note(sprintf "%5d", $list->count);
            $Para::Frame::REQ->may_yield;
        }
    }


    if ( $DEBUG )
    {
        debug "And the props is: \n";
        for ( my $i=0; $i<=$#$list; $i++ )
        {
            my $out = "  ".$list->[$i]->safedesig.": ";
            for ( my $x=0; $x<=$#props; $x++ )
            {
                if ( ref $props[$x][$i] )
                {
                    $out .= $props[$x][$i]->safedesig .' - ';
                }
                else
                {
                    $out .= $props[$x][$i] .' - ';
                }
            }
            debug $out;
        }

        debug "Sort string: { $sort_str }";
    }

    # The Schwartzian transform:
    # This method should be fast and efficient. Read up on it
    my @new = @{$list}[ eval qq{ sort { $sort_str } 0..$#$list } ];
    die "Sort error for '$sort_str': $@" if $@; ### DEBUG

    my $list_props = $list->clone_props;
    $list_props->{'sorted_on'} = $sortargs;
    $list_props->{'sorted_on_key'} = $sort_key;

    return $list->new( \@new, $list_props );
}


##############################################################################

=head2 parse_sortargs

  $class->parse_sortargs( ... )

=cut

sub parse_sortargs
{
    my( $this, $sortargs, $dir ) = @_;

    my $args = {};
    my $DEBUG = 0;

    $sortargs ||= 'desig';

    unless( ref $sortargs and ( ref $sortargs eq 'ARRAY' or
                                ref $sortargs eq 'RDF::Base::List' )
          )
    {
        $sortargs = [ $sortargs ];
    }

    if ( $dir )
    {
        unless( $dir =~ /^(asc|desc)$/ )
        {
            die "direction '$dir' out of bound";
        }

        for ( my $i = 0; $i < @$sortargs; $i++ )
        {
            unless( ref $sortargs->[$i] eq 'HASH' )
            {
                $sortargs->[$i] =
                {
                 on => $sortargs->[$i],
                 dir => $dir,
                };
            }
        }
    }

    my @sort;
    my @prop_str_list;
    for ( my $i = 0; $i < @$sortargs; $i++ )
    {
        if ( $DEBUG )
        {
            debug "i: $i";
            debug sprintf("sortargs: %d\n", scalar @$sortargs);
        }
        unless( ref $sortargs->[$i] eq 'HASH' )
        {
            $sortargs->[$i] =
            {
             on => $sortargs->[$i],
            };
        }

        $sortargs->[$i]->{'dir'} ||= 'asc';

        # Find out if we should do a numeric or literal sort
        #
        my $on =  $sortargs->[$i]->{'on'};
        if ( ref $on )
        {
            die "not implemented ($on)";
        }
        CORE::push @prop_str_list, $on;

        $on =~ /([^\.]+)$/;     #match last part
        my $pred_str = $1;


        my $cmp = $sortargs->[$i]->{'cmp'};
        unless( $cmp )
        {
            $cmp = 'cmp';

            # Silently ignore dynamic props (that isn't preds)
            eval
            {
                if ( my $pred = RDF::Base::Pred->get_by_anything( $pred_str,
                                                                  {
                                                                   %$args,
                                                                   nonfatal => 1,
                                                                  }))
                {
                    my $coltype = $pred->coltype;
                    $sortargs->[$i]->{'coltype'} = $coltype;
                    if ( ($coltype eq 'valfloat') or ($coltype eq 'valdate') )
                    {
                        $cmp = '<=>';
                    }
                }
            };
            if ( $@ )           # Just dump any errors to log...
            {
                undef $@;
                debug "Sortarg $pred_str not a predicate";
                debug "Specify cmp argument for optimization";
            }

            $sortargs->[$i]->{'cmp'} = $cmp;
        }

        if ( $sortargs->[$i]->{'dir'} eq 'desc')
        {
            CORE::push @sort, "\$props[$i][\$b] $cmp \$props[$i][\$a]";
        }
        else
        {
            CORE::push @sort, "\$props[$i][\$a] $cmp \$props[$i][\$b]";
        }
    }
    my $sort_str = join ' || ', @sort;

    my $sort_key = join( ',', @prop_str_list) . '=>' . $sort_str;

    return( $sortargs, $sort_str, $sort_key );
}


##############################################################################

=head2 uniq

  $l->uniq()

Returns a list with multiple list items filtered out. Operates on the
unmaterialized items. Populates the list.

For more than one element, returns a list.  If nothing was filtered,
returns the same object.

For less than one element, returns L<RDF::Base::Undef>.

For just one element, returns the element.

=cut

sub uniq
{
    my $l = $_[0]->SUPER::uniq();
    my $s = $l->size;
    if ( $s > 1 )
    {
        return $l;
    }
    elsif ( $s < 1 )
    {
        return is_undef;
    }
    else
    {
        return $l->get_first_nos;
    }
}

##############################################################################

=head2 unique_arcs_prio

  $list->unique_arcs_prio( \@arcproperties )

Example:

  $list->unique_arcs_prio( ['new','submitted','active'] )

Returns:

A List object with arc duplicates filtered out

=cut

sub unique_arcs_prio
{
    confess "FIXME";
    my( $list, $sortargs_in ) = @_;

    my $sortargs = RDF::Base::Arc::Lim->parse($sortargs_in);

    # $points->{ $commin_id }->[ $passed_order ] = $arc

#    debug "Sorting out duplicate arcs";


    my %points;

    my $index = $list->index;
    my( $arc, $error ) = $list->get_first;
    confess( "Not arc in unique_arcs_prio; $error - $arc" )
      unless( $error or ($arc and $arc->is_arc) );
    while (! $error )
    {
#	my $cid = $arc->common_id;
#	my $sor = $sortargs->sortorder($arc);
#	debug "Sort $sor: ".$arc->safedesig;
#	$points{ $cid }[ $sor ] = $arc;
        $points{ $arc->common_id }[ $sortargs->sortorder($arc) ] = $arc;
    }
    continue
    {
        ( $arc, $error ) = $list->get_next;
    }
    ;

    $list->set_index( $index );

#    debug "unique_arcs_prio";
#    debug query_desig(\%points);
#    debug "----------------";

    my @arcs;
    foreach my $group ( values %points )
    {
        foreach my $arc (@$group)
        {
            if ( $arc )
            {
                CORE::push @arcs, $arc;
                last;
            }
        }
    }

    return RDF::Base::List->new( \@arcs );
}


##############################################################################
################################  Accessors  ##########################

=head1 Accessors

=cut

##############################################################################

=head2 get

  $l->get(@params)

Calls L</find> with the params and expects just one match.

Returns:

A L<RDF::Base::Resource> object.

Exceptions:

See L<RDF::Base::Resource/get_by_anything>

=cut

sub get
{
    my $list = CORE::shift->find(@_);

    return RDF::Base::Resource->get_by_anything($list);
}


##############################################################################

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

    if ( $#$list )              # More than one element
    {
        for ( my $i = 0; $i<= $#$list; $i++)
        {
            $val .= "* ";
            $val .= $list->[$i]->sysdesig;
            $val .= "\n";
        }
    }
    else
    {
        $val .= $self->[0];
    }

    return $val;
}


##############################################################################

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

    if ( @$list == 1 )
    {
        $list->[0]->literal;
    }
    elsif ( @$list == 0 )
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


##############################################################################

=head2 loc

  $l->loc

  $l->loc(@params)

Choose a value, based on language option.  After that; sort on weight.

Params are given to L<Para::Frame::L10N/compute>.

The language priority should have been set by
L<Para::Frame::Resource/set_language> for the request.

Returns: A plain string

=cut

sub loc
{
    my $list = CORE::shift;

    # TODO: Check if the next argument is a hashref. Take that as
    # args.

    my $DEBUG = 0;


#    Para::Frame::Logging->this_level(4);

    my %alts;
    my $default;

#    debug 2,"Choosing among ".(scalar @$list)." values";

    # If we get a list of lists, do a loc for each sublist. Even if
    # one of the elements in this list is a sublist
    #
    my $is_nested_list = 0;

    foreach my $item ( @$list )
    {
        if ( ref $item )
        {
            if ( UNIVERSAL::isa($item, 'RDF::Base::Node') )
            {
                debug 3, sprintf "Res '%s' (%s)",
                  ($item||'<undef>'), blessed($item) if $DEBUG;

                my $langs = $item->list('is_of_language');
                if ( @$langs )
                {
                    foreach my $lang ( @$langs )
                    {
                        next unless $lang;
                        my $code = $lang->first_prop('code')->plain;
                        CORE::push @{$alts{$code}}, $item;
                        unless( $code )
                        {
                            throw('dbi', sprintf("Language %s does not have a code", $lang->sysdesig));
                        }
                        debug 4,"Lang $code: ".$item->id if $DEBUG;
                    }
                }
                else
                {
                    CORE::push @{$alts{'c'}}, $item;
                    # $item may stringify to undef
                    # debug 4, "Lang c: $item ($langs)";
                }
            }
            elsif ( UNIVERSAL::isa($item, 'RDF::Base::List') )
            {
                $is_nested_list++;
                last;
            }
            else
            {
                $default = $item;
                debug 3, sprintf "No translation '%s' (%s)",
                  $item, blessed($item) if $DEBUG;
            }
        }
        else
        {
            $default = $item;
            debug 3,"No translation" if $DEBUG;
        }
    }

    if ( $is_nested_list++ )
    {
        debug 3, "This is a nested list. Returning a list." if $DEBUG;
        my @new;
        foreach my $item ( @$list )
        {
            CORE::push @new, $item->loc(@_);
        }
        return $list->new(\@new);
    }


    # TODO: Chose value even with no language priority
    my @alternatives;
    if ( my $req = $Para::Frame::REQ )
    {
        confess( datadump($req,1) ) unless UNIVERSAL::can($req,'language');
        @alternatives = ($req->language->alternatives, 'c');
    }
    else
    {
        @alternatives = ('c');
    }

    foreach my $lang ( @alternatives )
    {
        debug 3, "Checking lang $lang" if $DEBUG;
        # Try to handle the cases in order of commonality
        next unless $alts{$lang} and @{$alts{$lang}};
        unless ( $alts{$lang}[1] )
        {
            # Not using ->value, since this may be a Literal
            debug 3, "  Returning only alternative" if $DEBUG;
#	    debug(0,$alts{$lang}[0]->{'id'});
            return $alts{$lang}[0]->loc(@_);
        }

        # Order by highest weight
        my %list;
        foreach ( @{$alts{$lang}} )
        {
            my $weight =
              ($_->is_literal ? $_->arc_weight : undef)
                || $_->weight->literal || 0;

            if ( $DEBUG )
            {
                debug 4, "  $_ has weight $weight" if $weight;
            }
            ;
            $list{ $weight } = $_;
        }

#	debug 1,"Returning (one) literal with highest weight";
#	debug query_desig \%list;
#        debug datadump(\%list,1);
        # Not using ->value, since this may be a Literal
        return $list{ List::Util::max( keys %list ) }->loc(@_);
    }

    ## Set default.  (*any* default)
    unless( defined $default )
    {
        if ( $alts{'c'}[0] )
        {
            $default = $alts{'c'}[0];
        }
    }
    unless( defined $default )
    {
        foreach my $lang ( keys %alts )
        {
            if ( $alts{$lang}[0] )
            {
                $default = $alts{$lang}[0];
                last;
            }
        }
    }

    if ( defined $default )
    {
        debug 3, "  Returning default" if $DEBUG;
        if ( ref $default and UNIVERSAL::isa $default, "RDF::Base::Object" )
        {
            return $default->loc(@_);
        }
        else
        {
            return $default;
        }
    }
    else
    {
        # Was this an empty list to begin with?
        unless( $list->size )
        {
            return "";
        }

        # The only choice is an undefined value!!!
        return "<undef>";       # This should not be common. Be clear!
    }
}


##############################################################################

=head2 loc_by_lang

my $prop = $list->loc_by_lang( [ 'sv', 'c' ] );

Returns one prop from the list, chosen first on is_of_language and then on
weight.

=cut

sub loc_by_lang
{
    my( $list, $lc_list, $args ) = @_;

    my %lang;
    my $DEBUG = 0;

    my $langprio = 100;
    foreach my $lc ( @$lc_list )
    {
        $lang{ $lc } = $langprio--;
    }

    my $got_weight = -1;
    my $got_lprio = -1;
    my $got_prop = is_undef;

    debug "Getting loc_by_list from: ". $list->sysdesig if $DEBUG;

    while ( my $prop = $list->get_next_nos )
    {
        if ( ref $prop and
             UNIVERSAL::isa($prop, 'RDF::Base::Resource') )
        {
            my $propweight = $prop->first_prop('weight', {}, $args) || 0;
            my $lprio = $lang{ $prop->first_prop('is_of_language', {}, $args)->first_prop('code', {}, $args)->plain } || 0;

            next unless( $lprio or defined $lang{'c'} );

            if ( $lprio gt $got_lprio )
            {
                $got_prop   = $prop;
                $got_weight = $propweight;
                $got_lprio  = $lprio;
            }
            elsif ( $lprio eq $got_lprio and
                    $propweight gt $got_weight )
            {
                $got_prop   = $prop;
                $got_weight = $propweight;
            }
        }
        elsif ( $got_lprio eq -1 )
        {
            $got_prop = $prop;
        }
    }

    return $got_prop;
}


##############################################################################

=head2 desig

  $l->desig

Return a SCALAR string with the elements designation concatenated with
C<' / '>.

See L<RDF::Base::Object/desig>

=cut

sub desig
{
#    debug "in list desig";
    my( $list, $args_in ) = @_;
    my @part;

    my $index = $list->index;
    my( $elem, $error ) = $list->get_first;
    while (! $error )
    {
        if ( (ref $elem) and ( UNIVERSAL::isa $elem, 'RDF::Base::Object' ) )
        {
            CORE::push @part, $elem->desig($args_in);
        }
        else
        {
            CORE::push @part, "$elem"; # stringify
        }
    }
    continue
    {
        ( $elem, $error ) = $list->get_next;
    }
    ;
    $list->set_index( $index );

    return join ' / ', @part;
}


##############################################################################

=head2 as_html

  $l->as_html( \%args )

Return a SCALAR string with the elements html representations concatenated with
C<'E<lt>brE<gt>'> or with the content of arg C<join>.

See L<RDF::Base::Object/desig>

=cut

sub as_html
{
#    debug "in list desig";
    my( $list, $args_in ) = @_;
    my( $args ) = parse_propargs( $args_in );
    my @part;

    my $index = $list->index;
    my( $elem, $error ) = $list->get_first;
    while (! $error )
    {
        if ( ref $elem )
        {
            if ( UNIVERSAL::isa $elem, 'RDF::Base::Object' )
            {
                CORE::push @part, $elem->as_html($args);
            }
            elsif ( $elem->can('as_html') )
            {
                CORE::push @part, $elem->as_html;
            }
            else
            {
                CORE::push @part, "$elem"; # stringify
            }
        }
        else
        {
            CORE::push @part, "$elem"; # stringify
        }
    }
    continue
    {
        ( $elem, $error ) = $list->get_next;
    }
    ;
    $list->set_index( $index );

    my $join = $args->{'join'} || "<br/>\n";
    return join $join, @part;
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


##############################################################################

=head2 nodes

  $l->nodes(@args)

Just as L</as_list> but regards the SCALAR/ARRAY context.

=cut

sub nodes
{
#    warn " --> wantarray?\n"; ### DEBUG
    if ( wantarray )
    {
        return @{CORE::shift->as_list(@_)};
    }
    else
    {
        return CORE::shift->as_list(@_);
    }
}


##############################################################################

=head2 plain

  $l->plain()

Just as L</nodes>.

=cut

sub plain
{
    if ( wantarray )
    {
        return @{CORE::shift->as_list(@_)};
    }
    else
    {
        return CORE::shift->as_list(@_);
    }
}


##############################################################################

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

    if ( ref $_[0][0] )
    {
        return $_[0][0]->is_true;
    }

    return $_[0][0] ? 1 : 0;
}


##############################################################################
################################  Public methods  #####################


=head1 Public methods

=cut


##############################################################################

=head2 contains

  $list->contains( $node, \%args )

  $list->contains( $list2, \%args )


Returns true if the list contains all mentioned items supplied as a
list, list objekt or single item.

Each element is compared with L<Para::Frame::Object/equals>.

Supported args are:

  arclim

TODO: Use iteration with the iterators

Returns: A boolean value

=cut

sub contains
{
    my( $list, $tmpl, $args ) = @_;

    if ( ref $tmpl )
    {
        if ( ref $tmpl eq 'RDF::Base::List' )
        {
            foreach my $val (@{$tmpl->as_list})
            {
                return 0 unless $list->contains($val, $args);
            }
            return 1;
        }
        elsif ( ref $tmpl eq 'ARRAY' )
        {
            foreach my $val (@$tmpl )
            {
                return 0 unless $list->equals($val, $args);
            }
            return 1;
        }
        elsif ( ref $tmpl eq 'Para::Frame::List' )
        {
            foreach my $val ($tmpl->as_list)
            {
                return 0 unless $list->contains($val, $args);
            }
            return 1;
        }
        elsif ( ref $tmpl eq 'HASH' )
        {
            die "Not implemented: $tmpl";
        }

        # else: go to the default handling below
    }

    # Default for simple values and objects:

    foreach my $node ( @{$list->as_list} )
    {
        unless( UNIVERSAL::isa $node, "RDF::Base::Object" )
        {
            confess "List element not a RB object: ".query_desig($node);
        }
        return $node if $node->equals($tmpl, $args);
    }
    return undef;
}


##############################################################################

=head2 contains_any_of

  $list->contains_any_of( $node, \%args )

  $list->contains_any_of( $list2, \%args )


Returns true if the list contains at least one of the mentioned items
supplied as a list, list objekt or single item.

Each element is compared with L<Para::Frame::Object/equals>.

Supported args are:

  arclim

TODO: Use iteration with the iterators

Returns: A boolean value

=cut

sub contains_any_of
{
    my( $list, $tmpl, $args ) = @_;

    my $DEBUG = 0;

    if ( $DEBUG )
    {
        debug "Checking list with content:";
        foreach my $node ( $list->nodes )
        {
            debug sprintf "  * %s", $node->sysdesig;
        }
    }

    if ( ref $tmpl )
    {
        if ( UNIVERSAL::isa $tmpl, 'RDF::Base::List' )
        {
            foreach my $val (@{$tmpl->as_list})
            {
                debug 2, sprintf "  check list item %s", $val->sysdesig if $DEBUG;
                return 1 if $list->contains_any_of($val, $args);
            }
            debug 2, "    failed" if $DEBUG;
            return 0;
        }
        elsif ( ref $tmpl eq 'ARRAY' )
        {
            foreach my $val (@$tmpl )
            {
                debug 2, sprintf "  check array item %s", $val->sysdesig if $DEBUG;
                return 1 if $list->contains_any_of($val, $args);
            }
            debug 2, "    failed" if $DEBUG;
            return 0;
        }
        elsif ( ref $tmpl eq 'Para::Frame::List' )
        {
            foreach my $val ($tmpl->as_list)
            {
                debug 2, sprintf "  check list item %s", $val->sysdesig if $DEBUG;
                return 1 if $list->contains_any_of($val, $args);
            }
            debug 2, "    failed" if $DEBUG;
            return 0;
        }
        elsif ( ref $tmpl eq 'HASH' )
        {
            die "Not implemented: $tmpl";
        }
    }

    # Default for simple values and objects:

    foreach my $node ( @{$list->as_list} )
    {
        debug 2, sprintf "  check node %s", $node->sysdesig if $DEBUG;
        debug 2, sprintf "  against %s", $tmpl->sysdesig if $DEBUG;
        return $node if $node->equals($tmpl, $args);
    }
    debug 2,"    failed" if $DEBUG;
    return undef;
}


##############################################################################

=head2 has_value

  $l->has_value($val, \%args)

Returns true if at least one of the elements of the list has the given
value.

See L<RDF::Base::Resource/find> nad L<RDF::Base::Arc/has_value>.

Supported args are:

  arclim

=cut

sub has_value
{
    my( $l, $value, $args ) = @_;

    my( $node, $error );
    my $index = $l->index;
    for ( ($node,$error)=$l->get_first; !$error; ($node,$error)=$l->get_next )
    {
        if ( $node->has_value($value, $args) )
        {
            $l->set_index( $index );
            return $node;
        }
    }

    $l->set_index( $index );
    return 0;
}


##############################################################################

=head2 has_pred

  $l->has_pred($predname, $proplim, \%args)

Returns: A list of all elements that has a property with the pred to a
value matching proplim and args

=cut

sub has_pred
{
    my( $l, $pred_in, $proplim, $args_in ) = @_;
    my( $args, $arclim ) = parse_propargs($args_in);

#    debug "Filtering list on has_pred";

    # This is an optimized version of list autoload has_pred...

    my( $pred, $predname );
    if ( UNIVERSAL::isa($pred_in,'RDF::Base::Pred') )
    {
        $pred = $pred_in;
        $predname = $pred->plain;
    }
    else
    {
        $pred = RDF::Base::Pred->get($pred_in);
        $predname = $pred->plain;
    }

    my @grep;

    my( $active, $inactive ) = $arclim->incl_act;

    my( $node, $error );
    my $index = $l->index;
    for ( ($node,$error)=$l->get_first; !$error; ($node,$error)=$l->get_next )
    {
#	debug "  checking ".$node->desig;
        my @arcs;
        if ( $node->initiate_prop( $pred, $proplim, $args ) )
        {
            if ( $active and $node->{'relarc'}{$predname} )
            {
                CORE::push @arcs, @{ $node->{'relarc'}{$predname} };
            }

            if ( $inactive and $node->{'relarc_inactive'}{$predname} )
            {
                CORE::push @arcs, @{ $node->{'relarc_inactive'}{$predname} };
            }
        }
        else
        {
            next;
        }

        foreach my $arc (@arcs )
        {
            next unless $arc->meets_arclim($arclim);
            next unless $arc->value_meets_proplim($proplim, $args);

            CORE::push @grep, $node;
            last;
        }
    }
    $l->set_index( $index );

#    debug "Filtering list on has_pred - done";

    return RDF::Base::List->new(\@grep);
}


##############################################################################

=head2 materialize

Primarly used by L<RDF::Base::Search/execute> given to L</new> as
argument C<materializer>.

=cut

sub materialize
{
    my( $l, $i ) = @_;

    confess "FIXME" unless defined $i;

    my $elem = $l->{'_DATA'}[$i];
    if ( ref $elem )
    {
        return $elem;
    }
    elsif ( $elem )
    {
        # Handle long lists
        unless( $i % 25 )
        {
            if ( $Para::Frame::REQ )
            {
                $Para::Frame::REQ->may_yield;
                die "cancelled" if $Para::Frame::REQ->cancelled;
            }
        }

        # TODO: Maby not call initiate_rel for arcs
        my $obj = RDF::Base::Resource->get( $elem,
                                            {
                                             initiate_rel =>
                                             $l->{'rb_initiate_rel'},
                                            });
        if ( debug > 2 )
        {
            debug "Materializing element $i -> ".$obj->sysdesig;
        }
        return $obj;
    }
    else
    {
        return is_undef;        # For special cases (in search_smart)
    }
}


##############################################################################

=head2 materialize_by_rec

=cut

sub materialize_by_rec
{
    my( $l, $i ) = @_;

    my $rec = $l->{'_DATA'}[$i];

    # Handle long lists
    unless( $i % 25 )
    {
        $Para::Frame::REQ->may_yield;
        die "cancelled" if $Para::Frame::REQ->cancelled;
    }

    my $node = RDF::Base::Arc->get_by_rec( $rec );

    if ( debug > 2 )
    {
        debug "Materializing element $i -> ".$node->sysdesig;
    }

    return $node;
}


##############################################################################

=head2 initiate_rel

  $l->initiate_rel

Calls L<Para::Frame::Resource/initiate_rel> for each element.

Returns: C<$l>

=cut

sub initiate_rel
{
    my( $l ) = CORE::shift;

    foreach ( @$l )
    {
        $_->initiate_rel(@_);
    }
    return $l;
}


##############################################################################

=head2 cmp_by_overload

  $l->cmp_by_overload( $val )

Comparing something with the list compares with it's desig

=cut

sub cmp_by_overload
{
    my $val_a = $_[0]->desig;
    my $val_b = "";
    if ( ref $_[1] )
    {
        $val_b = $_[1]->desig;
    }

    if ( $_[2] )                # Reverse?
    {
        return( $val_b cmp $val_a );
    }
    else
    {
        return( $val_a cmp $val_b );
    }
}


##############################################################################

=head2 as_listobj

  $o->as_listobj()

Returns a L<RDF::Base::List>

=cut

sub as_listobj
{
    return $_[0];
}

##############################################################################

=head2 equals

  $l->equals( $value )

Check each of the elements with the value

Returns: A boolean value

=cut

sub equals
{
    foreach ( $_[0]->nodes )
    {
        return 0 unless $_->equals($_[1]);
    }

    return 1;
}


##############################################################################

=head2 get_first_nos

Same as L<Para::Frame::List/get_first_nos>, but returns
L<RDF::Base::Undef> if no element found

=cut

sub get_first_nos
{
    my( $val, $err ) = $_[0]->get_first;
    if ( $err )
    {
        return is_undef;
    }
    else
    {
        return $val;
    }
}


##############################################################################

=head2 get_next_nos

Same as L<Para::Frame::List/get_next_nos>, but returns
L<RDF::Base::Undef> if no element found

=cut

sub get_next_nos
{
    my( $val, $err ) = $_[0]->get_next;
    if ( $err )
    {
        return is_undef;
    }
    else
    {
        return $val;
    }
}


##############################################################################

=head2 concatenate_by_overload

implemented concatenate_by_overload()

=cut

sub concatenate_by_overload
{
    my( $l, $str, $is_rev ) = @_;
#    carp "* OVERLOAD concatenate for list obj used";

    my $lstr = $l->desig;
    if ( $is_rev )
    {
        return $str.$lstr;
    }
    else
    {
        return $lstr.$str;
    }
}


##############################################################################

=head2 parse_prop

  $n->parse_prop( $criterion, \%args )

Parses C<$criterion>...

Returns the values of the property matching the criterion.  See
L</list> for explanation of the params.

See also L<RDF::Base::Node/parse_prop>

=cut

sub parse_prop
{
    my( $l, $crit, $args_in ) = @_;

    $crit or confess "No name param given";

    my( $args, $arclim ) = parse_propargs($args_in);
#    debug "Parsing $crit for list";

    my $step;
    if ( $crit =~ s/\.(.*)// )
    {
        $step = $1;
    }

    my($prop_name, $propargs) = split(/\s+/, $crit, 2);
    trim(\$prop_name);
    my( $proplim, $arclim2 );
    if ( $propargs )
    {
        ($proplim, $arclim2) = parse_query_value($propargs);
        if ( $arclim2 )
        {
            $args->{'arclim'} = $arclim2;
        }
    }

#    debug "  Calling method $prop_name";
    my $res = $l->$prop_name($proplim, $args);

    if ( $step )
    {
#        debug "  calling $res -> $step";
#        debug "  res is ".ref($res);

        my $res2 = $res->parse_prop( $step, $args_in );
#        debug "  list res2 $res2";
        return $res2;
    }

#    debug "  list res $res";
    return $res;
}


##############################################################################

=head2 transform

  $l->transform( $lookup )

Returns: A new list with the nodes that is the result of the given lookup

=cut

sub transform
{
    my( $l, $lookup ) = @_;

    my $l2 = $l->new([], $l->clone_props);

    my %seen;

    my $index = $l->index;
    my( $elem, $error ) = $l->get_first;
    while (! $error )
    {
        foreach my $elem2 ( $elem->$lookup->as_listobj->flatten->as_array )
        {
            next unless $elem2->defined;
            die datadump($elem2,1) if $elem2->is_list;
            next if $seen{ $elem2->id };
            $l2->push( $elem2 );
            $seen{ $elem2->id } ++;
        }

#	$l2->push( $elem->$lookup->as_array );
#	$l2->push_uniq( grep $_->defined, $elem->$lookup->flatten->as_array );
    }
    continue
    {
        if ( $Para::Frame::REQ )
        {
            $Para::Frame::REQ->note("...". $l->count ."/". $l->size)
              unless( $l->count % 100 );
        }
        ( $elem, $error ) = $l->get_next;
    }
    $l->set_index( $index );

    return $l2;
}


##############################################################################
################################  Private methods  ####################

=head1 AUTOLOAD

  $l->$method( @args )

For all method calls not catched by defined methods in this class,
this AUTOLOAD is used.

The method is called for each element in the source list. Elements
that are not L<RDF::Base::Object> objects are silently
ignored. L<RDF::Base::Undef> objects are also ignored.

If the source list is empty, the method are called on
L<RDF::Base::Undef> in return context, and returned. That class will
return the right type of value for most L<RDF::Base::Node> methods.

A result list is prepared for the return values of each method call.
The C<$method> are called in scalar context and given the C<@args>.

1.  Results that isn't L<RDF::Base::Object> objects are appended to
the result list.

2. L<RDF::Base::Undef> objects are ignored. Not placed in the result
list.

3. L<RDF::Base::List> objects are appended to the result list, only if
they contain one or more elements. The lists are B<NOT> flattened.
The content of the returned lists are not altered. Undef value inside
the lists are thus also left in place. We are just checking for the
size of the list. Empty lists are not appended to the result list.

4. All other L<RDF::Base::Object> objects are appended to the result
list.

The B<return> value depends on the size of the result list:

1. For an empty result list, we will return a an empty L<RDF::Base::List>

2. For a result list with just B<one> element, that element will be
used as a return value, no matter what that value is. (It may, for
example, be a L<RDF::Base::List> object returned from one of the
method calls.)

3. For a result list with more than one element, a L<RDF::Base::List>
containing the result list will be returned.

No exceptions are cathed.

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
    my $propname = $AUTOLOAD;
    my $self = CORE::shift;
    my $class = ref($self);
    my $thingtype = ref $self;

    #Logging mark don't work in AUTOLOAD
    #Para::Frame::Logging->this_level(3);
    my $DEBUG = 0;

    debug "List autoloading $propname for $thingtype" if $DEBUG>1;
    if ( $DEBUG>3 )
    {
        debug "LIST params ".query_desig(\@_);
        debug "LIST IN ".query_desig($self);
        debug "Got ".$self->size." elements";
    }

    confess "Self not a list: ".datadump($self) unless UNIVERSAL::isa($self,'RDF::Base::List');
    unless( $self->size )
    {
#	return $self->new_empty();
        return is_undef->$propname(@_,undef);
    }

    if ( $propname =~ /([^\.]+)\.(.*)/ )
    {
        my( $first, $last ) = ( $1, $2 );
        return $self->$first->$last(@_);
    }


    my @list = ();
    my $list_class;
    my $index = $self->index;
    my( $elem, $error ) = $self->get_first;
    while (! $error )
    {
        next unless defined $elem;
        if ( UNIVERSAL::isa( $elem, 'RDF::Base::Object' ) )
        {
            next unless $elem->defined;

            # Add a undef to force list context in Resource AUTOLOAD
            my $res = $elem->$propname(@_,undef);
            if ( UNIVERSAL::isa( $res, 'RDF::Base::Object' ) )
            {
                if ( $res->is_list )
                {
                    $list_class ||= ref($res);
                    if ( $res->size )
                    {
                        CORE::push @list, $res;
                    }
                }
                elsif ( $res->defined )
                {
                    $list_class ||= $res->list_class;
                    CORE::push @list, $res;
                }
            }
            else
            {
                CORE::push @list, $res;
            }
        }
    }
    continue
    {
        ( $elem, $error ) = $self->get_next;
    }
    $self->set_index( $index );

    # Don't assume it is the same as the call class
    $list_class ||= "RDF::Base::List";

    if ( $DEBUG > 2 )
    {
        debug( "LIST WASHED ".query_desig(\@list) );
    }

    if ( my $size = scalar @list )
    {
        if ( $size == 1 )
        {
            return $list[0];
        }
        else
        {
            return $list_class->new(\@list);
        }
    }
    else
    {
        debug "  No value returned" if $DEBUG>2;
        return $list_class->new_empty();
    }
}


##############################################################################

  1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
