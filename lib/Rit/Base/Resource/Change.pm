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

=head2 changes_add

  $c->changes_add()

  $c->changes_add( $num )

C<$num> defaults to 1

Returns: The new total number of changes

=cut

sub changes_add
{
    return $_[0]->{'changes'} += ($_[1]||1);
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

=head2 newarcs

Returns: a L<Rit::Base::List> of arcs

=cut

sub newarcs
{
    return Rit::Base::List->new($_[0]->{'newarcs'});
}


#########################################################################

=head2 sysdesig

  $c->sysdesig(\%args, $ident)

=cut

sub sysdesig
{
    my( $c, $args, $ident ) = @_;

    $ident ||= 0;
    my $out = "";

    my $deathrow = "";
    foreach my $node (values %{$c->{'deathrow'}})
    {
	$deathrow .= "  ".$node->sysdesig($args)."\n";
    }

    if( length $deathrow )
    {
	$out .= "Deathrow:\n$deathrow";
    }

    my $newarcs = "";
    foreach my $arc (@{$c->{'newarcs'}})
    {
	$newarcs .= "  ".$arc->sysdesig($args)."\n";
    }

    if( length $newarcs )
    {
	$out .= "Newarcs:\n$newarcs";
    }

    my $rows = "";
    foreach my $row (sort {$a <=> $b} keys %{$c->{'row'}})
    {
	if( my $arc_id = $c->{'row'}{$row}{'arc_id'} )
	{
	    $rows .= sprintf "  %.2d -> arc_id %d\n", $row, $arc_id;
	}

	if( my $pred_id = $c->{'row'}{$row}{'pred_id'} )
	{
	    $rows .= sprintf "  %.2d -> pred_id %d\n", $row, $pred_id;
	}
    }

    if( length $rows )
    {
	$out .= "Rows:\n$rows";
    }

    $out .= "Changes: $c->{changes}\n";

    return $out;
}


#######################################################################

=head2 autocommit

  $this->autocommit

This will submit all new arcs.

If the current user has root access; All submitted arcs will be activated.

Returns: The number of new arcs processed

=cut

sub autocommit
{
    my $newarcs = $_[0]->newarcs;
    my $cnt = $newarcs->size;
    if( $cnt )
    {
	my $root_access = $Para::Frame::REQ->user->has_root_access;
	if( $root_access )
	{
	    debug "Activating new arcs:";
	}
	else
	{
	    debug "Submitting new arcs:";
	}
	my( $arc, $error ) = $newarcs->get_first;
	while(! $error )
	{
	    debug "* ".$arc->sysdesig;

	    if( $arc->is_new )
	    {
		$arc->submit;

		if( $root_access )
		{
		    $arc->activate;
		}
	    }

	    ( $arc, $error ) = $newarcs->get_next;
	}
	debug "- EOL";
    }

    return $cnt;
}


#########################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Resource>

=cut
