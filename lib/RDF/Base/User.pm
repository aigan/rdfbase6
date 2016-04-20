package RDF::Base::User;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2016 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::User

=cut

use 5.010;
use strict;
use warnings;
use base qw(Para::Frame::User);

use DBI;
use Carp qw( confess cluck carp );
use Time::HiRes qw( time );
use Crypt::PRNG;
use Crypt::Digest::SHA512;

use Para::Frame::Utils qw( debug passwd_crypt trim datadump catch throw );
use Para::Frame::User;
use Para::Frame::Reload;

use RDF::Base::Utils qw( is_undef parse_propargs query_desig solid_propargs );
use RDF::Base::Constants qw( $C_login_account $C_full_access $C_content_management_access $C_guest_access $C_sysadmin_group );

use constant R => 'RDF::Base::Resource';


=head1 DESCRIPTION

Inherits from L<Para::Frame::User>

This class doesn't inherit from L<RDF::Base::Resoure>. But see
L<RDF::Base::User::Meta>.

Resources, when initiated, will be placed in the right class based on
the C<class_handled_by_perl_module> property. Since a resource can
have multiple classes, the class in itself can not inherit from
L<RDF::Base::Resource>. The resource will be placed in a metaclass
that inherits from this class and from L<RDF::Base::Resource>.

The L<RDF::Base::User::Meta> is used during startup. It is listed in
C<%RDF::Base::LOOKUP_CLASS_FOR> to make it be reblessd in the right
metaclass based on the nodes other possible classes.  See
L<RDF::Base::Resource/get>.

For subclassing, create both the subclass (L<RDF::Guides::User>) and
also a sub metaclass that inherits from it and from
L<RDF::Base::Resource> (L<RDF::Guides::User::Meta>). Set
L<Para::Frame/user_class> to the meta class but point to the subclass
in RDFbase with the property C<class_handled_by_perl_module> for the
resource representing the user class.

=cut

##############################################################################

=head2 get

This will call back to L<RDF::Base::Resource/get>.

=cut

sub get
{
#    debug "Getting RDF::Base user $_[1]";
    my $u = eval
    {
        $_[0]->RDF::Base::Resource::get($_[1]);
    };
    if ( catch(['notfound']) )
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
    return $_[0]->RDF::Base::Resource::id();
}

##############################################################################

=head2 name

=cut

sub name
{
    return $_[0]->RDF::Base::Resource::name;
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
    unless ( $_[0]->{'level'} )
    {
        my $node = $_[0];
        ## See $apphome/doc/notes.txt
        my $level;
        if ( $node->has_value({ 'has_access_right' => $C_full_access },['active']) )
        {
            $level = 40;
        }
        elsif ( $node->has_value({ 'has_access_right' => $C_content_management_access },['active']) )
        {
            $level = 20;
        }
        elsif ( $node->has_value({ 'has_access_right' => $C_guest_access },['active']) )
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

Called by L<RDF::Base::Resource/get> that gets called by
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
    if ( $val eq 'guest' )
    {
        debug 2, "  as guest";
#	warn datadump($C_guest_access, 2);
        my $class = ref($_[0]) || $_[0];
        @new = R->get_by_label('guest');
    }
    elsif ( $val !~ /^\d+$/ )
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

    return RDF::Base::List->new(\@new);

}

##############################################################################

=head2 verify_password

  $u->verify_password( $password_iphashed )

For secure hashed stored passwords, the supplied password should be
the value from has_password_hash, additionally iphashed with
passwd_crypt()

=cut

sub verify_password
{
    my( $u, $password_encrypted ) = @_;

    $password_encrypted ||= '';

#    debug 1, "Retrieving password for $u->{id}";
    my $pwhash = $u->first_prop('has_password_hash',undef,['active']);
    my @pwlist = $u->list('has_password',undef,['active'])->as_array;

    unless( $pwhash or @pwlist)
    {
        my $uname = $u->desig;
        confess "No desig for user" unless $uname;
        debug("$uname has no password");
        cluck "no password";
        return 0;
    }

    if( $pwhash ) # Do not use unhashed passwords if hashed exist
    {
        debug "Should do pw hash comparison";

        # Validating password
        #
        if( $password_encrypted eq passwd_crypt( $pwhash) )
        {
            return 1;
        }

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

#    debug "Verifying password failed:\n".datadump(\%ENV);
    return 0;
}

##############################################################################

=head2 has_root_access

=cut

sub has_root_access
{
    if ( $_[0]->prop('has_access_right',undef,['active'])->equals($C_full_access) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

##############################################################################

=head2 has_cm_access

=cut

sub has_cm_access
{
    if( R->get_by_label('rdfbase')->has_version->literal < 18 )
    {
        return $_[0]->has_root_access;
    }

    if ( $_[0]->prop('has_access_right',undef,['active'])->equals($C_content_management_access) )
    {
        return 1;
    }

    return $_[0]->has_root_access;
}

##############################################################################

=head2 require_write_access_to

=cut

sub require_write_access_to
{
    return if $_[0]->has_write_access_to( $_[1] );
    throw( 'denied', "You do not have access to modify ".$_[1]->desig );
}

##############################################################################

=head2 has_write_access_to

=cut

sub has_write_access_to
{
    my( $u, $n ) = @_;

    return 1 if $u->has_root_access;
    return 1 if $n->is_owned_by( $u );
    return 0 if $C_sysadmin_group->equals($n->write_access);
    return 1;
}

##############################################################################

=head2 set_default_propargs

For the current request

=cut

sub set_default_propargs
{

    # Since subrequests from the same user may interlace with this
    # request, it must be set for the request

    if ( $Para::Frame::REQ )
    {
        $Para::Frame::REQ->{'rb_default_propargs'} = undef;

        if ( $_[1] )
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
    if ( $Para::Frame::REQ )
    {
        return $Para::Frame::REQ->{'rb_default_propargs'} || undef;
    }
    return undef;
}


##############################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $u ) = @_;

    if( $u->has_pred('name_short') or $u->has_pred('has_access_right') )
    {
        $Para::Frame::REQ->require_root_access; #Protect access rights
    }
}


##############################################################################

=head2 on_unbless

=cut

sub on_unbless
{
    my( $u ) = @_;

    if( $C_sysadmin_group->equals($u->write_access) )
    {
        $Para::Frame::REQ->require_root_access; #Protect access rights
    }
}


##############################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $u, $arc, $pred_name, $args_in ) = @_;

#    debug "In RB::User on_arc_add $pred_name";

    if( $pred_name eq 'name_short' )
    {
        $Para::Frame::REQ->require_root_access; #Protect login name
        delete $u->{username};
    }
    elsif( $pred_name eq 'has_access_right' )
    {
        $Para::Frame::REQ->require_root_access; #Protect access rights
        $u->set_write_access( $C_sysadmin_group );
        $u->set_owned_by( $u );
    }

    if( $C_sysadmin_group->equals($u->write_access) )
    {
        if( $pred_name ~~ [qw(has_secret has_password_hash )] )
        {
            $Para::Frame::REQ->user->require_write_access_to( $u );
        }
    }

    $u->clear_caches;
}

##############################################################################

=head2 on_arc_del

=cut

sub on_arc_del
{
    my( $u, $arc, $pred_name, $args_in ) = @_;

    if( $C_sysadmin_group->equals($u->write_access) )
    {
        if( $pred_name ~~ [qw(has_secret has_password_hash )] )
        {
            $Para::Frame::REQ->user->require_write_access_to( $u );
        }
        elsif( $pred_name ~~ [qw(name_short has_access_right )] )
        {
            $Para::Frame::REQ->require_root_access;
        }
    }

    $u->clear_caches(@_);
}

##############################################################################

=head2 clear_caches

=cut

sub clear_caches
{
    delete  $_[0]->{'level'};
}

##############################################################################

=head2 set_working_on

=cut

sub set_working_on
{
    my( $u, $node_in ) = @_;
    my( $args ) = solid_propargs();

    my $n = R->get($node_in);

    return 0 if $n->revprop('working_on');
    return $u->add({working_on => $n}, $args);
}

##############################################################################

=head2 remove_working_on

=cut

sub remove_working_on
{
    my( $u, $node_in ) = @_;
    my( $args ) = solid_propargs();

    my $n = R->get($node_in);

#    debug "Remove arc for ".$n->sysdesig;
#    debug "List is ". $u->arc_list('working_on', $n, $args)->sysdesig;

    return $u->arc_list('working_on', $n, $args)->remove($args);
}

##############################################################################

=head2 password_hash

Random documents of interest..:
https://crackstation.net/hashing-security.htm
https://www.owasp.org/index.php/Password_Storage_Cheat_Sheet

=cut

sub password_hash
{
    my( $u, $password_plain ) = @_;
    my( $args ) = solid_propargs();

    my $server_salt = $Para::Frame::CFG->{server_salt}
      or die "Server salt not configured";

    my $personal_salt = $u->secret($args);

    # Could have used Crypt::KeyDerivation::pbkdf2, for slowing down
    # dictionary attacks in cases where salts and hashes are known.
    # Should migrate to Argon2 when easily availible. (not argon2i)

    my $d = Crypt::Digest::SHA512->new;
    $d->add($server_salt, $personal_salt, $password_plain);

    ### Store password with a prefix SIMILAR to glibc crypt. This is
    ### for attaching the hashing method used.

    # $6$$ == SHA512 b64u

    my $password_hash = '$6$$' . $d->b64udigest;

    return $password_hash;
}

##############################################################################

=head2 password_token

=cut

sub password_token
{
    my( $u, $password_plain ) = @_;
    my( $args ) = solid_propargs();

    if( $u->has_pred('has_password_hash',undef,$args) )
    {
        return $u->password_hash($password_plain);
    }

    return $password_plain;
}

##############################################################################

=head2 set_password_hash

=cut

sub set_password_hash
{
    my( $u, $password_plain, $args_in ) = @_;
    my( $args ) = solid_propargs( $args_in );

#    debug "About to set password to $password_plain"; ### SECRET

    my $password_hash = $u->password_hash( $password_plain );
    $u->update({has_password_hash=>$password_hash},$args);
    $u->arc_list('has_password',undef,$args)->remove($args);

    return $password_hash;
}

##############################################################################

=head2 secret

=cut

sub secret
{
    my( $u, $args ) = @_;

    my $secret = $u->first_prop('has_secret',undef,$args);
    unless( $secret )
    {
        my $prng = Crypt::PRNG->new;
        $secret = $prng->bytes_b64u(64); # represented by 86 bytes
        $u->update({has_secret=>$secret},$args);
    }

    return $secret;
}

##############################################################################

=head2 check_security

throws ececption if unsecure

=cut

sub check_security
{
    my( $u, $args ) = @_;

    unless( length( $u->first_prop('name_short',undef,$args)->plain) > 2 )
    {
        throw 'validation', "name_short missing";
    }
    unless( $u->prop('is',$C_login_account,$args) )
    {
        throw 'validation', "Not a login account";
    }
    unless( $C_sysadmin_group->equals($u->write_access) )
    {
        throw 'validation', "Account no secure";
    }
    unless( $u->is_owned_by( $u ) )
    {
        throw 'validation', "Account no secure";
    }

    return 1;
}

##############################################################################

1;
