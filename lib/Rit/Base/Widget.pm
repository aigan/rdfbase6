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
use Para::Frame::Utils qw( debug throw );
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

=head2 wub

Display field for updating a string property of a node

var node must be defined

prop pred is required

document newsubj!

the query param "arc___pred_$pred__subj_$nid" can be used for default new value

the query param "arc___pred_$pred" can be used for default new value

=cut

sub wub
{
    my( $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    Para::Frame::Logging->this_level(5);

    no strict 'refs';
    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;
    my $root_access = $req->user->has_root_access; # BOOL

    unless( $req->user->has_root_access )
    { ### FIXME: Not ready to use for non-admins...
	$args =
	  parse_propargs({
			  %$args,
			  unique_arcs_prio => ['submitted','active'],
			  arclim => [['submitted','created_by_me'],'active'],
			 });
    }



    my $size = $args->{'size'} || 30;
    my $smallestsize = $size - 10;
    if( $smallestsize < 3 )
    {
	$smallestsize = 3;
    }

    my $subj = $args->{'subj'} or confess "subj missing";
    my $inputtype = $args->{'inputtype'} || 'input';

    debug 2, "wub $inputtype $pred for ".$subj->sysdesig;


    my $newsubj = $args->{'newsubj'};
    my $rows = $args->{'rows'};
    my $maxw = $args->{'maxw'};
    my $maxh = $args->{'maxh'};

    $args->{'id'} ||= "arc___pred_${pred}__subj_". $subj->id ."__row_".$req->{'rb_wu_row'};

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });


    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($pred, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
    }
    elsif( not $subj )
    {
	$out .=
	  &{$inputtype}("arc___pred_${pred}__row_".$req->{'rb_wu_row'},	'',
			{
			 size => $size,
			 rows => $rows,
			 image_url => $args->{'image_url'}
			});
	$out .= "<br/>";
    }
    elsif( $subj->list($pred,undef,['active','submitted'])->is_true )
    {
	my $subj_id = $subj->id;

	my $arcversions =  $subj->arcversions($pred);
	if( scalar(keys %$arcversions) > 1 )
	{
	    $out .= '<ul style="list-style-type: none" class="nopad">';
	}

	foreach my $arc_id (keys %$arcversions)
	{
	    my $arc = Rit::Base::Arc->get($arc_id);
	    if( my $lang = $arc->obj->is_of_language(undef,'auto') )
	    {
		$out .= "(".$lang->desig."): ";
	    }

	    if( (@{$arcversions->{$arc_id}} > 1) or
		$arcversions->{$arc_id}[0]->submitted )
	    {
		debug "  multiple";

		$out .=
		  (
		   "<li><table class=\"wide suggestion nopad\">".
		   "<tr><th colspan=\"2\">".
		   &aloc("Choose one").
		   "</th></tr>"
		  );

		foreach my $version (@{$arcversions->{$arc_id}})
		{
		    debug "  version $version";
		    $out .=
		      (
		       "<tr><td>".
		       &hidden("version_${arc_id}", $version->id).
		       &radio("arc_${arc_id}__select_version",
			      $version->id,
			      0,
			      {
			       id => $version->id,
			      }).
		       "</td>"
		      );

		    $out .= "<td style=\"border-bottom: 1px solid black\">";

		    if( $version->is_removal )
		    {
			$out .= "<span style=\"font-weight: bold\">REMOVAL</span>";
		    }
		    else
		    {
			$out .= &{$inputtype}("undef",
					      $version->value,
					      {
					       disabled => "disabled",
					       class => "suggestion_field",
					       size => $smallestsize,
					       rows => $rows,
					       version => $version,
					       image_url => $args->{'image_url'}
					      });
		    }

		    $out .= $version->edit_link_html;
		    $out .= "</td></tr>";
		}

		$out .=
		  (
		   "<tr><td>".
		   &radio("arc_${arc_id}__select_version",
			  'deactivate',
			  0,
			  {
			   id => "arc_${arc_id}__activate_version--undef",
			  }).
		   "</td><td>".
		   "<label for=\"arc_${arc_id}__activate_version--undef\">".
		   loc("Deactivate group").
		   "</label>".
		   "</td></tr>".
		   "</table></li>"
		  );
	    }
	    else
	    {
		$out .= '<li>'
		  if( scalar(keys %$arcversions) > 1 );

		if( $arc->obj->is_value_node )
		{
		    $arc = $arc->obj->first_arc('value');
		    $arc_id = $arc->id;
		}

		my $arc_pred_name = $arc->pred->name;
		my $arc_subj_id = $arc->subj->id;

		$out .= &{$inputtype}("arc_${arc_id}__pred_${arc_pred_name}__row_".$req->{'rb_wu_row'}."__subj_${arc_subj_id}",
				      $arc->value,
				      {
				       arc => $arc_id,
				       size => $size,
				       rows => $rows,
				       image_url => $args->{'image_url'}
				      });

		$out .= $arc->edit_link_html;

		$out .= '</li>'
		  if( scalar(keys %$arcversions) > 1 );
	    }
	}

	$out .= '</ul>'
	  if( scalar(keys %$arcversions) > 1 );
    }
    else # no arc
    {
	my $default = $args->{'default_value'} || '';
	my $subj_id = $subj->id;
	$out .= &{$inputtype}("arc___pred_${pred}__subj_${subj_id}__row_".$req->{'rb_wu_row'},
			      $default,
			      {
			       size => $size,
			       rows => $rows,
			       maxw => $maxw,
			       maxh => $maxh,
			       image_url => $args->{'image_url'}
			      });
    }

    return $out;
}


#######################################################################

=head2 wub_date

Display field for updating a date property of a node

var node must be defined

prop pred is required

the query param "arc___pred_$pred__subj_$subjvarname" can be used for
default new value

=cut

sub wub_date
{
    my( $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;
    my $q = $Para::Frame::REQ->q;

    my $size = $args->{'size'} || 18;
    my $subj = $args->{'subj'} or confess "subj missing";

    my $newsubj = $args->{'newsubj'};
    my $tdlabel = $args->{'tdlabel'};
    my $label = $args->{'label'};
    my $arc = $args->{'arc'};

    my $subj_id = $subj->id;

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });


    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($pred, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
    }
    elsif( $subj->empty )
    {
	my $arc_id = $arc ? $arc->id : '';
	my $fieldname = "arc_${arc_id}__pred_${pred}";
	$out .= &calendar($fieldname, '',
			  {
			   id => $fieldname,
			   size => $size,
			  });
	$out .= $arc->edit_link_html
	  if( $arc );
    }
    elsif( $subj->list($pred)->size > 1 )
    {
	$out .= "<ul>";

	foreach my $arc ( $subj->arc_list($pred) )
	{
	    if( $arc->realy_objtype )
	    {
		$out .= "<li><em>This is not a date!!!</em></li>";
		$out .= $arc->edit_link_html;
	    }
	    else
	    {
		$out .= "<li>";

		my $arc_id = $arc->id || '';
		my $fieldname = "arc_${arc_id}__pred_${pred}__subj_${$subj_id}";
		my $value_new = $q->param("arc___pred_${pred}__subj_${$subj_id}") || $arc->value;
		$out .= &calendar($fieldname, $value_new,
				  {
				   id => $fieldname,
				   size => $size,
				  });
		$out .= $arc->edit_link_html
		  if( $arc );
		$out .= "</li>";
	    }
	}

	$out .= "</ul>";
    }
    else
    {
	my $arc = $subj->first_arc($pred);
	if( $arc->realy_objtype )
	{
	    $out .= "<em>This is not a date!!!</em>";
	}
	else
	{
	    my $arc_id = $arc->id || '';
	    my $fieldname = "arc_${arc_id}__pred_${pred}__subj_${subj_id}";
	    my $value_new = $q->param("arc___pred_${pred}__subj_${subj_id}") || $subj->prop($pred);
	    $out .= &calendar($fieldname, $value_new,
			      {
			       id => $fieldname,
			       size => $size,
			      });
	    $out .= $arc->edit_link_html
	      if( $arc );
	}
    }

    return $out;
}


#######################################################################

=head2 wub_image

Display field for updating images

=cut

sub wub_image
{
    my( $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;

    my $subj = $args->{'subj'} or confess "subj missing";
    my $multiple = $args->{'multiple'};

    my $maxw = $args->{'maxw'} ||= 400;
    my $maxh = $args->{'maxh'} ||= 300;
    $args->{'inputtype'} = 'input_image';
    $args->{'image_url'} = $Para::Frame::CFG->{'guides'}{'logos_published'} ||
      $Para::Frame::CFG->{'images_uploaded_url'} ||
	'/images';


    $out .= wub($pred, $args);

    if( $multiple )
    {
	if( $subj->list($pred, undef, ['active','submitted']) )
	{
	    my $subj_id = $subj->id;
	    $out .= filefield("arc___file_image__pred_${pred}__subj_${subj_id}__maxw_${maxw}__maxh_${maxh}");
	}
    }

    return $out;
}


#######################################################################

=head2 wub_select_tree

Display a select for a resource; a new select for its rev_scof and so
on until you've chosen one that has no scofs.

To be used for preds with range_scof.

=cut

sub wub_select_tree
{
    my( $pred_name, $type, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;

    my $rev = $args->{'is_rev'} || '';
    my $subj = $args->{'subj'} or confess "subj missing";
    my $arc_id = $args->{'arc_id'} ||
      ( $args->{'arc_type'} eq 'singular' ? 'singular' : '' );
    my $arc;

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

	$out .= wub_select_tree( $pred_name, $subtype, $args )
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
    my( $pred_name, $type, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;

    my $rev = $args->{'is_rev'} || '';
    my $header = $args->{'header'};
    my $subj = $args->{'subj'} or confess "subj missing";
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

    if( $args->{'disabled'} eq 'disabled' )
    {
	my $arclist = $subj->arc_list($pred_name, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
	return $out;
    }

    $out .= '<select name="arc_'. $arc_id .'__subj_'. $subj->id .'__'. $rev
      .'pred_'. $pred_name . $if .'">';

    my $default_value = $subj->prop( $pred_name )->id ||
      $args->{'default_value'} || '';
    $out .= '<option value="'. $default_value .'">'. $header .'</option>'
      if( $header );

    my $is_pred = ( $args->{'range_is_scof'} ? 'scof' : 'is' );
    my $items = $type->revlist($is_pred, undef, aais($args,'direct'))->
      sorted(['name_short', 'desig', 'label']);

    confess( "Trying to make a select of ". $items->size .".  That's not wise." )
      if( $items->size > 500 );

    while( my $item = $items->get_next_nos )
    {
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
