#  $Id$  -*-cperl-*-
package Rit::Base::Lazy;

=head1 NAME

Rit::Base::Lazy - Noninitiated resources

=cut

use Carp qw( cluck confess croak carp );
use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

## Inherit (just for letting UNIVERSAL::isa know it)

use base qw( Rit::Base::Resource::Compatible );

our $AUTOLOAD;

=head1 DESCRIPTION

Lazy evaluation of resources.

On first method invocation, initializes the object.

Be careful for places where the type of the object is checked whitout
first using a method invocation. We let this class inherit from
L<Rit::Base::Resource> to avoid some situations. But it will not say
what class this object realy will be blessed into.

=cut

#########################################################################

=head2 get

  Rit::Base::Lazy->get( $id )

Creates this lazy object.

=cut

sub get
{
    my( $this, $id ) = @_;
    my $class = ref $this || $this;
    $id =~ /^\d+$/ or die "no id given";

    if( my $node = $Rit::Base::Cache::Resource{ $id } )
    {
	return $node;
    }
    else
    {
	my $node = bless {id=>$id}, $class;
	$Rit::Base::Cache::Resource{ $id } = $node;
	$node->Rit::Base::Resource::initiate_cache;
	return $node;
    }
}

#########################################################################


=head1 AUTOLOAD

  $n->$method(@args)

Initializes the object as via L<Rit::Base::Resource/get>, calls the
method and returns the result.

Futher calls will go to the class this object now belongs to.

=cut

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
    my $obj = shift;
    debug "Converts lazy object $obj->{id}";

    bless $obj, 'Rit::Base::Resource';
    $obj->first_bless;

    return $obj->$AUTOLOAD(@_);
}

1;

=head1 SEE ALSO

L<Rit::Base::Resource>,

=cut
