package RDF::Base::Literal::Bool;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::Bool

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( RDF::Base::Literal::String );

use Carp;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );
use Para::Frame::Widget qw( checkbox label_from_params hidden );

use RDF::Base::Utils qw( parse_propargs );


=head1 DESCRIPTION

Inherits from L<RDF::Base::Literal::String>

=cut

##############################################################################

=head2 wuirc

Display checkbox for updating...

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = RDF::Base->Resource;
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
	$pred = RDF::Base::Pred->get_by_label($predname);
    }

    my $key = "arc_singular__pred_${predname}__subj_". $subj->id ."__row_".$req->{'rb_wu_row'};
    $args->{'id'} ||= $key;

#    $out .= label_from_params({
#			       label       => $args->{'label'},
#			       tdlabel     => $args->{'tdlabel'},
#			       separator   => $args->{'separator'},
#			       id          => $args->{'id'},
#			       label_class => $args->{'label_class'},
#			      });

    if( ($args->{'label'}||'') eq '1' )
    {
#        debug "Args label is ".$args->{'label'};
        $args->{'label'} = $pred;
    }

    if( ($args->{'tdlabel'}||'') eq '1' )
    {
#        debug "Args label is ".$args->{'label'};
        $args->{'tdlabel'} = $pred;
    }

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
	    $out .= checkbox($key, 1, $arc->value->plain, $args) .
	      $arc->edit_link_html;

	}
    }
    else
    {
	my $val = $args->{'default_value'} || 0;
	$out .= checkbox($key, 1, $val, $args);
    }

    return $out;
}


##############################################################################

=head2 as_html

  $lit->as_html( \%args )

=cut

sub as_html
{
    my( $lit, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    # Maby use ☑ and ☒
    return( $lit->plain ? '<span style="color: green;font-size:150%;padding:0;margin:0">☑</span>' :
	    '<span style="color: red">☒</span>' );
}


##############################################################################

=head2 some_kind_of_as_html

=cut

sub some_kind_of_as_html
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = RDF::Base->Resource;
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
	$pred = RDF::Base::Pred->get_by_label($predname);
    }

    my $arclist = $subj->arc_list($predname, undef, $args);

    while( my $arc = $arclist->get_next_nos )
    {
	# Maby use ☑ and ☒
	$out .= ( $arc->value->desig ? '<span style="color: green">V</span>' :
		  '<span style="color: red">X</span>' );
    }

    return $out;
}


##############################################################################

1;
