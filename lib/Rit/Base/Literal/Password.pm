#  $Id$  -*-cperl-*-
package Rit::Base::Literal::Password;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::Password

=cut

use strict;
use Carp qw( cluck confess longmess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug trim );
use Para::Frame::Widget qw( password );
use Rit::Base::Utils qw( is_undef );

use base qw( Rit::Base::Literal::String );
# Parent overloads some operators!


=head1 DESCRIPTION

Handling crypted passwords

=cut


#######################################################################

=head2 as_html

  $subj->as_html

=cut

sub as_html
{
    return "* * * * *";
}


#######################################################################

=head2 desig

  $subj->desig

=cut

sub desig
{
    return "* * * * *";
}


#######################################################################

=head2 sysdesig

  $subj->sysdesig

=cut

sub sysdesig
{
    return "password hidden";
}


#######################################################################

=head2 wuirc

Display field for updating password

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(5);

    no strict 'refs'; # For &{$inputtype} below
    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;
    my $root_access = $req->user->has_root_access; # BOOL


    my $size = $args->{'size'} || 15;
    my $smallestsize = $size - 10;
    if( $smallestsize < 3 )
    {
	$smallestsize = 8;
    }

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;

	debug 2, "String wuirc for $predname";
	debug 2, "$predname class is ". $pred->range->instance_class;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = Rit::Base::Pred->get_by_label($predname);
    }


    debug 2, "wub password $predname for ".$subj->sysdesig;

    my $newsubj = $args->{'newsubj'};

    $args->{'id'} ||= build_field_key({
				       pred => $predname,
				       subj => $subj,
				      });

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    my $proplim = $args->{'proplim'} || undef;
    my $arclim = $args->{'arclim'} || ['active','submitted'];

#    debug "Using proplim ".query_desig($proplim); # DEBUG


    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($predname, $proplim, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
    }
    elsif( $subj->list($predname,$proplim,$arclim)->is_true )
    {
	my $subj_id = $subj->id;

	my $arcversions =  $subj->arcversions($predname, proplim_to_arclim($proplim));
	my @arcs = map Rit::Base::Arc->get($_), keys %$arcversions;

#	debug "Arcs list: @arcs";
	my $list_weight = 0;

	foreach my $arc ( $subj->arc_list($predname,$proplim,$arclim) )
	{
	    my $arc_id = $arc->id;
#	    debug $arc_id;

	    my $field = build_field_key({arc => $arc});
	    my $fargs =
	    {
	     class => $args->{'class'},
	     size => $size,
	     maxlength => $args->{'maxlength'},
	     id => $args->{'id'},
	     arc => $arc->id,
	    };

	    $out .= password($field, undef, $fargs);
	    $out .= $arc->edit_link_html;
	}
    }
    else # no arc
    {
	my $props =
	{
	 pred => $predname,
	 subj => $subj,
	};

	$out .= password(build_field_key($props),
			 undef,
			 {
			  class => $args->{'class'},
			  size => $size,
			  maxlength => $args->{'maxlength'},
			  id => $args->{'id'},
			 });
    }

    return $out;
}


#######################################################################

1;
