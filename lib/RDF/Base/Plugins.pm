package RDF::Base::Plugins;

#=============================================================================
#
# AUTHOR
#   Fredrik Liljegren <fredrik@liljegren.org>
#
# COPYRIGHT
#   Copyright (C) 2010-2017 Fredrik Liljegren.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use File::stat;
use Fcntl ':mode';

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug datadump deunicode compile );

use RDF::Base::Utils qw( parse_arc_add_box parse_propargs );

=head1 NAME

RDF::Base::Plugins;

=cut

=head1 DESCRIPTION

Handle plugins; install, deinstall, list...

=cut

sub new
{
    my( $class ) = @_;

    my $plugins = bless
    {
    }, $class;

    return $plugins;
}


=head2 initiate_plugin_support

Initiates nodes required for plugin support.

=cut

sub initiate_plugin_support
{
    my( $args, $arclim, $res ) = parse_propargs('auto');
    my $R = RDF::Base->Resource;

    my $plugin = $R->find_set({
			       is    => 'class',
			       label => 'plugin',
			      }, $args);

    my $has_plugin_version = $R->find_set({
					   is     => 'predicate',
					   label  => 'has_plugin_version',
					   domain => $plugin,
					   range  => 'int',
					  }, $args);

    $res->autocommit({ activate => 1 });

    return "Done";
}


=head2 list_available

=cut

sub list_available
{
    my $cfg = $Para::Frame::CFG;

    my $rb_root = $cfg->{'rb_root'};
    my $plugins_dir = $rb_root ."/plugins";

    opendir(PLUGINS_DIR, $plugins_dir)
      or throw('fatal', "Couldn't open plugins dir: $plugins_dir");

    my @filelist = readdir(PLUGINS_DIR);
    closedir(PLUGINS_DIR);

    my $out = "Available in $plugins_dir:\n";

    my @plugin_dirs;

    foreach my $file (@filelist)
    {
	next
	  if($file eq '.' or $file eq '..');

	my $mode = (stat($plugins_dir .'/'. $file))->mode;

	if( S_ISDIR($mode) )
	{
	    push @plugin_dirs, $file;
	}
    }

    my @plugins;
    foreach my $plugin_dir (@plugin_dirs)
    {
	eval
	{
	    debug "Compiling $plugins_dir/$plugin_dir/plugin_handle.pm";
	    compile("$plugins_dir/$plugin_dir/plugin_handle.pm");
	    # exceptions will be rewritten: "Can't locate $filename: $@"
	};
	if( $@ )
	{
	    throw('error', "Well, not good: $@");
	}
	else
	{
	    my $plugin = "RDF::Base::Plugins::$plugin_dir";

	    debug "Trying ". $plugin .'::plugin_handle';

	    no strict 'refs';
	    push @plugins, &{$plugin .'::plugin_handle::new'}();
	}
    }

    return @plugins;
}


sub install
{
    my( $class, $plugin_dir ) = @_;

    my $cfg = $Para::Frame::CFG;
    my $rb_root = $cfg->{'rb_root'};
    my $plugins_dir = $rb_root ."/plugins";

    debug "Compiling $plugins_dir/$plugin_dir/plugin_handle.pm";
    compile("$plugins_dir/$plugin_dir/plugin_handle.pm");

    no strict 'refs';
    my $plugin = &{'RDF::Base::Plugins::'. $plugin_dir .'::plugin_handle::new'}();

    return $plugin->install();
}



1;
