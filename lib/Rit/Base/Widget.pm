package Rit::Base::Widget;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

Rit::Base::Widget

=cut

use 5.010;
use strict;
use warnings;

use Carp qw( confess cluck carp );
use CGI;

use base qw( Exporter );
our @EXPORT_OK = qw( aloc locn locnl sloc locpp alocpp locppg alocppg build_field_key );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug throw datadump );
use Para::Frame::L10N qw( loc );
use Para::Frame::Widget qw( input textarea hidden radio jump calendar
filefield input_image );


use Rit::Base;
use Rit::Base::Arc;
use Rit::Base::Utils qw( is_undef parse_propargs query_desig aais range_pred );
use Rit::Base::L10N;
use Rit::Base::Constants qw( $C_translatable $C_has_translation );

=head1 DESCRIPTION

=cut

##############################################################################

=head2 aloc

Administrate localization

=cut

sub aloc
{
    my $phrase = shift;

    if( $Para::Frame::REQ->session->admin_mode )
    {
        my $id = Rit::Base::L10N::find_translation_node_id($phrase);

        unless( $id )
	{
            my $R = Rit::Base->Resource;
            my $node = $R->create({ translation_label => $phrase,
				    is => $C_translatable,
				  }, { activate_new_arcs => 1 });
            $id = $node->id;
        }

        my $out = "";

        $out .= '<span class="translatable" title="'.
          CGI->escapeHTML(loc($phrase,qw([_1] [_2] [_3] [_4] [_5]))).
            '" id="translate_'. $id .'">' . loc($phrase, @_) . '</span>';

        return $out;
    }
    else
    {
        return loc($phrase, @_);
    }
}


##############################################################################

=head2 locn

localization node

=cut

sub locn
{
    my $phrase = shift;
#    debug "locn $phrase";
    my $node = Rit::Base::L10N::find_translation_node($phrase);
    unless( $node )
    {
#	debug "  creates and returns new translatable node";
	return Rit::Base::Resource->create({
					    translation_label => $phrase,
					    is => $C_translatable,
					   },
					   { activate_new_arcs => 1 });
    }

    return $node;
}


##############################################################################

=head2 locnl

localization node localization text. (Lock'n'Load)

Creates a node if missing and uses it.

=cut

sub locnl
{
    my $phrase = shift;
    my $node = Rit::Base::L10N::find_translation_node($phrase);
    unless( $node )
    {
#	debug "  creates and returns new translatable node";
	$node = Rit::Base::Resource->create({
					     translation_label => $phrase,
					     is => $C_translatable,
					    },
					    { activate_new_arcs => 1 });
    }

    return $node->loc(@_);
}


##############################################################################

sub sloc
{
    my $text = shift;
    my $out = "";

    my $compiled = ($Para::Frame::REQ->site->is_compiled
      and not $Para::Frame::File::COMPILING);

    if( $compiled or $Para::Frame::REQ->session->admin_mode )
    {
	my $home = $Para::Frame::REQ->site->home_url_path;
        my $id = Rit::Base::L10N::find_translation_node_id( $text );

        $out .= "[% IF admin_mode %]" if $compiled;
	$out .=
	  (
	   jump("Edit", "$home/rb/translation/node.tt",
		{
                 id => $id,
                 pred => $C_has_translation->id,
		 tag_attr => {class => "paraframe_edit_link_overlay"},
		 tag_image => "$home/pf/images/edit.gif",
		})
	  );

        $out .= "[% END %]" if $compiled;
    }

    return $out;
}


##############################################################################

=head2 locpp

  locpp($name, @args)

Localization for page-part.

Same as L<Para::Frame::L10N::loc>, but looks up the translation from
the database.

=cut

sub locpp
{
    my( $name ) = shift;

    my $req = $Para::Frame::REQ;

    my $code = $req->page->base;
    if( $name )
    {
	$code = $code.'#'.$name;
    }

    return alocpp_raw($code,1,@_);
}


##############################################################################

=head2 alocpp

  alocpp($name, @args)

Administrate localization for page-part.

Same as L<Para::Frame::L10N::loc>, but looks up the translation from
the database. If in admin mode, prepends a text edit link

=cut

sub alocpp
{
    my( $name ) = shift;

    my $req = $Para::Frame::REQ;

    my $code = $req->page->base;
    if( $name )
    {
	$code = $code.'#'.$name;
    }

    return alocpp_raw($code,0,@_);
}


##############################################################################

=head2 locppg

  locpp($name, @args)

Localization for page-part -- global.

Same as L<Para::Frame::L10N::loc>, but looks up the translation from
the database.

=cut

sub locppg
{
    return alocpp_raw('#'.shift, 1, @_);
}


##############################################################################

=head2 alocppg

  alocpp($name, @args)

Administrate localization for page-part -- global.

Same as L<Para::Frame::L10N::loc>, but looks up the translation from
the database. If in admin mode, prepends a text edit link

=cut

sub alocppg
{
    return alocpp_raw('#'.shift, 0, @_);
}


##############################################################################

sub alocpp_raw
{
    my( $code, $no_admin ) = (shift, shift);

    my $req = $Para::Frame::REQ;
    my $node = Rit::Base::Resource->find({code=>$code})->get_first_nos;
    my $site = $req->site;
    my $home = $site->home_url_path;

    my $out = "";

    if( $site->is_compiled and not $no_admin )
    {
        $out .= "[% IF admin_mode %]";
        if( $node )
	{
	    $out .= jump(locn("Edit"), "$home/rb/translation/html.tt",
			 {
			  id => $node->id,
			  tag_image => "$home/pf/images/edit.gif",
			  tag_attr => {class=>"paraframe_edit_link_overlay"},
			 });
	}
	else
	{
	    $out .= jump(locn("Edit"), "$home/rb/translation/html.tt",
			 {
			  code => $code,
			  tag_image => "$home/pf/images/edit.gif",
			  tag_attr => {class=>"paraframe_edit_link_overlay"},
			 });
	}
        $out .= "[% END %]";
    }
    elsif( $req->session->{'admin_mode'} and not $no_admin )
    {
	if( $node )
	{
	    $out .= jump(locn("Edit"), "$home/rb/translation/html.tt",
			 {
			  id => $node->id,
			  tag_image => "$home/pf/images/edit.gif",
			  tag_attr => {class=>"paraframe_edit_link_overlay"},
			 });
	}
	else
	{
	    $out .= jump(locn("Edit"), "$home/rb/translation/html.tt",
			 {
			  code => $code,
			  tag_image => "$home/pf/images/edit.gif",
			  tag_attr => {class=>"paraframe_edit_link_overlay"},
			 });
	}
    }

    ### TEST: change to list...
    return $out . $node->first_prop('has_html_content')->loc(@_);
#    return $out . $req->{'lang'}->maketext($name, @_);
}


##############################################################################

=head2 reset_wu_row

=cut

sub reset_wu_row
{
#    debug "Resetting wu row";
    $Para::Frame::REQ->{'rb_wu_row'} = 1;
    return "";
}


##############################################################################

=head2 next_wu_row

=cut

sub next_wu_row
{
    $Para::Frame::REQ->{'rb_wu_row'} ++;
    return "";
}


##############################################################################

=head2 wu_row

=cut

sub wu_row
{
    return $Para::Frame::REQ->{'rb_wu_row'};
}


##############################################################################

=head2 build_field_key

  build_field_key( \%props )

=cut

sub build_field_key
{
    my( $props ) = @_;
    unless( ref $props eq 'HASH' )
    {
	confess "Invalid argument: ".datadump($props,1);
    }
    my $arc_id = '';
    if( my $arc_in = delete($props->{'arc'}) )
    {
	my $arc = Rit::Base::Arc->get($arc_in);
	$arc_id = $arc->id;
    }

    my $out = "arc_".$arc_id;

    foreach my $key (sort keys %$props)
    {
	my $val = $props->{$key} || '';
	if( grep{$key eq $_} qw( subj type scof vnode ) )
	{
	    $val = Rit::Base::Resource->get($val)->id;
	}
	elsif( grep{$key eq $_} qw( pred desig ) )
	{
	    $val = Rit::Base::Pred->get($val)->plain;
	}

	unless( length $val ) # Not inserting empty fields
	{
	    next if grep{$key eq $_} qw( if );
	}

	$out .= '__'.$key.'_'.$val;
    }
    return $out;
}


##############################################################################

sub on_configure
{
    my( $class ) = @_;

    my $params =
    {
     'aloc'               => \&aloc,
     'sloc'               => \&sloc,
     'locn'               => \&locn,
     'locnl'              => \&locnl,
     'locpp'              => \&locpp,
     'locppg'             => \&locppg,
     'alocpp'             => \&alocpp,
     'alocppg'            => \&alocppg,
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

##############################################################################

sub on_reload
{
    # This will bind the newly compiled code in the params hash,
    # replacing the old code

    $_[0]->on_configure;
}

##############################################################################

1;
