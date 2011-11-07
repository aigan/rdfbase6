package RDF::Base::Renderer::AJAX;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2007-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;
use utf8;
use base 'Para::Frame::Renderer::Custom';

use JSON; # to_json from_json
#use Carp qw( cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw datadump
			   trim package_to_module compile );
use Para::Frame::L10N qw( loc );

use RDF::Base::Utils qw( arc_lock arc_unlock );

##############################################################################
# I'm sorry...  I should never have added these to RB; they are RG
# specific.
# TODO: FIXME!  ...move it to RG::AJAX::... instead.. or something...
# They are used for displaying specific types of nodes in rb-lookup
our $C_zipcode     ;
our $C_city        ;
our $C_country     ;
our $C_person      ;
our $C_organization;
our $C_lodging     ;
our $C_location    ;

BEGIN {
    my $C = RDF::Base->Constants;
    $C_zipcode      = $C->find({ label => 'zipcode'      }) || undef;
    $C_city         = $C->find({ label => 'city'         }) || undef;
    $C_country      = $C->find({ label => 'country'      }) || undef;
    $C_person       = $C->find({ label => 'person'       }) || undef;
    $C_organization = $C->find({ label => 'organization' }) || undef;
    $C_lodging      = $C->find({ label => 'lodging'      }) || undef;
    $C_location     = $C->find({ label => 'location'     }) || undef;
}
##############################################################################



##############################################################################

sub render_output
{
    my( $rend ) = @_;

    debug "Rendering AJAX response.";

    my $req = $rend->req;
    my $q = $req->q;
    my $R = RDF::Base->Resource;

    my $params;
    if( my $params_in = $q->param('params') )
    {
	$params = from_json( $params_in );
	debug "Got params data: ". datadump($params);
    }


    my( $file ) = ( $rend->url_path =~ /\/ajax\/(.*?)$/ );
    my $out = "";

    debug "AJAX 'file': $file";

    if( $file eq 'wu' )
    {
	$req->require_root_access;

	$rend->{'ctype'} = 'html';

	$out .= RDF::Base::AJAX->wu( $params );
    }
    elsif( $file =~ /action\/(.*)/ )
    {
	$req->require_root_access;
	my $action = $1;

	if( $action eq 'add_direct' )
	{
	    $rend->{'ctype'} = 'html';
	    my $subj = $R->get($q->param('subj'));
	    my $pred_name = $q->param('pred_name');
	    my $obj = $R->get($q->param('obj'));
	    my $rev = $q->param('rev');

	    my $on_arc_add;
	    if( my $on_arc_add_json = $q->param('on_arc_add') )
	    {
		$on_arc_add = from_json($on_arc_add_json);
	    }

	    my $args =
	    {
		activate_new_arcs => 1,
	    };

	    arc_lock();

	    my $arc;
	    if( $rev )
	    {
		$arc = $obj->add_arc({ $pred_name => $subj }, $args );
	    }
	    else
	    {
		$arc = $subj->add_arc({ $pred_name => $obj }, $args );
	    }

	    if( $on_arc_add )
	    {
		# on_arc_add can be constructed by the client. IT IS
		# NOT SAFE!
		#
		$req->require_root_access;

		foreach my $meth ( keys %$on_arc_add )
		{
		    $subj->$meth( $on_arc_add->{$meth}, $args );
		}
	    }

	    arc_unlock();


	    $out = $obj->wu_jump .'&nbsp;'. $arc->edit_link_html;

	    debug "Returning: $out";
	}
	elsif( $action eq 'remove_arc' )
	{
	    $req->require_root_access;
	    my $arc = $R->get($q->param('arc'));

	    $arc->remove({ activate_new_arcs => 1 });

	    $out = 'done';
	}
	elsif( $action eq 'create_new' )
	{
	    $req->require_root_access;
	    my $rev = $q->param('rev');
	    my $name = $q->param('name')
	      or throw('incomplete', "Didn't get name");

	    my $obj = $R->create({
				  name => $name,
				  %$params,
				 }, { activate_new_arcs => 1 });

	    my $subj = $R->get($q->param('subj'));
	    my $pred_name = $q->param('pred_name');


	    my $arc;
	    if( $rev )
	    {
		$arc = $obj->add_arc({ $pred_name => $subj },
				     { activate_new_arcs => 1 });
	    }
	    else
	    {
		$arc = $subj->add_arc({ $pred_name => $obj },
				      { activate_new_arcs => 1 });
	    }

	    $out = $obj->wu_jump .'&nbsp;'. $arc->edit_link_html;
	}
	else
	{
	    die("Unknown action $action");
	}
    }
    elsif( $file eq 'lookup' )
    {
	$req->require_root_access;
	$rend->{'ctype'} = 'json';
	my $lookup_preds = from_json( $q->param('search_type') );
	my $lookup_value = $q->param('search_value');
	trim( \$lookup_value );

	unless( length $lookup_value )
	{
	    $out = to_json([{
			     id => 0,
			     name => loc("Invalid search"),
			    }]);
	    return \$out;
	}


	my $result;
	foreach my $lookup_pred (@$lookup_preds)
	{
	    if( $lookup_pred =~ /_like$/ )
	    {
		if( length($lookup_value) < 3 )
		{
		    debug "removing _like from short search param";
		    $lookup_pred =~ s/_like$//;

#		    $out = to_json([{
#				     id => 0,
#				     name => "Invalid search"
#				    }]);
#		    return \$out;
		}
	    }


	    debug "  looking up $lookup_pred";
	    my $params_lookup =
	    {
	     %$params,
	     $lookup_pred => $lookup_value,
	    };

	    $result = $R->find($params_lookup)->sorted('name');
	    last if $result->size;
	}

	if( $result )
	{
	    $result->reset;
	    my @list;
	    while( my $node = $result->get_next_nos )
	    {
		my $item = {
			    id       => $node->id,
			    name     => $node->desig,
			    is      => $node->is_direct->desig,
			    form_url => $node->form_url->as_string,
			   };
		push @list, $item;
	    }
	    $out = to_json( \@list );
	}
	else
	{
	    $out = to_json([{
			       id   => 0,
			       name => loc("No hits"),
			      }]);
	}
    }
    elsif( $file =~ /app\/(.*)/ )
    {
	my $appbase = $Para::Frame::CFG->{'appbase'};
	my $app = $appbase .'::AJAX::'. $1;

	eval
	{
	    compile(package_to_module($app));
	    require(package_to_module($app));
	};
	if( $@ )
	{
	    debug "AJAX couldn't find: ". package_to_module($app);

            $appbase = 'RDF::Base';
            $app = $appbase .'::AJAX::'. $1;

            eval
            {
                compile(package_to_module($app));
                require(package_to_module($app));
            };
            if( $@ )
            {
                debug "AJAX couldn't find: ". package_to_module($app);
                debug "Error: ". datadump( $@ );
                return;
            }
	}

        debug "AJAX App is $app";

        $out = $app->handler( $req );

        debug "out is: $out";
    }


    if( $q->param('seen_node') )
    {
	$R->get($q->param('seen_node'))->update_seen_by;
    }

    return \$out;
}


##############################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    unless( $ctype )
    {
        die "No ctype given to set";
    }

    if( $rend->{'ctype'} eq 'json' )
    {
	$ctype->set("application/json; charset=UTF-8");
    }
    else #if( $rend->{'ctype'} eq 'html' )
    {
	$ctype->set("text/html; charset=UTF-8");
    }
}


##############################################################################

1;
