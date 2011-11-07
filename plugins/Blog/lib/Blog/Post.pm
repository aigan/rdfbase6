package RDF::Base::Plugins::Blog::Post;

use strict;
use warnings;

use utf8;

use Para::Frame::Reload;
use Para::Frame::Time qw( now );

use RDF::Base::Constants qw( $C_plugin_blog_post_comment );

sub publish
{
    my( $post, $args ) = @_;

    my $name_part = lc $post->name;

    $name_part =~ s/[: -\/]/_/g;
    $name_part =~ s/[åäáà]/a/g;
    $name_part =~ s/[é]/e/g;
    $name_part =~ s/ö/o/g;
    $name_part =~ s/[!\?]//g;

    my $blog = $post->plugin_blog_post_is_in_blog;

    my $url = $blog->has_plugin_blog_base_url
      .'/'. $name_part;

    my $template = $blog->instances_default_template;

    # Todo: Check that url isn't busy

    $post->update({ has_url       => $url         }, $args);
    $post->update({ uses_template => $template    }, $args);

    $post->update({ has_date      => now()->stamp }, $args )
      unless( $post->has_date );

    return $url;
}


sub add_comment
{
    my( $post, $name, $has_email, $message, $args ) = @_;

    my $R = RDF::Base->Resource;

    $R->create({
		is        => $C_plugin_blog_post_comment,
		is_from   => $name,
		has_email => $has_email,
		has_body  => $message,
		has_date  => now()->stamp,
		plugin_blog_post_comment_is_about => $post,
	       }, $args);

    return;
}



1;
