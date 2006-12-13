#  $Id$  -*-cperl-*-
package Rit::Base::Undef;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal Undef class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Undef

=cut

use Carp qw( cluck );
use strict;
use vars qw($AUTOLOAD);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}


use base qw( Rit::Base::Literal );

use Para::Frame::Reload;

use overload
    '""'   => 'as_string',
    'bool' => sub{0},
    '0+'   => sub{0},
    'cmp'  => 'cmp_string',
    '='    => sub{undef},
    '<=>'  => 'cmp_numeric',
    '+'    => sub{0},
    '@{}'  => sub{[]};

=head1 DESCRIPTION

Represents an undefined node.  But tries harder to cooperate.

=cut


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

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

#######################################################################

=head2 literal

=cut

sub literal
{
    return "";
}

#######################################################################

=head2 as_string

=cut

sub as_string
{
    return "<undef>";
}

#######################################################################

=head2 desig

=cut

sub desig
{
    return "";
}

#######################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    return shift->literal;
}



#######################################################################

=head2 loc

See L<Rit::Base::Literal/loc>

=cut

sub loc
{
    return shift->literal;
}



#######################################################################

=head2 clean

See L<Rit::Base::Literal/clean>

=cut

sub clean
{
    return Rit::Base::String->new("");
}



#######################################################################

=head2 plain

Make it a plain value

=cut

sub plain
{
    return undef;
}

#######################################################################

=head3 value

Search for arc may have resulted in undef. See
L<Rit::Base::Arc/value>.

The property "value" has special handling in its dynamic use for
nodes.  This means that you can only use this method as an ordinary
method call.  Not dynamicly.

=cut

sub value
{
    return shift;
}

#######################################################################

=head2 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return "undef";
}


#######################################################################

=head2 defined

Returns 0. (false)

=cut

sub defined
{
    # Used by List AUTOLOAD

    return 0;
}

#######################################################################

=head2 is_true

Returns 0;

=cut

sub is_true
{
    return 0;
}

#######################################################################

=head2 as_list

Returns empty L<Rit::Base::List>

=cut

sub as_list
{
    # Used by List AUTOLOAD

    return Rit::Base::List->new([]);
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
	return();
    }
    else
    {
	return Rit::Base::List->new([]);
    }
}

#######################################################################

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

#######################################################################

=head2 cmp_numeric

=cut

sub cmp_numeric
{
    my $val = 0;
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
	return( $val <=> 0 );
    }
    else
    {
	return( 0 <=> $val );
    }
}


#######################################################################

=head2 size

=cut

sub size
{
    return 0;
}

#######################################################################

=head2 as_array

TODO: CHECK if not used anywhere...

=cut

sub as_array
{
    return ();
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


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
