package Rit::Base::AJAX;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Rit::Base::AJAX

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

    my $R = Rit::Base->Resource;
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

  Rit::Base::AJAX->new_form_id()

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
                new PagePart('$divid', '$update_url', '$params'.evalJSON());
            //--></script>";
}


1;
