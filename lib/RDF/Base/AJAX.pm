package RDF::Base::AJAX;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::AJAX

=cut

=head1 DESCRIPTION

Tie it all together, make your pages into real applications!

=cut

use 5.010;
use strict;
use warnings;

use JSON; # to_json from_json

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw datadump
			   package_to_module );
use Para::Frame::L10N qw( loc );

our $ajax_formcount = 0;


##############################################################################

sub new
{
    my( $class, $args ) = @_;
    my $self = bless {}, $class;

    return $self;
}


##############################################################################

=head2 wu

  [% ajax->wu({ subj => node.id, pred_name => 'has_visitor', args... }) %]

Get a widget for updating from subj->wu( pred_name, $args )

=cut

sub wu
{
    my( $ajax, $args ) = @_;

    if( $args->{'params'} )
    {
	$args = {
		 %$args,
		 %{from_json($args->{'params'})},
		 params => ''};
    }

#    debug "AJAX wus: ". datadump($args);

    my $R = RDF::Base->Resource;
    my $out;

    my $subj = $R->get($args->{'subj'});
#    debug "Subj: ". $subj;

    if( my $pred_name = $args->{'pred_name'} )
    {
#	debug " -> wu $pred_name";
	$out =  $subj->wu($pred_name,
			  {
			      %$args,
			      ajax => 1,
			      from_ajax => 1,
			  });
    }
    elsif( my $view = $args->{'view'} )
    {
#	debug " -> wn $view";
	$out = $subj->wn({
	    %$args,
	    ajax => 1,
	    from_ajax => 1,
			 });
    }
    else
    {
	throw('incomplete', "Didn't get pred_name");
    }

    return $out;
}


##############################################################################

=head2 pagepart_reload_button

=cut

sub pagepart_reload_button
{
    my( $ajax, $divid )
}


##############################################################################

=head2 new_form_id

  RDF::Base::AJAX->new_form_id()

Gives you a unique id to use for tying html/javascript/rb together.

=cut

sub new_form_id
{
    return 'ajax_formcount_'. $ajax_formcount++;
}


##############################################################################

=head2 register_page_part

  [% ajax.register_page_part( divid, update_url, params ) %]

=cut

sub register_page_part
{
    my( $ajax, $divid, $update_url, $params ) = @_;

    my $home = $Para::Frame::REQ->site->home_url_path;
    $update_url ||= "$home/ajax/";
    $params = to_json( $params || {} );

    return "<script><!--
                new PagePart('$divid', '$update_url', $params);
            //--></script>";
}


##############################################################################

sub form
{
    my( $ajax, $module, $part, $args ) = @_;

    $module = "Rit::Guides::AJAX::Form::$module";
    #$module = 'Rit::Guides::Action::booking_invoice';

    $part ||= 'all';

    debug "Attempting to get form html from $module->$part with args:";
    debug datadump( $args );

    eval
    {
	require(package_to_module($module));
    };
    if( $@ )
    {
	debug $@;
    }
    else
    {
	return $module->$part( $args );
    }

    return "$@";
}


##############################################################################
############################### Widgets ###############################

=head1 Widgets

  AJAX-widgets to use from tt or perl.

=cut

##############################################################################

=head2 switchingDivs

  Rit::Guides::AJAX->switching_divs( $content_1, $content_2 );

  [% ajax->switching_divs('This is a little, click me to see more.',
                          'This is much more! Bla bla bla.... !') %]

Makes two div's, the first shown and the second hidden.  When the
first is clicked, it is changed to the second instead (with a nifty
scriptaculous shrink/grow).

=cut

sub switching_divs
{
    my( $ajax, $div1, $div2 ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $out = "";

    my $fid = $ajax->new_form_id;

    $out .= $q->a({ id      => $fid .'-shown',
		    href    => "javascript:switchDivs('$fid')",
		  }, $div1);
    $out .= $q->div({ id => $fid .'-hid',
		      style => 'display: none',
		    }, $div2);

    return $out;
}


##############################################################################

=head2 action_button

  [% ajax.action_button( label, divid, action, args ) %]

=cut

sub action_button
{
    my( $ajax, $label, $divid, $action, $args ) = @_;

    $args = to_json( $args || {} );
    $args =~ s/"/'/g;

    return qq{<input type="button" class="btn btn-primary" value="$label" ".
      "onclick="RDF.Base.pageparts['$divid'].performAction('$action', $args)">};
}

##############################################################################

1;
