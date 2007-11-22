# $Id$
package Rit::Base::AJAX;


=head1 NAME

Rit::Base::AJAX

=cut

=head1 DESCRIPTION

Tie it all together, make your pages into real applications!

=cut

use strict;

use JSON;

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
		 %{jsonToObj($args->{'params'})},
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



1;
