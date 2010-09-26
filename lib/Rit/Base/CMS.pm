package Rit::Base::CMS;
#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren   <jonas@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2009-2010 Fredrik Liljegren.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

use Carp qw( confess );
use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug datadump deunicode );
use Para::Frame::L10N qw( loc );

use Rit::Base::Utils qw( valclean parse_propargs query_desig );


=head1 NAME

Rit::Base::CMS

=cut

=head1 DESCRIPTION

This code requires the following nodes setup:

label          => 'cms_page',
is             => 'class',
class_form_url => 'rb/cms/page.tt',

label  => 'has_url',
is     => 'predicate',
domain => 'cms_page',
range  => 'text',

label  => 'is_view_for_node',
is     => 'predicate',
domain => 'cms_page',
range  => 'resource',

label  => 'uses_template',
is     => 'predicate',
domain => 'cms_page',
range  => 'text',

label       => 'message',
is          => 'class',
description => 'A message is a page_part, could be a forum-message.',

label  => 'has_body',
is     => 'predicate',
domain => 'message',


=cut


##############################################################################

=head2 find

For finding which template to use for an URL.

Handling publish on demand.

=cut

sub find
{
    my( $class, $p_in ) = @_;

    my $req = $Para::Frame::REQ;

    my( $args, $arclim, $res ) = parse_propargs('auto');
    my $p = $p_in->normalize;
    my $R = Rit::Base->Resource;

    my $path = $p->path_slash;
#    debug "LOOKING for $path";

    debug "Test from CMS 0.  p_in is $p_in";

    # Firstly check for the common case
    #my $target_in = $p->target_with_lang;
    my $target_in = $p->target;
    my $target_path = $target_in->path_slash;

    if( $target_in->exist and not $target_in->is_dir )
    {
#       debug "  file exists";
        return $target_in;
    }

    debug "Test from CMS 1; target_in is ". $target_in->path;
    debug "Test from CMS 1; p_in target is ". $p_in->target->path;

    my $page = $R->find({
                         is  => 'cms_page',
                         has_url => $target_path,
                        }, $args)->get_first_nos;

    if( not $page and $target_path =~ /^(.*)\/index.tt$/ ) {
	$page = $R->find({
			  is  => 'cms_page',
			  has_url => $1,
			 }, $args)->get_first_nos;
    }

    if( $page )
    {
        debug "Found a page!  ID ". ref($page);
        my $end_target = $req->site->home->get_virtual( $page->uses_template );
        $req->q->param( id => $page->id);
        debug "  - Using end target: ". $end_target->sysdesig;

        #$end_target = Para::Frame::File->new({
        #                                      filename => "/var/www/brisingasmycket.se/rb/plugins/blog/inc/add_blog.tt",
        #                                     });
        #debug "  - No, Using end target: ". $end_target->sysdesig;
        return $end_target;
    }
    else
    {
        debug "Found no page with url $target_path...";
    }

    return;


    #my $target_path = $target_in->path_slash;
    #my $go_target = $req->site->home->get_virtual( '/go'.$target_path );
##    debug "  Looking for ".$go_target->sysdesig;
    #if( $go_target->exist and not $go_target->is_dir )
    #{
    #    debug "===> Go existing";
    #    return $go_target;
    #}

##    debug "Target not found: ".$target_in->sysdesig;
#
#
#
#    my( $item, $rest, $args, $go_args ) = $class->item_by_path( $path );
#    return undef unless $item;
#
#
#
#    debug "===> Getting node url";
#
#    # May change to normal item url
#    my $p_tmpl = $item->page_presentation_template($rest, $go_args);
#    my $target = $p_tmpl->target_with_lang;
#
#    # Looks for the corresponding template url
#    my $file = $target->sys_path;
#    debug "===> Looking for $file";
#
#    debug "Target is ".$target->sysdesig;
#
#    unless( -e $file )
#    {
#        ### NB! The publishing of a page gives a new target
#        $req->note(loc "Compiling page [_1]", $item->desig($args));
#        $target = $item->publish($rest, $go_args);
#        debug "New target is ".$target->sysdesig;
#    }
#
#    if( -e $file )
#    {
#        debug "Now existing: $file";
#        $p = $item->page_presentation($rest, $go_args);
#        debug "Presentation url is ".$p->sysdesig;
#
#        # Even if we later decide to actually do a redirect
#        $req->response->set_http_status(200);
#
#        if( $p->path_slash ne $path )
#        {
#            debug "===> Forwarding";
#            debug "  From ".$path;
#            debug "  To   ".$p->path_slash;
#            $req->set_page($p);
#        }
#    }
#    else
#    {
#        throw('notfound', "Failed to publish $target_path");
#    }
#
##    debug "GO returns ".$target->sysdesig;
#
#    return $target;
}



1;

# ##############################################################################
#
# =head2 item_by_path
#
# Looking up an item corresponding to a path
#
# =cut
#
# sub item_by_path
# {
#     my( $class, $path ) = @_;
#
#     # Looking at the normalized URL
#     unless( $path =~ m(^(?:/preview/(\d+))?/([^/]+)(?:/([^/]+))?(?:/(.*))?) )
#     {
#         debug "  path not handled by Go";
#         return undef;
#     }
#
# #    $C_city->initiate_rev;
#
#     my $req = $Para::Frame::REQ;
#     my $uid = $req->session->user->id;
#
#     my $target_uid = $1;
#     my $city_part  = $2;
#     my $name_part  = $3;
#     my $rest       = $4;
#
#     if( 0 )
#     {
#         debug "==== Lookup item by path";
#         debug "path = ".$path;
#         debug "uid  = ".($target_uid||'');
#         debug "city = ".($city_part||'');
#         debug "name = ".($name_part||'');
#         debug "rest = ".($rest||'');
#     }
#
#     my $city;
#     my $item;
#
#     my $go_prefix;
#     my $args = {};
#     if( $target_uid ) # for previews
#     {
#         $go_prefix = "/preview/$target_uid";
#         $args = parse_propargs('relative');
#
#         if( $uid != $target_uid )
#         {
#             throw('denied',"This page is restricted");
#         }
#
# #       debug("args is  ".datadump($args,3));
#     }
#
#     my $go_args =
#     {
#      %$args,
#      go_prefix => $go_prefix,
#     };
#
# #    debug query_desig( $go_args );
#
#
#     #### Looking up City
#     #
# #    my( $cityalts ) = $C_city->revlist('is',{url_part => $city_part},$args);
#
#     my( $cityalts ) = Rit::Base::Resource->find({
#                                                  is=>$C_city,
#                                                  url_part => $city_part,
#                                                 }, $args);
#     if( $cityalts )
#     {
#         $city = $cityalts->get_first_nos;
#     }
#     else
#     {
#         my $city_part_clean = clean_part($city_part);
#
# #       $cityalts = $C_city->revlist('is',{name_clean => $city_part_clean},$args);
#         $cityalts = Rit::Base::Resource->find({
#                                                name_clean => $city_part_clean,
#                                                is=>$C_city,
#                                               }, $args);
# #       debug "Searching for ".datadump({
# #                                        name_clean => $city_part_clean,
# #                                        is=> $C_city->id,
# #                                       });
#
#         my @maby;
#
#         foreach my $city_maby ( $cityalts->nodes )
#         {
#             debug "  Considering ".$city_maby->desig;
#             my $part_maby = $city_maby->get_set_url_part($go_args);
#             debug "  $part_maby eq $city_part_clean ?";
#             if ( $part_maby eq $city_part_clean )
#             {
#                 $city = $city_maby;
#                 last;
#             }
#             else
#             {
#                 push @maby, $city_maby;
#             }
#         }
#
#         unless( $city )
#         {
#             if( $city = $maby[0] )
#             {
#                 debug "No direct city match found. Using a close hit";
#                 debug $city->sysdesig;
#             }
#         }
#     }
#
#     unless( $city )
#     {
#         debug "No city $city_part found";
#         return undef;
# #       throw 'notfound', "City $city_part not found";
#     }
#
#     debug "===> City ".$city->desig;
#
#
#     #### Lookup item in city
#     #
#     #
#     if( $name_part )
#     {
#         # Get alternatives
#         my $trc = $C_tourist_related_client;
#
# #       my( $alts ) = $city->revlist('in_region',
# #                                    {
# #                                     is => $trc,
# #                                     url_part => $name_part,
# #                                     inactive_ne => 1,
# #                                    }, $args );
#
#         my( $alts ) = Rit::Base::Resource->find({
#                                                  is => $trc,
#                                                  url_part => $name_part,
#                                                  in_region => $city,
#                                                  inactive_ne => 1,
#                                                 }, $args);
#
#         if( $alts )
#         {
#             $item = $alts->get_first_nos;
#         }
#         else
#         {
#             my @variants = clean_part( $name_part );
#             my @words = split /\s+/, clean_part( $name_part );
#             push @variants, join '', $city_part, @words;
#             my $beginning = shift @words;
#             push @variants, join '', $beginning, $city_part, @words;
#             while ( @words )
#             {
#                 $beginning .= "" . shift @words;
#                 push @variants, join '', $beginning, $city_part, @words;
#             }
#
#             my @maby;
#
#           VARIANT:
#             foreach my $name_part_clean (@variants)
#             {
#                 debug "  Searching for variant $name_part_clean";
#
#                 $alts = Rit::Base::Resource->find({
#                                                    name_clean => $name_part_clean,
#                                                    is=> $trc,
#                                                    in_region => $city,
#                                                    inactive_ne => 1,
#                                                   }, $args);
# #               debug "Searching for ".datadump({
# #                                                name_clean => $name_part_clean,
# #                                                is=> $trc->id,
# #                                               });
#                 foreach my $item_maby ( $alts->nodes )
#                 {
#                     my $part_maby = $item_maby->get_set_url_part($go_args);
#                     debug "Comparing $part_maby with $name_part";
#                     if ( $part_maby eq $name_part )
#                     {
#                         $item = $item_maby;
#                         last VARIANT;
#                     }
#                     else
#                     {
#                         push @maby, $item_maby;
#                     }
#                 }
#             }
#
#             # No primary match. Using any secondary match
#             unless( $item )
#             {
#                 debug "No direct item match found. Using a close hit";
#                 $item = $maby[0];
#             }
#         }
#
#         unless( $item )
#         {
#             throw 'notfound', "Business $name_part not found in $city_part";
#         }
#     }
#     else
#     {
#         $item = $city;
#     }
#
#     return( $item, $rest, $args, $go_args );
# }
#
# ##############################################################################
#
# =head2 clean_part
#
# =cut
#
# sub clean_part
# {
#     my $clean = $_[0];
#     $clean =~ s/_/ /g;
#     return valclean($clean);
# }
#
# ##############################################################################
