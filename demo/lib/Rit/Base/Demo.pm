#  $Id$  -*-cperl-*-
package Rit::Base::Demo;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base;
use Rit::Base::Utils qw( string );
use Rit::Base::Setup;

our $CFG;


######################################################################

=head2 store_cfg

=cut

sub store_cfg
{
    $CFG = $_[1];
}


######################################################################

=head2 on_done

  Runs after each request

=cut

sub on_done ()
{
    Rit::Base->on_done();
}


#######################################################################

=head2 on_configure

Adds class given by C<resource_class> as a parent to
L<Rit::Guides::Resource>. That class must be loaded during startup.


=cut

sub on_configure
{
    debug "In Guides on_configure";
    if( my $resource_class = $Para::Frame::CFG->{'resource_class'} )
    {
	debug "Adding $resource_class";
	push @Rit::Base::Resource::ISA, $resource_class;
    }
}

#######################################################################

=head2 initialize_db

=cut

sub initialize_db
{
    if( $ARGV[0] and ($ARGV[0] eq 'setup_db') )
    {
	Rit::Base::Setup->setup_db();
    }



    return; ### NOTHING TO DO HERE NOW


    my $req = Para::Frame::Request->new_bgrequest();

    my $R = Rit::Base->Resource;
    my $P = Rit::Base->Pred;
    my $C = Rit::Base->Constants;
#    my $dbix = $Rit::dbix;

#    my $rbc = $R->get({code => 'ritbase_core_resource'});

    ###

    debug 1, "Adding/updating nodes and preds: done!";
}

######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>
L<Rit::Base>

=cut
