#  $Id$  -*-cperl-*-
package Rit::Base::Resource::Change;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource Change class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Resource::Change

=cut

use strict;

use Carp qw( cluck confess croak carp shortmess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch create_file trim debug datadump
			   package_to_module );

use Rit::Base::Resource;
use Rit::Base::Utils qw();

=head1 DESCRIPTION

Represent a group of changes done to the database.

=cut


#########################################################################

=head2 new

=cut

sub new
{
    my $class = shift;
    return bless
    {
     'deathrow' => {}, # arcs to remove
     'newarcs'  => [], # Arcs to submit and maby activate
     'changes'  => 0,  # Actual things changed
     'row'      => {}, # Holds relating field info for row
    }, $class;
}


#########################################################################

=head2 add_to_deathrow

=cut

sub add_to_deathrow
{
    my( $c, $arc ) = @_;
    $c->{'deathrow'}{ $arc->id } = $arc;
}


#########################################################################

=head2 remove_from_deathrow

=cut

sub remove_from_deathrow
{
    my( $c, $arc ) = @_;
    delete $c->{'deathrow'}{ $arc->id };
}


#########################################################################

=head2 deathrow_list

=cut

sub deathrow_list
{
    return values %{$_[0]->{'deathrow'}};
}


#########################################################################

=head2 pred_id_by_row

=cut

sub pred_id_by_row
{
    my( $c, $rowno ) = @_;
    return $c->{'row'}{$rowno}{'pred_id'};
}


#########################################################################

=head2 set_pred_id_by_row

=cut

sub set_pred_id_by_row
{
    my( $c, $rowno, $pred_id ) = @_;
    return $c->{'row'}{$rowno}{'pred_id'} = $pred_id;
}


#########################################################################

=head2 arc_id_by_row

=cut

sub arc_id_by_row
{
    my( $c, $rowno ) = @_;
    return $c->{'row'}{$rowno}{'arc_id'};
}


#########################################################################

=head2 set_arc_id_by_row

=cut

sub set_arc_id_by_row
{
    my( $c, $rowno, $arc_id ) = @_;
    return $c->{'row'}{$rowno}{'arc_id'} = $arc_id;
}


#########################################################################

=head2 changes

=cut

sub changes
{
    return $_[0]->{'changes'};
}


#########################################################################

=head2 add_newarc

=cut

sub add_newarc
{
    push @{$_[0]->{'newarcs'}}, $_[1];
    return $_[1];
}


#########################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Resource>

=cut
