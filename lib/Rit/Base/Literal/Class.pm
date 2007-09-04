#  $Id$  -*-cperl-*-
package Rit::Base::Literal::Class;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Literal Class class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::Class

=cut

use strict;
use Carp qw( cluck confess longmess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use Rit::Base::Constants;
use Rit::Base::Resource;
use Rit::Base::Utils qw( is_undef parse_propargs );

use base qw( Rit::Base::Resource );

our %COLTYPE_num2name =
(
 1 => 'obj',
 2 => 'valfloat',
 3 => 'valbin',
 4 => 'valdate',
 5 => 'valtext',
 6 => 'value',
);

our %COLTYPE_name2num;

our %COLTYPE_valtype2name; # Initiated in Rit::Base::Constants

our $id; # Node id


=head1 DESCRIPTION

Inherits from L<Rit::Base::Resource>

=cut


######################################################################

=head2 on_startup

=cut

sub on_startup
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
	    $COLTYPE_valtype2name{$nid} = $colname;
	    debug "Valtype $nid = $colname";
	}
	$sth_child->finish;

	$COLTYPE_valtype2name{$colid} = $colname;
    }
    $COLTYPE_valtype2name{5} = 'obj';

    %COLTYPE_name2num = reverse %COLTYPE_num2name;


    debug "Initiating literal_class";

    my $sth = $Rit::dbix->dbh->
      prepare("select node from node where label=?");
    $sth->execute( 'literal_class' );
    $id = $sth->fetchrow_array; # Store in GLOBAL id
    $sth->finish;

    #################### CREATION
    unless( $id )
    {
	my( $args, $arclim, $res ) = parse_propargs('auto');
	my $req = Para::Frame::Request->new_bgrequest();
	$req->user->set_default_propargs({activate_new_arcs => 1 });

	my $lc = Rit::Base::Resource->get('new');
	$id = $lc->id;
	$lc->set_label('literal_class');
	Rit::Base::Resource->commit;
    }


    $Rit::Base::Constants::Label{'literal_class'} =
      Rit::Base::Resource->get($id);
}


#######################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $node, $class_old, $args_in ) = @_;

    my $scofs = $node->list('scof');
    while( my $parent = $scofs->get_next_nos )
    {
	my $label = $parent->label;
	next unless $label;

	if( $COLTYPE_name2num{$label} )
	{
	    $COLTYPE_valtype2name{ $node->id } = $label;
	    if( debug )
	    {
		debug sprintf "Adding valtype %d -> %s in coltype cache",
		  $node->id, $label;
	    }
	    last;
	}
    }
}

#######################################################################

=head2 on_unbless

=cut

sub on_unbless
{
    my( $node, $class_new, $args_in ) = @_;

    delete $COLTYPE_valtype2name{ $node->id };

    if( debug )
    {
	debug sprintf "Removing valtype %d from coltype cache",
	  $node->id;
    }
}

######################################################################

=head2 coltype_by_valtype_id

Rit::Base::Literal::Class->coltype_by_valtype_id( $id )

=cut

sub coltype_by_valtype_id
{
    return $COLTYPE_valtype2name{ $_[1] };
}


######################################################################

=head2 coltype_by_coltype_id

Rit::Base::Literal::Class->coltype_by_coltype_id( $name )

=cut

sub coltype_by_coltype_id
{
    return $COLTYPE_num2name{ $_[1] };
}


######################################################################

=head2 coltype_id_by_coltype

Rit::Base::Literal::Class->coltype_id_by_coltype( $id )

=cut

sub coltype_id_by_coltype
{
    return $COLTYPE_name2num{ $_[1] };
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Resource>,
L<Rit::Base::Constants>,

=cut
