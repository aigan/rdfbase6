# $Id$
package Rit::Base::AJAX;
#=====================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::AJAX

=cut

=head1 DESCRIPTION

Tie it all together, make your pages into real applications!

=cut

use strict;

use JSON; # to_json from_json

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw datadump
			   package_to_module );
use Para::Frame::L10N qw( loc );

our $ajax_formcount = 0;


#######################################################################

sub new
{
    my( $class, $args ) = @_;
    my $self = bless {}, $class;

    return $self;
}


#######################################################################

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

    debug "Got args: ". datadump($args);

    my $R = Rit::Base->Resource;
    my $pred_name = $args->{'pred_name'}
      or throw('incomplete', "Didn't get pred_name");

    my $subj = $R->get($args->{'subj'});

    debug "Subj: ". $subj;

    my $out =  $subj->wu($pred_name, {
				      %$args,
				      ajax => 1,
				      from_ajax => 1,
				     });
    #$out .= '<input type="button" onclick="pps[\'has_visitor\'].update()" value="o" />';

    return $out;
}


#######################################################################

=head2 pagepart_reload_button

=cut

sub pagepart_reload_button
{
    my( $ajax, $divid )
}


#######################################################################

=head2 new_form_id

  Rit::Base::AJAX->new_form_id()

Gives you a unique id to use for tying html/javascript/rb together.

=cut

sub new_form_id
{
    return 'ajax_formcount_'. $ajax_formcount++;
}


#######################################################################

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
