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
    $VERSION = "6.50";
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame;
use Para::Frame::Reload;

use Rit::Base::Resource;
use Rit::Base::Arc;
use Rit::Base::Pred;

# Used in Rit::Base::Resource->first_bless()
our %LOOKUP_CLASS_FOR =
    (
     Rit::Base::Resource   => 1,
     Rit::Base::User::Meta => 1,
    );

our %COLTYPE_num2name =
(
 1 => 'obj',
 2 => 'valfloat',
 3 => 'valbin',
 4 => 'valdate',
 5 => 'valtext',
 6 => 'value',
);



#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name

=cut


sub init
{
    my( $this, $dbix ) = @_;

    warn "Adding hooks for Rit::Base\n";

    Para::Frame->add_hook('on_error_detect', sub
			  {
			      Rit::Base::User->revert_from_temporary_user();
			      $Para::Frame::REQ->user->set_default_propargs(undef);
			  });

    Para::Frame->add_hook('on_startup', sub
			  {
 			      Rit::Base::Constants->init;
			  });

    Para::Frame->add_hook('before_db_commit', sub
			  {
			      Rit::Base::Resource->commit();
			  });
    Para::Frame->add_hook('after_db_rollback', sub
			  {
			      Rit::Base::Resource->rollback();
			  });



    my $global_params =
    {
     find            => sub{ Rit::Base::Resource->find($_[0]) },
     get             => sub{ Rit::Base::Resource->get(@_) },
     new_search      => sub{ Rit::Base::Search->new(@_) },
     find_preds      => sub{ Rit::Base::Pred->find(@_) },
     find_arcs       => sub{ Rit::Base::Arc->find(@_) },
     find_rules      => sub{ Rit::Base::Rule->find(@_) },
     find_constants  => sub{ Rit::Base::Constants->find(@_) },
     query_desig     => \&Rit::Base::Utils::query_desig,
     C               => Rit::Base::Constants->new,
     timediff        => \&Para::Frame::Utils::timediff,
     timeobj         => sub{ Rit::Base::Time->get( @_ ) },
    };
    Para::Frame->add_global_tt_params( $global_params );

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
}

######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>
L<Rit::Base::Object>,
L<Rit::Base::Search>,
L<Rit::Base::Utils>

=cut
