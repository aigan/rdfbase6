package Rit::Base::Action::cms_page;

use strict;
use Rit::Base::Utils qw( string parse_propargs );

sub handler
{
    my( $req ) = @_;

    my $url = $req->original_url_string;
    my $R = Rit::Base->Resource;

    my( $args, $arclim, $res ) = parse_propargs('auto');

    $args = parse_propargs({
                            %$args,
                            activate_new_arcs => 1,
                           });
    $Para::Frame::REQ->{'rb_default_propargs'} = $args;

    #my $cms_page = $R->find_set({
    #                             is => 'class',
    #                             label => 'cms_page',
    #                            }, $args);
    #my $has_url = $R->find_set({
    #                            is => 'predicate',
    #                            label => 'has_url',
    #                            domain => $cms_page,
    #                            range  => 'text',
    #                           }, $args);
    #

    my $test_blog = $R->find_set({
                                  is   => 'cms_page',
                                  name => 'My test blog post',
                                  has_body => '<h1>My test post</h1><p>This is a test</p>',
                                 }, $args);

    $res->autocommit;


    my $page = $R->find({
                         is  => 'cms_page',
                         has_url => $url,
                        }, $args);

    if( $page )
    {
        
    }
    else
    {
    }

    return "Yeps.";
}


1;
