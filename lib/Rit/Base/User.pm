package Rit::Base::User;
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

Rit::Base::User

=cut

use 5.010;
use strict;
use warnings;
use base qw(Para::Frame::User);

use DBI;
use Carp qw( confess cluck carp );
use Time::HiRes qw( time );

use Para::Frame::Utils qw( debug passwd_crypt trim datadump catch throw );
use Para::Frame::User;
use Para::Frame::Reload;

use Rit::Base::Utils qw( is_undef parse_propargs query_desig );
use Rit::Base::Constants qw( $C_login_account $C_full_access $C_guest_access );


=head1 DESCRIPTION

Inherits from L<Para::Frame::User>

This class doesn't inherit from L<Rit::Base::Resoure>. But see
L<Rit::Base::User::Meta>.

Resources, when initiated, will be placed in the right class based on
the C<class_handled_by_perl_module> property. Since a resource can
have multiple classes, the class in itself can not inherit from
L<Rit::Base::Resource>. The resource will be placed in a metaclass
that inherits from this class and from L<Rit::Base::Resource>.

The L<Rit::Base::User::Meta> is used during startup. It is listed in
C<%Rit::Base::LOOKUP_CLASS_FOR> to make it be reblessd in the right
metaclass based on the nodes other possible classes.  See
L<Rit::Base::Resource/get>.

For subclassing, create both the subclass (L<Rit::Guides::User>) and
also a sub metaclass that inherits from it and from
L<Rit::Base::Resource> (L<Rit::Guides::User::Meta>). Set
L<Para::Frame/user_class> to the meta class but point to the subclass
in Ritbase with the property C<class_handled_by_perl_module> for the
resource representing the user class.

=cut

##############################################################################

=head2 get

This will call back to L</find_by_anything>.

=cut

sub get
{
#    debug "Getting Rit::Base user $_[1]";
    my $u = eval
    {
	$_[0]->Rit::Base::Resource::get($_[1]);
    };
    if( catch(['notfound']) )
    {
	return undef;
    }

#    debug "Got $u";
    return $u;
}

##############################################################################

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

##############################################################################

=head2 username

=cut

sub username
{
#    debug "in User username: ".datadump($_[0],2);
#    debug "cached ".$_[0]->{username};
#    debug "label ".$_[0]->label;
#    debug "short ".$_[0]->name_short->loc;
#    debug "name ".$_[0]->name->loc;
#    debug "cid ".$_[0]->customer_id;

    return $_[0]->{username} ||= $_[0]->label || $_[0]->name_short->loc;
}

##############################################################################

=head2 id

=cut

sub id ($)
{
    confess( $_[0]||'<undef>' ) unless ref $_[0];
    return $_[0]->Rit::Base::Resource::id();
}

##############################################################################

=head2 name

=cut

sub name
{
    return $_[0]->Rit::Base::Resource::name;
}

##############################################################################

=head2 node

=cut

sub node
{
    carp "----------- TEMPORARY! FIXME";
    return $_[0];
}

##############################################################################

=head2 level

  $node->level

See L<Para::Frame::User/level>

Returns: The level

=cut

sub level
{
    unless( $_[0]->{'level'} )
    {
	my $node = $_[0];
	## See $apphome/doc/notes.txt
	my $level;
	if( $node->has_value({ 'has_access_right' => $C_full_access },['active']) )
	{
	    $level = 40;
	}
	elsif( $node->has_value({ 'has_access_right' => $C_guest_access },['active']) )
	{
	    $level = 0;
	}
	else
	{
	    $level = 10;
	}
	$node->{'level'} = $level;
    }

    return $_[0]->{'level'};
}


##############################################################################

=head2 find_by_anything

Called by L<Rit::Base::Resource/get> that gets called by
L<Para::Frame::User/identify_user>.

Supported args are:

  arclim

=cut

sub find_by_anything
{
    my( $this, $val, $args ) = @_;
    return is_undef unless defined $val;

#    Para::Frame::Logging->this_level(3);

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
	@new = Rit::Base::Resource->get_by_label('guest');
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
	     }, $args)};

	unless(@new)
	{
	    debug 2, "  as non-number, from name";
	    @new = @{ $class->find
		({
		  'name' => $val,
		  is     => $C_login_account,
		 }, $args)};
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

##############################################################################

=head2 verify_password

=cut

sub verify_password
{
    my( $u, $password_encrypted ) = @_;

    $password_encrypted ||= '';

#    debug "Retrieving password for $u->{id}";
    my @pwlist = $u->list('has_password',undef,['active'])->as_array;

    unless(scalar @pwlist)
    {
	my $uname = $u->desig;
	confess "No desig for user" unless $uname;
	debug("$uname has no password");
	cluck "no password";
	return 0;
    }

    foreach my $pwd (@pwlist)
    {
	# Validating password
	#
	if( $password_encrypted eq passwd_crypt($pwd) )
	{
	    return 1;
	}
    }

    debug datadump(\%ENV);
    return 0;
}

##############################################################################

=head2 has_root_access

=cut

sub has_root_access
{
    if( $_[0]->prop('has_access_right',undef,['active'])->equals($C_full_access) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

##############################################################################

=head2 set_default_propargs

For the current request

=cut

sub set_default_propargs
{

    # Since subrequests from the same user may interlace with this
    # request, it must be set for the request

    if( $Para::Frame::REQ )
    {
	$Para::Frame::REQ->{'rb_default_propargs'} = undef;

	if( $_[1] )
	{
	    my $args = parse_propargs( $_[1] );
	    return $Para::Frame::REQ->{'rb_default_propargs'} = $args;
	}
    }
    else
    {
	debug "set_default_propargs without an active REQ";
    }

    return undef;
}

##############################################################################

=head2 default_propargs

For the current request

=cut

sub default_propargs
{
    if( $Para::Frame::REQ )
    {
	return $Para::Frame::REQ->{'rb_default_propargs'} || undef;
    }
    return undef;
}


##############################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $u, $arc, $pred_name, $args_in ) = @_;

    if( $pred_name eq 'name_short' )
    {
	delete $u->{username};
    }
}

##############################################################################

1;
