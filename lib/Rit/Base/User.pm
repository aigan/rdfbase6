#  $Id$  -*-cperl-*-
package Rit::Base::User;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource User class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::User

=cut

use strict;

use DBI;
use Data::Dumper;
use Carp qw( confess cluck carp );
use Time::HiRes qw( time );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( debug passwd_crypt trim datadump );
use Para::Frame::User;
use Para::Frame::Reload;

use Rit::Base::Utils qw( is_undef );
use Rit::Base::Constants qw( $C_login_account $C_full_access $C_guest_access );

use base qw(Para::Frame::User);


=head1 DESCRIPTION

Inherits from L<Para::Frame::User>

This class doesn't inherit from L<Rit::Base::Resoure>. But see
L<Rit::Base::User::Meta>.

Resources, then initiated, will be placed in the right class based on
the C<class_handled_by_perl_module> property. Since a resource can
have multiple classes, the class in itself can not inherit from
L<Rit::Base::Resource>. The resource will be placed in a metaclass
that inherits from this class and from L<Rit::Base::Resource>.

The L<Rit::Base::User::Meta> is used during startup. It is listed in
C<%Rit::Base::LOOKUP_CLASS_FOR> to make it be reblessd in the right
metaclass based on the nodes other possible classes.  See
L<Rit::Base::Resource/get>.

Forsubclassing, create both the subclass (L<Rit::Guides::User>) and
also a sub metaclass that inherits from it and from
L<Rit::Base::Resource> (L<Rit::Guides::User::Meta>). Set
L<Para::Frame/user_class> to the meta class but point to the subclass
in Ritbase with the property C<class_handled_by_perl_module> for the
resource representing the user class.

=cut

#######################################################################

=head2 get

=cut

sub get
{
#    debug "Getting user $_[1]";
    my $u = $_[0]->Rit::Base::Resource::get($_[1]);
#    debug "Got $u";
    return $u;
}

#######################################################################

=head2 init

This is first run *before* constants initialized.

=cut

sub init
{
    my( $node ) = @_;

    my $uid = $node->id;
    $node->{'uid'} = $uid;

    return $node;
}

#######################################################################

=head2 username

=cut

sub username
{
#    warn "in User username: ".datadump($_[0],3);

    return $_[0]->{username} ||= $_[0]->name_short->loc || $_[0]->name->loc || $_[0]->customer_id;
}

#######################################################################

=head2 id

=cut

sub id ($)
{
    confess( $_[0]||'<undef>' ) unless ref $_[0];
    return $_[0]->Rit::Base::Resource::id();
}

#######################################################################

=head2 name

=cut

sub name
{
    return $_[0]->Rit::Base::Resource::name;
}

#######################################################################

=head2 node

=cut

sub node
{
    carp "----------- TEMPORARY! FIXME";
    return $_[0];
}

#######################################################################

=head2 level

=cut

sub level
{
    unless( $_[0]->{'level'} )
    {
	my $node = $_[0];
	## See $apphome/doc/notes.txt
	my $level;
	if( $node->has_prop( 'has_access_right', $C_guest_access ) )
	{
	    $level = 0;
	}
	elsif( $node->has_prop( 'has_access_right', $C_full_access ) )
	{
	    $level = 40;
	}
	else
	{
	    $level = 10;
	}
	$node->{'level'} = $level;
    }

    return $_[0]->{'level'};
}


#######################################################################

=head2 find_by_level

Called by L<Rit::Base::Resource/get> that gets called by
L<Para::Frame::User/identify_user>.

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

    debug 2, "find user by label: $val";

    # obj is guest
    #
    if( $val eq 'guest' )
    {
	debug 2, "  as guest";
#	warn datadump($C_guest_access, 2);
	my $class = ref($_[0]) || $_[0];
	@new = @{ $class->find
	    ({
	      'name_short'       => 'guest',
	      has_access_right   => $C_guest_access,
	     })};
    }
    #
    # obj is root
    #
    elsif( $val eq 'root' ) # root node
    {
	debug 2, "  as root";
	Para::Frame::REQ->result->message("Login as root not permitted");
	return undef;
    }
    #
    # obj as name of obj
    #
    elsif( $val =~ /^h\d/i )
    {
	debug 2, "  as customer";
	my $class = ref($_[0]) || $_[0];
	@new = @{ $class->find
	    ({
	      'customer_id' => $val,
	      is            => $C_login_account,
	     })};
    }
    elsif( $val !~ /^\d+$/ )
    {
	debug 2, "  as non-number, from name_short";
	# TODO: Handle empty $val

	my $class = ref($_[0]) || $_[0];
	@new = @{ $class->find
	    ({
	      'name_short' => $val,
	      is           => $C_login_account,
	     })};

	unless(@new)
	{
	    debug 2, "  as non-number, from name";
	    @new = @{ $class->find
		({
		  'name' => $val,
		  is     => $C_login_account,
		 })};
	}
    }
    #
    # obj as obj id
    #
    else
    {
	debug 2, "  as id";
	push @new, $this->get_by_id( $val );
    }

    debug 3, "Returning ($new[0])";

#    warn "  returning @new\n";

    return Rit::Base::List->new(\@new);

}

#######################################################################

=head2 verify_password

=cut

sub verify_password
{
    my( $u, $password_encrypted ) = @_;

    $password_encrypted ||= '';

#    debug "Retrieving password for $node->{id}";
    my $n_password = $u->first_prop('password') || '';

    # Validating password
    #
    if( $password_encrypted eq passwd_crypt($n_password) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

#######################################################################

=head2 has_root_access

=cut

sub has_root_access
{
    if( $_[0]->has_access_right->equals($C_full_access) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

#######################################################################

1;
