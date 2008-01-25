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
use Para::Frame::Utils qw( debug package_to_module );

use Rit::Base::Constants qw( $C_literal );
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

our %COLTYPE_valtype2name; # For bootstrapping

our $id; # Node id


=head1 DESCRIPTION

Inherits from L<Rit::Base::Resource>

=cut


#######################################################################

=head2 on_startup

=cut

sub on_startup
{
    my( $class ) = @_;

    debug "Initiating valtypes";

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

    unless( $id )
    {
	die "Failed to initiate literal_class constant";


    #################### CREATION
#	my( $args, $arclim, $res ) = parse_propargs('auto');
#	my $req = Para::Frame::Request->new_bgrequest();
#	$req->user->set_default_propargs({activate_new_arcs => 1 });
#
#	my $lc = Rit::Base::Resource->get('new');
#	$id = $lc->id;
#	$lc->set_label('literal_class');
#	Rit::Base::Resource->commit;
    }


    $Rit::Base::Constants::Label{'literal_class'} =
      Rit::Base::Resource->get($id);
}


#######################################################################

=head2 set_valtype2name

=cut

sub set_valtype2name
{
    my( $node ) = @_;

    my $scofs = $node->list('scof');
    my $found = 0;
    while( my $parent = $scofs->get_next_nos )
    {
	my $label = $parent->label;
	next unless $label;

	if( $COLTYPE_name2num{$label} ) #not expecting 6
	{
	    $node->{'lit_coltype'} =
	      $COLTYPE_valtype2name{ $node->id } = $label;
	    if( debug )
	    {
		debug sprintf "Adding valtype %d -> %s in coltype cache",
		  $node->id, $label;
	    }
	    $found ++;
	    last;
	}
    }

    unless( $found )
    {
	if( my $label = $node->label )
	{
	    if( $COLTYPE_name2num{$label} )
	    {
		$node->{'lit_coltype'} =
		  $COLTYPE_valtype2name{ $node->id } = $label;
		if( debug )
		{
		    debug sprintf "Adding valtype %d -> %s in coltype cache",
		      $node->id, $label;
		}
		$found ++;
	    }
	}
    }

    unless( $found )
    {
	debug sprintf "Removing valtype %d -> %s in coltype cache",
	  $node->id, $COLTYPE_valtype2name{ $node->id };
	delete $node->{'lit_coltype'};
	delete $COLTYPE_valtype2name{ $node->id };
    }
}


#######################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $node, $class_old, $args_in ) = @_;
    $node->set_valtype2name();
}


#######################################################################

=head2 on_unbless

=cut

sub on_unbless
{
    my( $node, $class_new, $args_in ) = @_;
    $node->set_valtype2name();
}


#######################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $node, $arc, $pred_name, $args_in ) = @_;

    if( $pred_name eq 'scof' )
    {
	$node->set_valtype2name();
    }
}


#######################################################################

=head2 on_arc_del

=cut

sub on_arc_del
{
    my( $node, $arc, $pred_name, $args_in ) = @_;

    if( $pred_name eq 'scof' )
    {
	$node->set_valtype2name();
    }
}


#######################################################################

=head2 coltype

  $n->coltype()

This will give the coltype that instances of the literal will
have. (instance instance coltype).

Will not return C<obj>

=cut

sub coltype
{
    return(
	   ( $_[0]->{'lit_coltype'}
	     ||= $COLTYPE_valtype2name{ $_[0]->id } )
	   || confess("coltype missing for $_[0]->{id}")
	  );
}


#######################################################################

=head2 coltype_id

  $n->coltype_id()

This will give the coltype id that instances of the literal will
have. (instance instance coltype).

Will not return the C<obj> id.

=cut

sub coltype_id
{
    return $COLTYPE_name2num{ $_[0]->coltype };
}


#########################################################################

=head2 instance_class

  $n->instance_class()

Get the perl class name that handles instances of this class.

It will be retrieved by the class_handled_by_perl_module property, or
for Literals, by the corresponding coltype.

Literals, arcs and preds must only have ONE class. Other resoruces may
have multiple classses.

Returns: the class name as a plain string

=cut

sub instance_class
{
    my( $node ) = @_;

    my $id = $node->id;
    my $classname = $Rit::Base::Cache::Class{ $id };
    unless( $classname )
    {
	if( my $class = $node->first_prop('class_handled_by_perl_module') )
	{
	    eval
	    {
		$classname = $class->first_prop('code')->plain
		  or confess "No classname found for class $class->{id}";
		require(package_to_module($classname));
	    };
	    if( $@ )
	    {
		debug $@;
	    }
	    else
	    {
		$Rit::Base::Cache::Class{ $id } = $classname;
		return $classname;
	    }
	}

	if( $node->id == $C_literal->id )
	{
	    # Should be a value literal
	    $classname = "Rit::Base::Resource";
	}
	else
	{
	    my $coltype = $node->coltype;

	    if( $coltype eq 'valtext' )
	    {
		$classname = "Rit::Base::Literal::String";
	    }
	    elsif( $coltype eq 'valdate' )
	    {
		$classname = "Rit::Base::Literal::Time";
	    }
	    elsif( $coltype eq "valfloat" )
	    {
		$classname = "Rit::Base::Literal::String";
	    }
	    else
	    {
		confess "Coltype $coltype not supported";
	    }
	}

	$Rit::Base::Cache::Class{ $id } = $classname;
    }

    return $classname;
}


#######################################################################
#######################################################################
#######################################################################

=head2 coltype_by_valtype_id

Rit::Base::Literal::Class->coltype_by_valtype_id( $id )

=cut

sub coltype_by_valtype_id
{
    return $COLTYPE_valtype2name{ $_[1] }
      or confess "coltype not found for valtype id $_[1]";
}


#######################################################################

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
