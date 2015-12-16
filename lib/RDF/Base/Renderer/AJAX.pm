package RDF::Base::Renderer::AJAX;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <fredrik@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2007-2015 Avisita AB.  All Rights Reserved.
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

#no warnings "experimental";
no if $] >= 5.018, warnings => "experimental";

use constant R => 'RDF::Base::Resource';

use JSON;                       # to_json from_json
use Carp qw( cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw catch datadump
                           trim package_to_module compile );
use Para::Frame::L10N qw( loc );

use RDF::Base::AJAX;
use RDF::Base::Widget::Handler;
use RDF::Base::Utils qw( arc_lock arc_unlock query_desig valclean );

##############################################################################

=head2 render options

 wu
 action/add_direct
 action/remove_arc
 action/create_new
 action/update
 lookup
 app/arc_create
 app/arc_update
 app/translate_string
 app/*



=cut

sub render_output
{
    my( $rend ) = @_;

#    debug "Rendering AJAX response";

    $rend->{'ctype'} = 'html'; # Set to json if appropriate
    my $out = "";
    my $args;
    my $args_in = $rend->req->q->param('args');

    eval
    {

        if( $args_in )
        {
            $args =  from_json( $args_in );
            debug("args = " . query_desig($args));
        }


        my( $file ) = ( $rend->url_path =~ /\/ajax\/(.*)/ );
        unless( $file )
        {
            die "AJAX renderer only handles the /ajax/ path";
        }

        debug "AJAX path: $file";

        ### Versioned, next generation ajax api
        #
        if ( $file =~ /(\d+)\/(.*)/ )
        {
            die "Version $1 not supported " unless $1 == 1;

            my $path = $2;
            if( $path =~ /(\d+)\/(.*)/ )
            {
                $out = $rend->render_node( $1, $2, $args );
                return;
            }
            elsif( $path =~ /tt\/(.*)/ )
            {
                $out = $rend->render_tt($1, $args);
                return;
            }
            elsif( $path =~ /ttget\/(.*)/ )
            {
                $out = $rend->render_ttget($1, $args);
                return;
            }
        }

        if ( $file eq 'wu' )    # used by rb.js PagePart
        {
            $out = $rend->render_wu();
        }
        elsif ( $file =~ /action\/(.*)/ ) # used by rb.js
        {
            $out = $rend->render_action($1);
        }
        elsif ( $file eq 'lookup' ) # used by rb.js
        {
            $out = $rend->render_lookup();
        }
        elsif ( $file =~ /app\/(.*)/ ) # custom code api
        {
            $out = $rend->render_app( $1 );
        }
        else
        {
            die "Ajax path $file not supported";
        }

        my $q = $rend->req->q;
        if ( $q->param('seen_node') )
        {
            R->get($q->param('seen_node'))->update_seen_by;
        }
    };

    if( my $err = catch($@) )
    {
        $out = to_json({
                        error =>
                        {
                         type => $err->type,
                         info => $err->info,
                        }
                       });
        debug 0,"$err";
    }

    return \$out;
}


##############################################################################

sub render_wu
{
    my( $rend ) = @_;

    $rend->req->require_root_access;
    my $q = $rend->req->q;
    my $params;
    if ( my $params_in = $q->param('params') )
    {
        debug "Parsing params $params_in";
        $params = from_json( $params_in );
        debug "Got params data: ". datadump($params);
    }

    foreach my $key ( $q->param )
    {
        debug " param $key = ".$q->param($key);
    }

    return RDF::Base::AJAX->wu( $params );
}

##############################################################################

sub render_app
{
    my( $rend, $applabel ) = @_;

    my $appbase = $Para::Frame::CFG->{'appbase'};
    my $app = $appbase .'::AJAX::'. $applabel;

    eval
    {
        compile(package_to_module($app));
        require(package_to_module($app));
    };
    if ( $@ )
    {
        debug "AJAX couldn't find: ". package_to_module($app);
        debug "Error: ". datadump( $@ );

        $appbase = 'RDF::Base';
        $app = $appbase .'::AJAX::'. $applabel;

        eval
        {
            compile(package_to_module($app));
            require(package_to_module($app));
        };
        if ( $@ )
        {
            debug "AJAX couldn't find: ". package_to_module($app);
            debug "Error: ". datadump( $@ );
            return;
        }
    }

    debug "AJAX App is $app";

    return $app->handler( $rend->req );
}

##############################################################################

sub render_action
{
    my( $rend, $action ) = @_;

    my $req = $rend->req;
    my $q = $req->{'q'};
    my $out = "";

    $req->require_root_access;

    my $params;
    if ( my $params_in = $q->param('params') )
    {
        debug "Parsing params $params_in";
        $params = from_json( $params_in );
        debug "Got params data: ". datadump($params);
    }

    if ( $action eq 'add_direct' )
    {
        my $subj = R->get($q->param('subj'));
        my $pred_name = $q->param('pred_name');
        my $obj = R->get($q->param('obj'));
        my $rev = $q->param('rev');

        my $on_arc_add_json = $q->param('on_arc_add');
        my $on_arc_add;
        if ( $on_arc_add_json and $on_arc_add_json ne 'null')
        {
            $on_arc_add = from_json($on_arc_add_json);
        }

        my $args =
        {
         activate_new_arcs => 1,
        };

        arc_lock();

        my $arc;
        if ( $rev )
        {
            $arc = $obj->add_arc({ $pred_name => $subj }, $args );
        }
        else
        {
            $arc = $subj->add_arc({ $pred_name => $obj }, $args );
        }

        if ( $on_arc_add )
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
    elsif ( $action eq 'remove_arc' )
    {
        $req->require_root_access;
        my $arc = R->get($q->param('arc'));

        $arc->remove({ activate_new_arcs => 1 });

        $out = 'done';
    }
    elsif ( $action eq 'create_new' )
    {
        $req->require_root_access;
        my $rev = $q->param('rev');
        my $name = $q->param('name')
          or throw('incomplete', "Didn't get name");

        my $obj = R->create({
                              name => $name,
                              %$params,
                             }, { activate_new_arcs => 1 });

        my $subj = R->get($q->param('subj'));
        my $pred_name = $q->param('pred_name');


        my $arc;
        if ( $rev )
        {
            $arc = $obj->add_arc({ $pred_name => $subj },
                                 {
                                  activate_new_arcs => 1 });
        }
        else
        {
            $arc = $subj->add_arc({ $pred_name => $obj },
                                  {
                                   activate_new_arcs => 1 });
        }

        $out = $obj->wu_jump .'&nbsp;'. $arc->edit_link_html;
    }
    elsif ( $action eq 'update' )
    {
        my $subj = R->get($params->{'subj'})
          or throw('missing','Node missing');
        unless( $req->session->user->has_root_access
                or $subj->is_owned_by( $req->session->user )
              )
        {
            throw('denied', "Access denied");
        }

        my $pred_name = $params->{'pred_name'};
        my $val = $q->param('val');
#            debug(datadump($q));
#            debug(datadump($params));

        my $jsup = from_json( $params->{'params'} );

        $q->param($jsup->{'id'}, $val);
        $q->param('id', $params->{'subj'});

        my $args =
        {
         activate_new_arcs => 1,
         node => $subj,
        };

        RDF::Base::Widget::Handler->update_by_query($args);

        $out .= RDF::Base::AJAX->wu( $params );
    }
    else
    {
        die("Unknown action $action");
    }

    return $out;
}


##############################################################################

sub render_lookup
{
    my( $rend ) = @_;

    my $req = $rend->req;
    my $q = $req->{'q'};

    $req->require_root_access;

    my $params;
    if ( my $params_in = $q->param('params') )
    {
        debug "Parsing params $params_in";
        $params = from_json( $params_in );
        debug "Got params data: ". datadump($params);
    }

    $rend->{'ctype'} = 'json';
    my $lookup_preds = from_json($q->param('search_type'));
    my $lookup_value = $q->param('search_value');
    trim( \$lookup_value );

    unless( length $lookup_value )
    {
        return to_json([{
                         id => 0,
                         name => loc("Invalid search"),
                        }]);
    }

    my $result;
    foreach my $lookup_pred (@$lookup_preds)
    {
        if ( $lookup_pred =~ /_(like|begins)$/ )
        {
            if ( length(valclean($lookup_value)) < 3 )
            {
                debug "removing _like from short search param";
                $lookup_pred =~ s/_like$//;
            }
        }

        next unless length(valclean($lookup_value));

        debug "*  looking up $lookup_pred '$lookup_value'";

        $params ||= {};
        my $params_lookup =
        {
         %$params,
         $lookup_pred => $lookup_value,
        };

#        debug "Lookup ".query_desig($params_lookup);

        $result = R->find($params_lookup)->sorted('name');
        last if $result->size;
    }

    my @list;
    if ( $result )
    {
        $result->reset;

        my @result_properties =
          $q->param('result_properties') ||
          $q->param('result_properties[]') ||
          qw( form_url tooltip_html );

        my %allowed = map{$_=>1}
          qw(
                form_url
                longdesig
                mobile_phone
                address
           );

        my $name_method = $q->param('name_method') || 'longdesig';
        push @result_properties, $name_method;

        while ( my $node = $result->get_next_nos )
        {
            my $item =
            {
             id => $node->id,
            };

            foreach ( @result_properties )
            {
                my $key = $_;
                if( $key eq $name_method )
                {
                    $key = 'name';
                }

                when("tooltip_html")
                {
                    $item->{'tooltip_html'} =
                      $node->select_tooltip_html({lookup_preds=>$lookup_preds});
                }
                when($node->can($_))
                {
                    die "not allowed: $_" unless $allowed{$_};
                    my $res = $node->$_;
                    if ( UNIVERSAL::can( $res, 'as_string') )
                    {
                        $res = $res->as_string;
                    }
                    $item->{$key} = $res;
                }
                default
                {
                    my @l;
                    foreach my $v ( $node->list($_)->as_array )
                    {
                        if ( $v->is_literal )
                        {
                            $v = $v->plain;
                        }
                        elsif ( $v->is_resource )
                        {
                            $v = $v->id;
                        }
                        elsif ( not $v->defined )
                        {
                            $v = undef;
                        }
                        else
                        {
                            die "Obj $v not handled";
                        }
                        push @l, $v;
                    }

                    if( $key eq 'name' )
                    {
                        $item->{$key} = $l[0] || $node->desig;
                    }
                    else
                    {
                        $item->{$key} = \@l;
                    }
                }
            }

            push @list, $item;

#                {
#                 tooltip_html => $node->select_tooltip_html({lookup_preds=>$lookup_preds}),
#                 id => $node->id,
#                 name => $node->longdesig,
#                 form_url => $node->form_url->as_string,
#                };
        }
    }
    else
    {
        unless( $q->param('hide_no_hits') )
        {
            push @list,
            {
             id   => 0,
             name => loc("No hits"),
            };
        }
    }

    return to_json( \@list );
}

##############################################################################

sub render_node
{
    my( $rend, $id, $path, $args ) = @_;


    my $n = R->get( $id );
    $rend->{'ctype'} = 'json';
    $path ||= 'props';

    my @l;

    $rend->req->require_root_access;

    if( $path eq 'props' )
    {
        @l = $n->props_as_json_ref($args);
    }
    elsif( $path eq 'revprops' )
    {
        @l = $n->revprops_as_json_ref($args);
    }
    elsif( $path =~ /^get\/(\w+)/ )
    {
        my $pnlist = $n->list($1,undef,$args);
        while( my $pn = $pnlist->get_next_nos )
        {
            push @l, $pn->props_as_json_ref($args);
        }
    }
    elsif( $path =~ /^revget\/(\w+)/ )
    {
        my $pnlist = $n->revlist($1, undef, $args);
        while( my $pn = $pnlist->get_next_nos )
        {
            push @l, $pn->props_as_json_ref($args);
        }
    }
    else
    {
        die "Path $path not supported";
    }

#    debug "Returning data: ".datadump(\@l,3);

    return to_json({data=>[@l]});
}

##############################################################################

sub render_tt
{
    my( $rend, $path, $args ) = @_;

    my $req = $rend->req;
    $req->require_root_access;
    my $q = $req->{'q'};

    my $params_in = from_json( $q->param('params') );
    my $template = $q->param('template');

    debug datadump([$template,$params_in]);

    my $params = {%$Para::Frame::PARAMS, %$params_in};

    # Based on Para::Frame::Burner/burn
    #
    my $burner = Para::Frame::Burner->get_by_type('plain');
    my $th = $burner->th();

    # Clean out previous variables from stash
    $th->{ SERVICE }{ CONTEXT }{ STASH } = Template::Stash::XS->new();

    my $out = "";
    my $res = $th->process( \ $template, $params, \ $out, {binmode=>':utf8'});
    if ( $res )
    {
        debug "Got out: ".$out;
        return to_json({data=>[$out]});
    }
    else
    {
        my $err = $th->error();
        debug "Got err: ".$err;
        return to_json({
                        error =>
                        {
                         type => $err->type,
                         info => $err->info,
                        }
                       });
    }
}

##############################################################################

sub render_ttget
{
    my( $rend, $path, $args ) = @_;

    my $req = $rend->req;
    $req->require_root_access;
    $req->user->set_default_propargs({activate_new_arcs => 1 });

    my $q = $req->{'q'};
    my $params_in = from_json( $q->param('params')||'{}' );

    my $expr = $q->param('expr');
    my $template = '[% '.$expr.' %]';

#    debug datadump([$template,$params_in]);

    my $params = {%$Para::Frame::PARAMS, %$params_in};

    # Based on Para::Frame::Burner/burn
    #
    my $burner = Para::Frame::Burner->get_by_type('plain');
    my $th = $burner->th();

    # Clean out previous variables from stash
    $th->{ SERVICE }{ CONTEXT }{ STASH } = Template::Stash::XS->new();

    #######################################
#    # Tried to get down to the actual parsed result
#    #
#    my $service = $th->{ SERVICE };
#    my $context = $service->{ CONTEXT };
#    $params->{ template } = \$template;
#    $context->localise($params);
#    my $provider = $context->{ LOAD_TEMPLATES }[0];
##    my $parser = Template::Config->parser($provider->{PARAMS});
##    my $tokens = $parser->split_text($template);
##    my $code = $parser->_parse($tokens, {});
#    my( $compiled, $compile_err) = $provider->fetch(\$template);
#    $context->{ STASH }->update($params);
#    my $stash = $context->{ STASH };
#    my $test = $compiled->process($context);
    #######################################

    ### Fails to fail on undefined function/method

    my $out = "";
    my $res = $th->process( \ $template, $params, \ $out, {binmode=>':utf8'});
    if ( $res )
    {
#        debug "Got out: ".datadump($out);

        if( my $err = $th->error )
        {
            debug "Got err: ".$err;
            return to_json({
                            error =>
                            {
                             type => $err->type,
                             info => $err->info,
                            }
                           });
        }

        return $out;
    }
    else
    {
        my $err = $th->error();
        debug "Got err: ".$err;
        return to_json({
                        error =>
                        {
                         type => $err->type,
                         info => $err->info,
                         context => $err->text,
                        }
                       });
    }
}

##############################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    unless( $ctype )
    {
        die "No ctype given to set";
    }

    if ( $rend->{'ctype'} eq 'json' )
    {
        $ctype->set("application/json; charset=UTF-8");
    }
    else                        #if( $rend->{'ctype'} eq 'html' )
    {
        $ctype->set("text/html; charset=UTF-8");
    }
}


##############################################################################

sub render_error
{
    my( $part ) = @_;
    debug $part->as_string();
    return 1;
}


##############################################################################

1;
