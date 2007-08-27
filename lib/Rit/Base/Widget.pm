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
filefield input_image );


use Rit::Base;
use Rit::Base::Arc;
use Rit::Base::Utils qw( is_undef parse_propargs query_desig );
#use Rit::Base::Constants qw( );

our $IDCOUNTER = 1;

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

    no strict 'refs';
    my $out = "";
    my $R = Rit::Base->Resource;

    my $size = $args->{'size'} || 30;
    my $smallestsize = $size - 10;
    if( $smallestsize < 3 )
    {
	$smallestsize = 3;
    }

    my $subj = $args->{'subj'} or confess "subj missing";
    my $inputtype = $args->{'inputtype'} || 'input';

    debug "wub $inputtype $pred for ".$subj->sysdesig;


    my $newsubj = $args->{'newsubj'};
    my $rows = $args->{'rows'};
    my $tdlabel = $args->{'tdlabel'};
    my $label = $args->{'label'};

    if( $newsubj )
    {
	$out .=
	  &{$inputtype}("newsubj_${newsubj}__pred_${pred}",
			"",
			{
			 size => $size,
			 rows => $rows,
			 tdlabel => $tdlabel, label => $label,
			 image_url => $args->{'image_url'}
			});
    }
    else
    {
	if( not $subj )
	{
	    $out .=
	      &{$inputtype}("arc___pred_${pred}__row_${IDCOUNTER}",
			    '',
			    {
			     size => $size,
			     rows => $rows,
			     tdlabel => $tdlabel, label => $label,
			     image_url => $args->{'image_url'}
			    });
	    $out .= "<br/>";
	}
	elsif( $subj->list($pred,undef,['active','submitted'])->is_true )
	{
	    my $subj_id = $subj->id;
	    if( $tdlabel )
	    {
		my $arc = $subj->arc_list($pred,undef,'auto')->get_first_nos;
		my $arc_id = $arc->id;
		my $tdlabel_html =  CGI->escapeHTML($tdlabel);
		$out .= "<label for=\"arc_${arc_id}__pred_${pred}__row_${IDCOUNTER}__subj_${subj_id}\">${tdlabel_html}</label></td><td>";
	    }

	    my $arcversions =  $subj->arcversions($pred);
	    if( scalar(keys %$arcversions) > 1 )
	    {
		$out .= '<ul style="list-style-type: none" class="nopad">';
	    }

	    foreach my $arc_id (keys %$arcversions)
	    {
#		debug "Arc $arc_id";

		my $arc = Rit::Base::Arc->get($arc_id);
		if( my $lang = $arc->obj->is_of_language(undef,'auto') )
		{
		    $out .= "(".$lang->name->loc.")";
		}

		if( (@{$arcversions->{$arc_id}} > 1) or
		    $arcversions->{$arc_id}[0]->submitted )
		{
		    debug "  multiple";

		    $out .=
		      (
		       ": <li><table class=\"wide suggestion nopad\">".
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

			$out .=
			   "<td style=\"border-bottom: 1px solid black\">";

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

			$out .= $arc->edit_link_html;

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
#		    debug "  singular";

		    if( scalar(keys %$arcversions) > 1 )
		    {
			$out .= '<li>';
		    }

		    if( $arc->obj->is_value_node )
		    {
			$arc = $arc->obj->first_arc('value');
			$arc_id = $arc->id;
		    }

		    my $arc_pred_name = $arc->pred->name;
		    my $arc_subj_id = $arc->subj->id;

		    $out .= &{$inputtype}("arc_${arc_id}__pred_${arc_pred_name}__row_${IDCOUNTER}__subj_${arc_subj_id}",
					  $arc->value,
					  {
					   size => $size,
					   rows => $rows,
					   image_url => $args->{'image_url'}
					  });

		    $out .= $arc->edit_link_html;

		    if( scalar(keys %$arcversions) > 1 )
		    {
			$out .= '</li>';
		    }
		}
	    }

#	    debug "after";

	    if( scalar(keys %$arcversions) > 1 )
	    {
		$out .= '</ul>';
	    }
	}
	else # no arc
	{
#	    debug "no arc";

	    my $subj_id = $subj->id;
	    $out .= &{$inputtype}("arc___pred_${pred}__subj_${subj_id}__row_${IDCOUNTER}",
				  '',
				  {
				   size => $size,
				   rows => $rows,,
				   tdlabel => $tdlabel, label => $label,
				   image_url => $args->{'image_url'}
				  });
	}
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

    if( $newsubj )
    {
	my $fieldname = "newsubj_${newsubj}__pred_${pred}";
	$out .= &calendar($fieldname, "",
			  {
			   id => $fieldname,
			   size => $size,
			   tdlabel => $tdlabel, label => $label
			   });
    }
    else
    {
	if( $subj->empty )
	{
	    my $arc_id = $arc ? $arc->id : '';
	    my $fieldname = "arc_${arc_id}__pred_${pred}";
	    $out .= &calendar($fieldname, '',
			      {
			       id => $fieldname,
			       size => $size,
			       tdlabel => $tdlabel, label => $label
			      });
	    if( $arc )
	    {
		$out .= $arc->edit_link_html;
	    }
	}
	elsif( $subj->list($pred)->size > 1 )
	{
	    if( $tdlabel )
	    {
		$out .= "<label>${tdlabel}</label></td><td>";
	    }

	    $out .= "<ul>";

	    foreach my $arc ( $subj->arc_list($pred) )
	    {
		if( $arc->realy_objtype )
		{
		    $out .= "<li><em>This is not a date!!!</em></li>";
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
				       tdlabel => $tdlabel, label => $label
				      });
		    if( $arc )
		    {
			$out .= $arc->edit_link_html;
		    }

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
				   tdlabel => $tdlabel, label => $label
				  });
		if( $arc )
		{
		    $out .= $arc->edit_link_html;
		}
	    }
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
    my $q = $Para::Frame::REQ->q;

    my $subj = $args->{'subj'} or confess "subj missing";
    my $multiple = $args->{'multiple'};

    my $maxw = $args->{'maxw'} ||= 400;
    my $maxh = $args->{'maxh'} ||= 300;
    $args->{'inputtype'} = 'input_image';
    $args->{'image_url'} = $Para::Frame::CFG->{'images_uploaded_url'} ||
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

=head2 next_wu_row

=cut

sub next_wu_row
{
    $IDCOUNTER++;
    return "";
}


#######################################################################

=head2 wu_row

=cut

sub wu_row
{
    return $IDCOUNTER;
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
