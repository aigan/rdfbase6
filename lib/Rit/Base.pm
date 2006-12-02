#  $Id$  -*-cperl-*-
package Rit::Base;
#=====================================================================
#
# DESCRIPTION
#   Ritbase package main class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base - The ultimate database

=cut

=head1 DESCRIPTION

See L<Rit::Base::Object> for the baseclass for most classes.

=cut

use vars qw( $VERSION );

BEGIN
{
    $VERSION = "4.50";
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame;
use Para::Frame::Reload;

use Rit::Base::Resource;
use Rit::Base::Arc;
use Rit::Base::Pred;

use Rit::Base::Utils qw( log_stats_commit );

# Used in Rit::Base::Resource->first_bless()
our %LOOKUP_CLASS_FOR =
    (
     Rit::Base::Resource   => 1,
     Rit::Base::User::Meta => 1,
    );


#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name

=cut


sub init
{
    my( $this, $dbix ) = @_;

#    Rit::Base::Resource->init( $dbix );
#    Rit::Base::Arc->init( $dbix );
#    Rit::Base::Pred->init( $dbix );
}



#######################################################################

=head2 Resource

Returns class object for Rit::Base::Resource

=cut

sub Resource ()
{
    return 'Rit::Base::Resource';
}

######################################################################

=head2 Arc

Returns class boject for Rit::Base::Arc

=cut

sub Arc ()
{
    return 'Rit::Base::Arc';
}

######################################################################

=head2 Pred

Returns class boject for Rit::Base::Pred

=cut

sub Pred ()
{
    return 'Rit::Base::Pred';
}

######################################################################

=head2 Constants

Returns class boject for Rit::Base::Constants

=cut

sub Constants ()
{
    return 'Rit::Base::Constants';
}

######################################################################

=head2 on_done

  Runs after each request

=cut

sub on_done ()
{
    # Releas arc locks
    Rit::Base::Arc->unlock_all();
    log_stats_commit();
}

######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>
L<Rit::Base::Object>,
L<Rit::Base::Search>,
L<Rit::Base::Utils>

=cut
