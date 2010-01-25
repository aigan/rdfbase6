package Rit::Base::Plugins::Blog::plugin_handle;

use Rit::Base::Utils qw( parse_arc_add_box parse_propargs );
use Rit::Base::Constants qw( $C_resource );

sub new
{
    $class = 'Rit::Base::Plugins::Blog::plugin_handle';

    my $plugin_blog = bless
    {
     name    => 'Blog',
     version => '0.5',
     description => 'A simple plugin to do blogging.',
    }, $class;

    return $plugin_blog;
}

sub install
{
    my( $class ) = @_;

    my( $args, $arclim, $res ) = parse_propargs('auto');
    my $R = Rit::Base->Resource;

    $C_resource->add({ is => 'class' }, $args);
    $res->autocommit({ activate => 1 });


    my $instances_uses_template =
      $R->find_set({
		    label       => 'instances_default_template',
		    is          => 'predicate',
		    domain_scof => 'cms_page',
		    range       => 'text',
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






    # Register plugin
    my $plugin_blog = $R->find_set({
				    is      => 'plugin',
				    name    => $class->{name},
				    has_plugin_version => $class->{version},
				   }, $args);

    # Create base classes


    # A 'blog' is a collection of blog-posts in named 'blog'...  A
    # blog can be subclassed for blogging sections in a system; ie
    # news, members-blogs.
    my $blog_module = $R->find_set({
				    is => 'class_perl_module',
				    code => 'Rit::Base::Plugins::Blog',
				   }, $args);
    my $blog =
      $R->find_set({
		    label => 'plugin_blog',
		    is => 'class',
		    class_handled_by_perl_module => $blog_module,
		    class_form_url               => 'rb/plugins/Blog/blog.tt',
		   }, $args);


    # A 'blog_post' is a single post IN a blog.
    my $blog_post_module = $R->find_set({
					 is => 'class_perl_module',
					 code => 'Rit::Base::Plugins::Blog::Post',
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


    # Add soft links for code, html etc...
    #my( $plugin_dir ) = /^(.*)\/(.*?)$/, __LINE__;
    #...



    $res->autocommit({ activate => 1 });


    $blog
}

1;
