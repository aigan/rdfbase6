#  $Id$  -*-cperl-*-
package Rit::Base::Widget;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Widget class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Widget

=cut

use strict;
use Carp qw( confess cluck carp );
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use base qw( Exporter );
BEGIN
{
    @Rit::Base::Widget::EXPORT_OK

      = qw( wub aloc );

}


use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::L10N qw( loc );
use Para::Frame::Widget qw( input textarea hidden radio jump calendar
filefield input_image label_from_params );


use Rit::Base;
use Rit::Base::Arc;
use Rit::Base::Utils qw( is_undef parse_propargs query_desig aais );
#use Rit::Base::Constants qw( );

=head1 DESCRIPTION


REPLACED prop_fields.tt

 * updated      => Arc:: info_updated_html
 * edit_arc     => Arc:: edit_link_html
 * prop         => wub
 * prop_area    => wub
 * prop_image   => wub_image
 * input_image  => PF:: input_image
 * prop_date    => wub_date

 * prop_concart --------------
 * prop_tree    --------------
 * prop_tree_wh --------------


REPLACED rg_rg_components.tt

 * aloc         => aloc


=cut

#######################################################################

=head2 wub_select_tree

Display a select for a resource; a new select for its rev_scof and so
on until you've chosen one that has no scofs.

To be used for preds with range_scof.

=cut

sub wub_select_tree
{
    my( $subj, $pred_name, $type, $args ) = @_;

    ### Given args MUST have been initialized and localizes!

    my $out = "";
    my $R = Rit::Base->Resource;

    my $rev = $args->{'is_rev'} || '';
    my $arc_type = $args->{'arc_id'} || '';
    my $arc_id = $args->{'arc_id'} ||
      ( $arc_type eq 'singular' ? 'singular' : '' );
    my $arc;

    unless( UNIVERSAL::isa $type, 'Rit::Base::Node' )
    {
	confess "type missing: ".datadump($type,2);
    }

     $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    if( $args->{'disabled'} eq 'disabled' )
    {
	my $arclist = $subj->arc_list($pred_name, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
	return $out;
    }

    $out .= '<select name="parameter_in_value"><option rel="nop-'.
      $type->id .'"/>';

    my $subtypes = $type->revlist('scof', undef, aais($args,'direct'))->
      sorted(['name_short', 'desig', 'label']);

    while( my $subtype = $subtypes->get_next_nos )
    {
	$out .= '<option rel="'. $subtype->id .'"';

	$out .= ' value="arc_'. $arc_id .'__subj_'. $subj->id .'__'. $rev
	  .'pred_'. $pred_name .'='. $subtype->id .'"'
	    unless( $subtype->rev_scof );

	if( $subj->has_value({ $pred_name => $subtype }) or
	    $subj->has_value({ $pred_name => { scof => $subtype } }))
	{
	    $out .= ' selected="selected"';
	    $arc = $subj->arc( $pred_name, $subtype );
	}

	$out .= '>'. ( $subtype->name_short->loc || $subtype->desig || $subtype->label) .'</option>';
    }
    $out .= '</select>';

    $out .= $arc->edit_link_html
      if( $arc );

    $out .= '<div rel="nop-'. $type->id .'" style="display: none"></div>'; # usableforms quirk...

    $subtypes->reset;
    while( my $subtype = $subtypes->get_next_nos )
    {
	$out .= '<div rel="'. $subtype->id .'" style="display: inline">';

	$out .= wub_select_tree( $subj, $pred_name, $subtype, $args )
	  if( $subtype->has_revpred( 'scof' ) );

	$out .= '</div>';
    }

    # TODO: Recurse for all subtypes, make rel-divs etc...

    return $out;
}


#######################################################################

=head2 wub_select

Display a select of everything that is -> $type

=cut

sub wub_select
{
    my( $subj, $pred_name, $type, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;

    unless( UNIVERSAL::isa $type, 'Rit::Base::Node' )
    {
	confess "type missing: ".datadump($type,2);
    }

    my $rev = $args->{'is_rev'} || '';
    my $header = $args->{'header'};
    my $singular = (($args->{'arc_type'}||'') eq 'singular') ? 1 : undef;
    my $arc_id = $args->{'arc_id'} ||
      $singular ? 'singular' : '';
    my $arc = $args->{'arc_id'} ? get($args->{'arc_id'}) : undef;
    my $if = ( $args->{'if'} ? '__if_'. $args->{'if'} : '' );

    $arc ||= $subj->arc( $pred_name )
      if( $singular );

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($pred_name, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
	return $out;
    }

    debug "Building select widget for ".$subj->desig." $pred_name";

    $out .= '<select name="arc_'. $arc_id .'__subj_'. $subj->id .'__'. $rev
      .'pred_'. $pred_name . $if .'">';

    my $default_value = $subj->prop( $pred_name )->id ||
      $args->{'default_value'} || '';
    $out .= '<option value="'. $default_value .'">'. $header .'</option>'
      if( $header );

    my $is_pred = ( $args->{'range_scof'} ? 'scof' : 'is' );
    my $items = $type->revlist($is_pred, undef, $args)->
      sorted(['name_short', 'desig', 'label']);

    $req->may_yield;
    die "cancelled" if $req->cancelled;

    confess( "Trying to make a select of ". $items->size .".  That's not wise." )
      if( $items->size > 500 );

    while( my $item = $items->get_next_nos )
    {
	unless( $items->count % 100 )
	{
	    debug sprintf "Wrote item %4d (%s)",
	      $items->count, $item->desig;
	    $req->may_yield;
	    die "cancelled" if $req->cancelled;
	}

	$out .= '<option value="'. $item->id .'"';

	$out .= ' selected="selected"'
	  if( $default_value eq $item->id or
	      $subj->prop( $pred_name, $item ) );

	$out .= '>'. ( $item->name_short->loc || $item->desig ) .'</option>';
    }
    $out .= '</select>';
    $out .= $arc->edit_link_html
      if( $arc );

    return $out;
}


#######################################################################
#
#=head2 wub_tree
#
#Create a ul of elements that are scof to n
#
#Creates a sub-ul for elements with their own scof's
#
#=cut
#
#sub wub_tree
#{
#    my( $pred, $args_in ) = @_;
#    my( $args ) = parse_propargs($args_in);
#
#    my $out = "";
#    my $R = Rit::Base->Resource;
#    my $q = $Para::Frame::REQ->q;
#
#    my $subj = $args->{'subj'} or confess "subj missing";
#
#    return $out;
#}
#
#
#######################################################################

=head2 aloc

Administrate localization

TODO: Move template to ritbase

=cut

sub aloc
{
    my $text = shift;
    my $out = "";

    if( $Para::Frame::REQ->session->admin_mode )
    {
	my $home = $Para::Frame::REQ->site->home_url_path;
	$out .=
	  (
	   jump("Edit", "$home/admin/translation/update.tt",
		{
		 run => 'mark',
		 c => $text,
		}) .
	   " "
	  );
    }

    return $out . loc($text, @_);
}


#######################################################################

=head2 reset_wu_row

=cut

sub reset_wu_row
{
    debug "Resetting wu row";
    $Para::Frame::REQ->{'rb_wu_row'} = 1;
    return "";
}


#######################################################################

=head2 next_wu_row

=cut

sub next_wu_row
{
    $Para::Frame::REQ->{'rb_wu_row'} ++;
    return "";
}


#######################################################################

=head2 wu_row

=cut

sub wu_row
{
    return $Para::Frame::REQ->{'rb_wu_row'};
}


#######################################################################

sub on_configure
{
    my( $class ) = @_;

    my $params =
    {
#     'wub'               => \&wub,
#     'wub_date'          => \&wub_date,
#     'wub_image'         => \&wub_image,

     'aloc'               => \&aloc,
     'reset_wu_row'       => \&reset_wu_row,
     'next_wu_row'        => \&next_wu_row,
     'wu_row'             => \&wu_row,
    };

    Para::Frame->add_global_tt_params( $params );



#    # Define TT filters
#    #
#    Para::Frame::Burner->get_by_type('html')->add_filters({
#	'pricify' => \&pricify,
#    });


}

#######################################################################

sub on_reload
{
    # This will bind the newly compiled code in the params hash,
    # replacing the old code

    $_[0]->on_configure;
}

#######################################################################

1;
