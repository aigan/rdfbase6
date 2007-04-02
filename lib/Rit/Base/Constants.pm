#  $Id$  -*-cperl-*-
package Rit::Base::Constants;
#=====================================================================
#
# DESCRIPTION
#   Ritbase constants class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Constants

=head1 SYNOPSIS

  use Rit::Base::Constants qw( $C_business_persona );

  $label = $C_business_persona->loc;

=cut

use strict;
use Carp qw( croak cluck confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

#use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base;
use Rit::Base::Utils qw( is_undef );
use Rit::Base::Constant;

our %Constant; # The initiated constants
our %Constobj; # The initiated constant objects
our $AUTOLOAD;
our @Initlist; # Constants to export then the DB is online
our %COLTYPE;

#######################################################################

=head2 import

=cut

sub import
{
    my $class = shift;

    my $callpkg = caller();
    no strict 'refs'; # Symbolic refs

    my $temp = bless{NOT_INITIALIZED=>1};

    my $updating_db = 0;
    if( $ARGV[0] eq 'upgrade' )
    {
	$updating_db = 1;
    }

    foreach my $const ( @_ )
    {
	$const =~ /^\$C_(\w+)/ or croak "malformed constant: $const";
	debug 2, "Package $callpkg imports $1";

	if( $Rit::dbix and not $updating_db  )
	{
	    my $obj = $class->get($1);
	    *{"$callpkg\::C_$1"} = \ $obj;
	}
	else
	{
	    push @Initlist, ["$callpkg\::C_$1", $1];

	    # Temporary placeholder
	    *{"$callpkg\::C_$1"} = \ $temp;
	}
    }
}


#######################################################################

=head2 new

=cut

sub new ()
{
    return bless {};
}


#######################################################################

=head2 new_by_rec

=cut

sub new_by_rec
{
    my( $this, $rec, $node ) = @_;

    $node ||= Rit::Base::Resource->get_by_id( $rec->{'node'} );

    my $const = bless $rec, "Rit::Base::Constant";
    $const->{'node'} = $node;

    return $const;
}


######################################################################

=head2 find

  Rit::Base::Constants->find()

Currently doesn't take any params.

Returns all constants.

Returns:

a L<Rit::Base::List> of L<Rit::Base::Constant> elements

=cut

sub find
{
    my( $this ) = @_;

#    debug "Looking up all constants";

    my @list;
    my $sth = $Rit::dbix->dbh->prepare(
	      "select * from node where label is not null");
    $sth->execute();
    while( my $rec = $sth->fetchrow_hashref )
    {
	my $label = $rec->{'label'};
	my $id    = $rec->{'node'};

#	debug "Found $id: $label";
	unless( $Constant{$label} )
	{
	    my $node = Rit::Base::Resource->get( $id );
	    $Constant{$label} = $node;
	}

	unless( $Constobj{ $id } )
	{
	    $Constobj{ $id } = $this->new_by_rec( $rec, $Constant{$label} );
	}

	push @list, $Constobj{ $id };
    }
    $sth->finish;

    return Rit::Base::List->new(\@list);
}



######################################################################

=head2 get_by_id

  Rit::Base::Constants->get_by_id( $id )

Returns:

a L<Rit::Base::Constant> object or L<Rit::Base::Undef>

=cut

sub get_by_id
{
    my( $this, $id ) = @_;

    unless( $Constobj{$id} )
    {
	my $sth = $Rit::dbix->dbh->prepare(
		  "select * from node where node=?");
	$sth->execute( $id );
	my( $rec ) = $sth->fetchrow_hashref;
	$sth->finish;

	unless( $rec )
	{
	    return is_undef;
	}

	$Constobj{$id} = $this->new_by_rec($rec, $Constant{$rec->{'label'}});
    }

    # TODO: Handle resetting of the given nodes

    return $Constobj{$id};
}



######################################################################

=head2 get

  Rit::Base::Constants->get( $label )

Returns:

a L<Rit::Base::Resource>

Exceptions:

croaks if constant doesn't exist

=cut

sub get
{
    my( $this, $label ) = @_;

    unless( $Constant{$label} )
    {
#	debug "Initiating constant $label";
	my $sth = $Rit::dbix->dbh->prepare(
		  "select node from node where label=?");
	$sth->execute( $label );
	my( $id ) = $sth->fetchrow_array;
	$sth->finish;

	unless( $id )
	{
	    croak "Constant $label doesn't exist";
	}

	debug "Fetching constant $id";
	$Constant{$label} = Rit::Base::Resource->get( $id );
    }

    # TODO: Handle resetting of the given nodes

    return $Constant{$label};
}



######################################################################

=head2 get_set

  Rit::Base::Constants->get_set( $label, $node )

Creates the constant if it doesn't exist

Returns:

The C<$node>

Exceptions:

Node mismatch - If existing constant doesn't match given node

=cut

sub get_set
{
    my( $this, $label, $node_in_in ) = @_;

    my $node_in = Rit::Base::Resource->get( $node_in_in );

    confess("Node in not found: ". $node_in_in)
      unless $node_in;

    unless( $Constant{$label} )
    {
	my $sth = $Rit::dbix->dbh->prepare(
		  "select node from node where label=?");
	$sth->execute( $label );
	my( $id ) = $sth->fetchrow_array;
	$sth->finish;

	if( $id )
	{
	    $Constant{$label} = Rit::Base::Resource->get( $id );
	}
	else
	{
	    $this->add( $label, $node_in );
	    $Constant{$label} = $node_in;
	}

    }

    my $node_out = $Constant{$label};

    unless( $node_in->equals( $node_out ) )
    {
	my $in_id = $node_in->id;
	my $out_id = $node_out->id;
	confess "Node mismatch: $in_id != $out_id";
    }

    # TODO: Handle resetting of the given nodes

    return $node_out;
}


######################################################################

=head2 init

=cut

sub init
{
    my( $class ) = @_;

    my $dbh = $Rit::dbix->dbh;
    my $sth_label = $dbh->prepare("select node from node where label=?") or die;
    my $sth_child = $dbh->prepare("select subj from arc where pred=2 and obj=?") or die;
    foreach my $colname (qw(valdate valfloat valtext valbin))
    {
	$sth_label->execute($colname) or die;
	my( $colid ) = $sth_label->fetchrow_array or die;
	$sth_label->finish;

	debug "Caching colname $colname";
	$sth_child->execute($colid) or die;
	while(my( $nid ) = $sth_child->fetchrow_array)
	{
	    $Rit::Base::COLTYPE_valtype2name{$nid} = $colname;
	    debug "Valtype $nid = $colname";
	}
	$sth_child->finish;

	$Rit::Base::COLTYPE_valtype2name{$colid} = $colname;
    }
    $Rit::Base::COLTYPE_valtype2name{5} = 'obj';


    #################################

#    # Bootstrap the is Pred
#    debug "Bootstrapping is";
#    Rit::Base::Pred->new(1)->init();
#    debug "Bootstrapping class_handled_by_perl_module ";
#    $sth_label->execute('class_handled_by_perl_module');
#    Rit::Base::Pred->new($sth_label->fetchrow_array)->init();
#    $sth_label->finish;
#    debug "Bootstrapping done";

    #################################

    no strict 'refs'; # Symbolic refs
    foreach my $export (@Initlist)
    {
	my $obj = $class->get($export->[1]);
	*{$export->[0]} = \ $obj;
    }
}


######################################################################

=head2 add

  Rit::Base::Constants->add( $label, $node )

Adds a constant to the database.

=cut

sub add
{
    my( $class, $label, $node ) = @_;

    die "Constant labels cannot start with 'C_'"
      if $label =~ /^C_/;

    my $uid = $Para::Frame::REQ->user->id;

    $Rit::dbix->commit;
    eval
    {
	$Rit::dbix->dbh->do("INSERT INTO node (label,node,created,created_by,updated,updated_by) values (?,?,now(),?,now(),?)",
			    {}, $label, $node->id, $uid, $uid);
    };

    if( $@ )
    {
	if( $Rit::dbix->dbh->state eq 23505 )
	{
	    $Rit::dbix->rollback;
	}
	else
	{
	    die $@;
	}
    }
}


######################################################################

=head2 AUTOLOAD

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
#    debug "Autoloading constant $AUTOLOAD";
    return  $Constant{$AUTOLOAD} || Rit::Base::Constants->get($AUTOLOAD);
}

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>,
L<Rit::Base>

=cut
