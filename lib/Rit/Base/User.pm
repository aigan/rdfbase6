#  $Id$  -*-cperl-*-
package Rit::Base::User;

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

use base qw(Para::Frame::User Rit::Base::Resource);


# Getting the real node instead...
sub get
{
#    debug "Getting user $_[1]";

#    if( $_[1] eq 'guest' )
#    {
#	# Special case
#	my $rec =
#	{
#	 name => 'Gäst',
#	 username => 'guest',
#	 uid      => 0,
#	 level    => 0,
#	};
#
#	my $class = ref($_[0]) || $_[0];
#	return bless $rec, $class;
#    }

    return $_[0]->Rit::Base::Resource::get($_[1]);
}

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

sub username
{
#    warn "in User username: ".datadump($_[0],3);

    return $_[0]->{username} ||= $_[0]->name_short->loc || $_[0]->name->loc || $_[0]->customer_id;
}

sub id ($)
{
    confess( $_[0]||'<undef>' ) unless ref $_[0];
    return $_[0]->Rit::Base::Resource::id();
}

sub name
{
    return $_[0]->Rit::Base::Resource::name;
}

sub node
{
    carp "----------- TEMPORARY! FIXME";
    return $_[0];
}

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
	      is_eq_5   => $C_login_account,
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
	      is_eq_5   => $C_login_account,
	     })};

	unless(@new)
	{
	    debug 2, "  as non-number, from name";
	    @new = @{ $class->find
		({
		  'name' => $val,
		  is_eq_5   => $C_login_account,
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

1;
