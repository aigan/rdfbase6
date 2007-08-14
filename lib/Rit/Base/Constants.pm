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
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
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

our %Label; # The initiated constants
our $AUTOLOAD;
our @Initlist; # Constants to export then the DB is online

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
    if( $ARGV[0] and ($ARGV[0] eq 'upgrade') )
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
	$sth_label->execute($colname) or die "could not get constant $colname";
	my( $colid ) = $sth_label->fetchrow_array or confess "could not get constant $colname";
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

#    # Bootstrap the 'is' Pred
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


#######################################################################

=head2 new

=cut

sub new ()
{
    return bless {};
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
	unless( $Label{$label} )
	{
	    my $node = Rit::Base::Resource->get( $id );
	    $Label{$label} = $node;
	}

	push @list, $Label{$label};
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
    my $node = Rit::Base::Resource->get_by_id($id) or return undef;
    if( $node->label )
    {
	return $node;
    }
    else
    {
	confess "Node $id not a constant";
    }
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
    return Rit::Base::Resource->get_by_constant_label( $label );
}



######################################################################

=head2 AUTOLOAD

=cut

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
#    debug "Autoloading constant $AUTOLOAD";
    return  $Label{$AUTOLOAD} || Rit::Base::Constants->get($AUTOLOAD);
}

#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>,
L<Rit::Base>

=cut
