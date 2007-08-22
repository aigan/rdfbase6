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

      = qw( wub wub_textarea aloc );

}


use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw );
use Para::Frame::Widget qw( input textarea hidden radio jump );
use Para::Frame::L10N qw( loc );


use Rit::Base;
use Rit::Base::Arc;
use Rit::Base::Utils qw( is_undef parse_propargs query_desig );
#use Rit::Base::Constants qw( );

our $IDCOUNTER = 0;

=head1 DESCRIPTION

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

    if( my $context = $args->{'context'} )
    {
	if( my $node = $context->stash->get('node') )
	{
	    $args->{'subj'} = $node;
	}
    }

    no strict 'refs';
    my $out = "";
    my $R = Rit::Base->Resource;

    my $size = $args->{'size'} || 30;
    my $smallestsize = $size - 10;
    if( $smallestsize < 3 )
    {
	$smallestsize = 3;
    }

    my $subj = $args->{'subj'};
    my $inputtype = $args->{'inputtype'} || 'input';

    my $newsubj = $args->{'newsubj'};
    my $rows = $args->{'row'};
    my $tdlabel = $args->{'tdlabel'};

    if( $newsubj )
    {
	$out .=
	  &{$inputtype}("newsubj_${newsubj}__pred_${pred}",
			"",
			{
			 size => $size,
			 rows => $rows,
			 tdlabel => $tdlabel,
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
			     tdlabel => $tdlabel,
			    });
	    $out .= "<br/>";
	}
	elsif( $subj->list($pred,undef,['active','submitted'])->is_true )
	{
	    debug "Update widget for ".$subj->sysdesig; ### DEBUG

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
		debug "Arc $arc_id";

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
		    debug "  singular";

		    if( scalar(keys %$arcversions) > 1 )
		    {
			$out .= '<li>';
		    }

		    if( $arc->obj->is_value_node )
		    {
			$arc = $arc->obj->first_arc('value');
		    }

		    my $arc_pred_name = $arc->pred->name;
		    my $arc_subj_id = $arc->subj->id;

		    $out .= &{$inputtype}("arc_${arc_id}__pred_${arc_pred_name}__row_${IDCOUNTER}__subj_${arc_subj_id}",
					  $arc->value,
					  {
					   size => $size,
					   rows => $rows,
					  });

		    $out .= $arc->edit_link_html;

		    if( scalar(keys %$arcversions) > 1 )
		    {
			$out .= '</li>';
		    }
		}
	    }

	    debug "after";

	    if( scalar(keys %$arcversions) > 1 )
	    {
		$out .= '</ul>';
	    }
	}
	else # no arc
	{
	    debug "no arc";

	    my $subj_id = $subj->id;
	    $out .= &{$inputtype}("arc___pred_${pred}__subj_${subj_id}__row_${IDCOUNTER}",
				  '',
				  {
				   size => $size,
				   rows => $rows,,
				   tdlabel => $tdlabel,
				  });
	}
    }

    return $out;
}


#######################################################################

=head2 wub_textarea

Display field for updating a textblock property of a node

=cut

sub wub_textarea
{
    my( $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    $args->{'rows'} ||= 0;
    $args->{'cols'} ||= 57;
    $args->{'size'} = $args->{'cols'};
    $args->{'inputtype'} = 'textarea';

    return &wub($pred, $args);
}


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
#
#=head2 next_row
#
#=cut
#
#sub next_row
#{
#    $IDCOUNTER++;
#}
#
#
#######################################################################

sub on_configure
{
    my( $class ) = @_;

    my $params =
    {
#     'wub'               => \&wub,
#     'wub_textarea'      => \&wub_area,

     'aloc'               => \&aloc,
#     'next_row'           => \&next_row,
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
