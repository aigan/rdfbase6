package RDF::Base::Literal::Class;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::Class

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Resource );

use Carp qw( cluck confess longmess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug package_to_module );

use RDF::Base::Constants qw( $C_literal );
use RDF::Base::Resource;
use RDF::Base::Utils qw( is_undef parse_propargs );

our %COLTYPE_num2name =
  (
   1 => 'obj',
   2 => 'valfloat',
   3 => 'valbin',
   4 => 'valdate',
   5 => 'valtext',
  );

our %COLTYPE_name2num;

our %COLTYPE_valtype2name;      # For bootstrapping

our $ID;                       # Node id (used in RDF::Base::Resource)


=head1 DESCRIPTION

Inherits from L<RDF::Base::Resource>

=cut


##############################################################################

=head2 on_startup

=cut

sub on_startup
{
    my( $class ) = @_;

    debug "Initiating valtypes";

    my $dbh = $RDF::dbix->dbh;
    my $sth_label = $dbh->prepare("select node from node where label=?") or die;
    my $sth_child = $dbh->prepare("select subj from arc where pred=2 and obj=?") or die;
    foreach my $colname (qw(valdate valfloat valtext valbin))
    {
        $sth_label->execute($colname) or die "could not get constant $colname";
        my( $colid ) = $sth_label->fetchrow_array or confess "could not get constant $colname";
        $sth_label->finish;

#	debug "Caching colname $colname";
        $sth_child->execute($colid) or die;
        while (my( $nid ) = $sth_child->fetchrow_array)
        {
            $COLTYPE_valtype2name{$nid} = $colname;
#	    debug "Valtype $nid = $colname";
        }
        $sth_child->finish;

        $COLTYPE_valtype2name{$colid} = $colname;
    }
    $COLTYPE_valtype2name{5} = 'obj';

    %COLTYPE_name2num = reverse %COLTYPE_num2name;


#    debug "Initiating literal_class";

    my $sth = $RDF::dbix->dbh->
      prepare("select node from node where label=?");
    $sth->execute( 'literal_class' );
    $ID = $sth->fetchrow_array; # Store in GLOBAL id
    $sth->finish;

    unless( $ID )
    {
        die "Failed to initiate literal_class constant";


        #################### CREATION
#	my( $args, $arclim, $res ) = parse_propargs('auto');
#	my $req = Para::Frame::Request->new_bgrequest();
#	$req->user->set_default_propargs({activate_new_arcs => 1 });
#
#	my $lc = RDF::Base::Resource->get('new');
#	$id = $lc->id;
#	$lc->set_label('literal_class');
#	RDF::Base::Resource->commit;
    }


    $RDF::Base::Constants::Label{'literal_class'} =
      $RDF::Base::Cache::Resource{ $ID } ||=
        RDF::Base::Resource->new($ID)->init();
}


##############################################################################

=head2 set_valtype2name

=cut

sub set_valtype2name
{
    my( $node ) = @_;

    my $scofs = $node->list('scof');
    my $found = 0;
    while ( my $parent = $scofs->get_next_nos )
    {
        my $label = $parent->label;
        next unless $label;

        if ( $COLTYPE_name2num{$label} ) #not expecting 6
        {
            $node->{'lit_coltype'} =
              $COLTYPE_valtype2name{ $node->id } = $label;
            if ( debug )
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
        if ( my $label = $node->label )
        {
            if ( $COLTYPE_name2num{$label} )
            {
                $node->{'lit_coltype'} =
                  $COLTYPE_valtype2name{ $node->id } = $label;
                if ( debug )
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
        my $nid = $node->id;
        if ( $COLTYPE_valtype2name{ $nid } )
        {
            debug sprintf "Removing valtype %d -> %s in coltype cache",
              $node->id, $COLTYPE_valtype2name{ $nid };
            delete $COLTYPE_valtype2name{ $nid };
        }
        delete $node->{'lit_coltype'};
    }
}


##############################################################################

=head2 on_bless

=cut

sub on_bless
{
    my( $node, $class_old, $args_in ) = @_;
    $node->set_valtype2name();
}


##############################################################################

=head2 on_unbless

=cut

sub on_unbless
{
    my( $node, $class_new, $args_in ) = @_;
    $node->set_valtype2name();
}


##############################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    my( $node, $arc, $pred_name, $args_in ) = @_;

    if ( $pred_name eq 'scof' )
    {
        $node->set_valtype2name();
    }
}


##############################################################################

=head2 on_arc_del

=cut

sub on_arc_del
{
    my( $node, $arc, $pred_name, $args_in ) = @_;

    if ( $pred_name eq 'scof' )
    {
        $node->set_valtype2name();
    }
}


##############################################################################

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


##############################################################################

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
    my $classname = $RDF::Base::Cache::Class{ $id };
    unless( $classname )
    {
#	debug "Getting instance class for $id";

        if ( my $class = $node->first_prop('class_handled_by_perl_module') )
        {
            eval
            {
                $classname = $class->first_prop('code')->plain
                  or confess "No classname found for class $class->{id}";
                require(package_to_module($classname));
            };
            if ( $@ )
            {
                cluck $@;
            }
            else
            {
                $RDF::Base::Cache::Class{ $id } = $classname;
                return $classname;
            }
        }

        if ( $id == $RDF::Base::Literal::ID )
        {
            # Should be a value literal
            $classname = "RDF::Base::Resource";
        }
        else
        {
            my $coltype = $node->coltype;

            if ( $coltype eq 'valtext' )
            {
                $classname = "RDF::Base::Literal::String";
            }
            elsif ( $coltype eq 'valdate' )
            {
                $classname = "RDF::Base::Literal::Time";
            }
            elsif ( $coltype eq "valfloat" )
            {
                $classname = "RDF::Base::Literal::String";
            }
            elsif ( $coltype eq "valbin" )
            {
                $classname = "RDF::Base::Literal::String";
            }
            else
            {
                confess "Coltype $coltype not supported";
            }
        }

        $RDF::Base::Cache::Class{ $id } = $classname;
    }

    return $classname;
}


##############################################################################
##############################################################################
##############################################################################

=head2 coltype_by_valtype_id

RDF::Base::Literal::Class->coltype_by_valtype_id( $id )

Dies if this is not a registred literal valtype

Returns: a coltype as a string

Example: valtext

=cut

sub coltype_by_valtype_id
{
    debug "coltype_by_valtype_id for $_[1] is $COLTYPE_valtype2name{ $_[1] }"; # DEBUG
    return( $COLTYPE_valtype2name{ $_[1] }
            or confess "coltype not found for valtype id $_[1]" );
}


##############################################################################

=head2 coltype_by_valtype_id_or_obj

RDF::Base::Literal::Class->coltype_by_valtype_id( $id )

Defaults to 'obj' for unregistred valtypes

Returns: a coltype as a string

Example: obj

=cut

sub coltype_by_valtype_id_or_obj
{
    confess unless defined $_[1];
    return( $COLTYPE_valtype2name{ $_[1] } || 'obj' );
}


##############################################################################

=head2 coltype_by_coltype_id

RDF::Base::Literal::Class->coltype_by_coltype_id( $name )

=cut

sub coltype_by_coltype_id
{
    confess "wrong input: @_" unless $_[1];
    return $COLTYPE_num2name{ $_[1] };
}


######################################################################

=head2 coltype_id_by_coltype

RDF::Base::Literal::Class->coltype_id_by_coltype( $id )

=cut

sub coltype_id_by_coltype
{
    return $COLTYPE_name2num{ $_[1] };
}


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Resource>,
L<RDF::Base::Constants>,

=cut
