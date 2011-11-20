package RDF::Base::Plugins::Blog::plugin_handle;

use 5.010;
use strict;
use warnings;
use RDF::Base::Utils qw( parse_arc_add_box parse_propargs );
use RDF::Base::Constants qw( $C_resource );

sub new
{
    my $class = 'RDF::Base::Plugins::Blog::plugin_handle';

    my $plugin_blog = bless
    {
     name    => 'Blog',
     version => '0.6',
     description => 'A simple plugin to do blogging.',
    }, $class;

    return $plugin_blog;
}

sub install
{
    my( $class ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('auto');
    my $R = RDF::Base->Resource;

    # Register plugin
    my $plugin_blog_reg = $R->find_set({
                                        is      => 'plugin',
                                        name    => $class->{name},
                                       }, $args);
    $plugin_blog_reg->update({ has_plugin_version => $class->{version} },
                             $args);

    # Create base classes


    # A 'blog' is a collection of blog-posts in named 'blog'...  A
    # blog can be subclassed for blogging sections in a system; ie
    # news, members-blogs.
    my $blog_module = $R->find_set({
				    is   => 'class_perl_module',
				    code => 'RDF::Base::Plugins::Blog',
				   }, $args);
    my $blog =
      $R->find_set({
		    label                        => 'plugin_blog',
		    is                           => 'class',
		    class_handled_by_perl_module => $blog_module,
		    class_form_url               => 'rb/plugins/Blog/blog.tt',
		   }, $args);


    my $instances_uses_template =
      $R->find_set({
		    label       => 'instances_default_template',
		    is          => 'predicate',
		    domain_scof => 'cms_page',
		    range       => 'text',
		   }, $args);

    my $has_plugin_blog_base_url =
      $R->find_set({
		    label  => 'has_plugin_blog_base_url',
		    is     => 'predicate',
		    domain => 'plugin_blog',
		    range  => 'text',
		   }, $args);

    my $has_plugin_version =
      $R->find_set({
		    is     => 'predicate',
		    label  => 'has_plugin_version',
		    domain => 'plugin',
		    range  => 'int',
		   }, $args);

    my $is_view_for_node =
      $R->find_set({
		    label       => 'is_view_for_node',
		    is          => 'predicate',
		    domain      => 'cms_page',
		    range       => $C_resource,
		   }, $args);

    $res->autocommit({ activate => 1 });






    # A 'blog_post' is a single post IN a blog.
    my $blog_post_module = $R->find_set({
					 is => 'class_perl_module',
					 code => 'RDF::Base::Plugins::Blog::Post',
					}, $args);
    my $blog_post =
      $R->find_set({
		    label                        => 'plugin_blog_post',
		    scof                         => 'cms_page',
		    class_handled_by_perl_module => $blog_post_module,
		    class_form_url               => 'rb/plugins/Blog/post.tt',
		   }, $args);

    my $plugin_blog_post_is_in_blog =
      $R->find_set({
		    label  => 'plugin_blog_post_is_in_blog',
		    is     => 'predicate',
		    domain => $blog_post,
		    range  => $blog,
		   }, $args);

    my $plugin_blog_post_comment =
      $R->find_set({
		    label => 'plugin_blog_post_comment',
		    is    => 'class',
		   }, $args);

    my $plugin_blog_post_comment_is_about =
      $R->find_set({
		    label => 'plugin_blog_post_comment_is_about',
		    is    => 'predicate',
		    domain => 'plugin_blog_post_comment',
		    range  => 'plugin_blog_post',
		   }, $args);


    # Blog types are both scof -> C_plugin_blog and is -> C_plugin_blog_type
    my $plugin_blog_type_module
      = $R->find_set({
		      is => 'class_perl_module',
		      code => 'RDF::Base::Plugins::Blog::Type',
		     }, $args);

    my $plugin_blog_type
      = $R->find_set({
		      label                        => 'plugin_blog_type',
		      is                           => 'class',
		      class_handled_by_perl_module => $plugin_blog_type_module,
		      class_form_url               => 'rb/plugins/Blog/type.tt',
		     }, $args);

    # Add soft links for code, html etc...
    #my( $plugin_dir ) = /^(.*)\/(.*?)$/, __LINE__;
    #...



    $res->autocommit({ activate => 1 });


    $blog
}

1;
