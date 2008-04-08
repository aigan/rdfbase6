# $Id$
package Rit::Base::Literal::Bool;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::Bool

=cut

use strict;
use Carp;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Widget qw( checkbox label_from_params hidden );

use Rit::Base::Utils qw( parse_propargs );

use base qw( Rit::Base::Literal::String );

=head1 DESCRIPTION

Inherits from L<Rit::Base::Literal::String>

=cut

#######################################################################

=head2 wuirc

Display checkbox for updating...

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = Rit::Base::Pred->get_by_label($predname);
    }

    $args->{'id'} ||= "arc_singular__pred_${predname}__subj_". $subj->id ."__row_".$req->{'rb_wu_row'};

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($predname, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= 'X';
	}
    }
    elsif( $subj->count($predname) )
    {
	my $arclist = $subj->arc_list($predname, undef, $args);


	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= hidden('check_arc_'. $arc->id, $arc->value->plain);
	    $out .= checkbox($args->{'id'}, 1, $arc->value->plain) .
	      $arc->edit_link_html;

	}
    }
    else
    {
	$out .= checkbox($args->{'id'}, 1, $args->{'default_value'} || 0);
    }

    return $out;
}



#######################################################################

=head2 as_html

=cut

sub as_html
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = Rit::Base::Pred->get_by_label($predname);
    }

    my $arclist = $subj->arc_list($predname, undef, $args);

    while( my $arc = $arclist->get_next_nos )
    {
	$out .= ( $arc->value->desig ? '<span style="color: green">V</span>' :
		  '<span style="color: red">X</span>' );
    }

    return $out;
}

1;
