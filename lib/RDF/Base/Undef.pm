package RDF::Base::Undef;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Undef

=cut

use 5.014;
use warnings;
use base qw( RDF::Base::Node );
use vars qw($AUTOLOAD);
use overload
  '""'   => sub{""},
  'bool' => sub{0},
  '0+'   => sub{0},
  'cmp'  => 'cmp_string',
  '='    => sub{undef},
  '<=>'  => 'cmp_numeric',
  '+'    => sub{0},
  '-'    => sub{0},
  '@{}'  => sub{[]},
  ;

use Carp qw( cluck );
use Scalar::Util qw( looks_like_number );

use RDF::Base::Widget qw( locnl );

use Para::Frame::Reload;


=head1 DESCRIPTION

Represents an undefined node.  But tries harder to cooperate.

=cut


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any List object.

=cut

##############################################################################

=head2 new

=cut

sub new
{
    my( $this ) = @_;
    my $class = ref($this) || $this;
    return bless {}, $class;
}


#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

##############################################################################

=head2 literal

=cut

sub literal
{
    return "";
}

##############################################################################

=head2 as_string

=cut

sub as_string
{
    return "<undef>";
}

##############################################################################

=head2 as_json

=cut

sub as_json
{
    return '{"data":[]}';
}

##############################################################################

=head2 as_html

=cut

sub as_html
{
    return "<span class='na'>&#8212;</span>";
}

##############################################################################

=head2 desig

=cut

sub desig
{
    return "";
}

##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    return shift->literal;
}



##############################################################################

=head2 loc

See L<RDF::Base::Literal/loc>

=cut

sub loc
{
    return shift->literal;
}



##############################################################################

=head2 clean

See L<RDF::Base::Literal/clean>

=cut

sub clean
{
    return RDF::Base::Literal::String->new("");
}



##############################################################################

=head2 clean_plain

See L<RDF::Base::Literal/clean_plain>

=cut

sub clean_plain
{
    return "";
}



##############################################################################

=head2 plain

Make it a plain value

=cut

sub plain
{
    return undef;
}

##############################################################################

=head3 value

Search for arc may have resulted in undef. See
L<RDF::Base::Arc/value>.

The property "value" has special handling in its dynamic use for
nodes.  This means that you can only use this method as an ordinary
method call.  Not dynamicly.

=cut

sub value
{
    return shift;
}


##############################################################################

=head2 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return "undef";
}


##############################################################################

=head2 wu_jump

See L<RDF::Base::Node/wu_jump)

Returns: the string '<undef>' as HTML

=cut

sub wu_jump
{
    return "<span class=\"broken\">&lt;undef&gt;</span>";
}


##############################################################################

=head2 id

returns: plain undef

=cut

sub id
{
    return undef;
}


##############################################################################

=head2 id_alphanum

returns: plain undef

=cut

sub id_alphanum
{
    return undef;
}


##############################################################################

=head2 defined

Returns 0. (false)

=cut

sub defined
{
    # Used by List AUTOLOAD

    return 0;
}

##############################################################################

=head2 is_true

Returns 0;

=cut

sub is_true
{
    return 0;
}

##############################################################################

=head2 as_list

Compatible with L<Template::Iterator>.

Returns: An arrayref

=cut

sub as_list
{
    # Used by List AUTOLOAD

    return [];
}

##############################################################################

=head2 as_listobj

  $o->as_listobj()

Returns a L<RDF::Base::List>

=cut

sub as_listobj
{
    return $_[0]->list_class->new_empty();
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
	return();
    }
    else
    {
	return RDF::Base::List->new([]);
    }
}

##############################################################################

=head2 cmp_string

=cut

sub cmp_string
{
    my $val = "";
    if( ref $_[1] )
    {
	if( $_[1]->defined )
	{
	    $val = $_[1]->desig;
	}
    }
    else
    {
	if( defined $_[1] )
	{
	    $val = $_[1];
	}
    }
    if( $_[2] ) # Reverse?
    {
	return( $val cmp "" );
    }
    else
    {
	return( "" cmp $val );
    }
}

##############################################################################

=head2 cmp_numeric

=cut

sub cmp_numeric
{
    my $val = 0;
    if( ref $_[1] and $_[1]->can('defined') )
    {
	if( $_[1]->defined )
	{
	    $val = $_[1]->desig;
	    return 0 unless looks_like_number($val);
	}
    }
    else
    {
	if( defined $_[1] )
	{
	    $val = $_[1];
	    return 0 unless looks_like_number($val);
	}
    }
    if( $_[2] ) # Reverse?
    {
	return( $val <=> 0 );
    }
    else
    {
	return( 0 <=> $val );
    }
}


##############################################################################

=head2 equals

=cut

sub equals
{
    if( UNIVERSAL::isa $_[1], "RDF::Base::Undef" )
    {
	return 1;
    }
    elsif( not defined $_[1] )
    {
	return 1;
    }

    return 0;
}


##############################################################################

=head2 size

=cut

sub size
{
    return 0;
}

##############################################################################

=head2 as_array

TODO: CHECK if not used anywhere...

=cut

sub as_array
{
    return ();
}

##############################################################################

=head2 list

Equals to L<RDF::Base::Resource/list>.
Do not confuse with L</as_listobj>.

=cut

sub list
{
    return RDF::Base::List->new_empty();
}

##############################################################################

=head2 arc_list

=cut

sub arc_list
{
    return RDF::Base::Arc::List->new_empty();
}

##############################################################################

=head2 list_preds

=cut

sub list_preds
{
    return RDF::Base::List->new_empty();
}

##############################################################################

=head2 revlist

TODO: Rewrite code for handling undef objects in arcs. Those will have
a relvist in the same manner as literal nodes.

=cut

sub revlist
{
    return RDF::Base::List->new_empty();
}

##############################################################################

=head2 revarc_list

=cut

sub revarc_list
{
    return RDF::Base::Arc::List->new_empty();
}

##############################################################################

=head2 revlist_preds

=cut

sub revlist_preds
{
    return RDF::Base::List->new_empty();
}

##############################################################################

=head2 arcversions

=cut

sub arcversions
{
    return RDF::Base::List->new_empty();
}

##############################################################################

=head2 get_first

=cut

sub get_first
{
    return( RDF::Base::Undef->new(), Template::Constants::STATUS_DONE );
}

##############################################################################

=head2 get_next

=cut

sub get_next
{
    return( RDF::Base::Undef->new(), Template::Constants::STATUS_DONE );
}

##############################################################################

=head2 count

=cut

sub count
{
    return 0;
}

##############################################################################

=head2 revcount

=cut

sub revcount
{
    return 0;
}

##############################################################################

=head2 remove

=cut

sub remove
{
    return 0;
}

##############################################################################

=head2 this_coltype

=cut

sub this_coltype
{
    return undef;
}

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut


#########################################################################
################################  Private methods  ######################

=head1 AUTOLOAD

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
    my $propname = $AUTOLOAD;
    my $self = shift;

    return $self;
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
