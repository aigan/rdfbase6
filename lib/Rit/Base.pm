#  $Id$  -*-cperl-*-
package Rit::Base;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base - The ultimate database

=cut

=head1 DESCRIPTION

See L<Rit::Base::Object> for the baseclass for most classes.

=cut

use vars qw( $VERSION );

BEGIN
{
    $VERSION = "6.55";
    print "Loading ".__PACKAGE__." $VERSION\n";

    $Rit::Base::ioid = 0; # Internal object enumeration
}

use Para::Frame;
use Para::Frame::Utils qw( debug );
use Para::Frame::Reload;

use Rit::Base::Utils;
use Rit::Base::Object;
use Rit::Base::Node;
use Rit::Base::Undef;
use Rit::Base::Resource;
use Rit::Base::Arc;
use Rit::Base::Pred;
use Rit::Base::User;
use Rit::Base::Session;
use Rit::Base::L10N;
use Rit::Base::Widget;
use Rit::Base::Search::Collection;
use Rit::Base::Search::Result;
use Rit::Base::Literal::String; # Needed by RB::Utils
use Rit::Base::Setup;

# Used in Rit::Base::Resource->first_bless()
our %LOOKUP_CLASS_FOR =
    (
     Rit::Base::Resource   => 1,
     Rit::Base::User::Meta => 1,
    );

our  $IN_STARTUP = 1; # Set to 0 after db init
our  $VACUUM_ALL = 0; # Only for initialization and repair

#########################################################################

BEGIN
{
    $Para::Frame::HOOK{'on_ritbase_ready'} = [];
}

#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name

=cut

sub init
{
    my( $this ) = @_;

    warn "Adding hooks for Rit::Base\n";

    # Just in case we temporarily switched to root and got an exception
    Para::Frame->add_hook('on_error_detect', sub
			  {
			      Rit::Base::User->revert_from_temporary_user();
			      if( $Para::Frame::U )
			      {
				  $Para::Frame::U->set_default_propargs(undef);
			      }
			  });

    Para::Frame->add_hook('on_startup', \&init_on_startup);

    # Can't unlock all arcs in the middle of an operation. Wait until
    # we are done. Also wait with resources...
    #
#    Para::Frame->add_hook('before_db_commit', sub
#			  {
#			      Rit::Base::Resource->commit();
#			      Rit::Base::Arc->unlock_all();
#			  });

    Para::Frame->add_hook('after_db_rollback', sub
			  {
			      Rit::Base::Resource->rollback();
			      Rit::Base::Arc->rollback();
			  });

    Para::Frame->add_hook('done', \&on_done);

    Para::Frame->add_hook('add_background_jobs', \&add_background_jobs);

    $Para::Frame::CFG->{'search_collection_class'} ||=
      'Rit::Base::Search::Collection';
    $Para::Frame::CFG->{'search_result_class'} ||=
      'Rit::Base::Search::Result';
    $Para::Frame::CFG->{'email_subject_class'} ||=
      'Rit::Base::Literal::Email::Subject';
    $Para::Frame::CFG->{'email_class'} ||=
      'Rit::Base::Email';


    my $global_params =
    {
     rb              => bless( {}, 'Rit::Base'),
     find            => sub{ Rit::Base::Resource->find(@_) },
     get             => sub{ Rit::Base::Resource->get(@_) },
     set_one         => sub{ Rit::Base::Resource->set_one(@_) },
     find_set        => sub{ Rit::Base::Resource->find_set(@_) },
     new_search      => sub{ Rit::Base::Search->new(@_) },
     query_desig     => \&Rit::Base::Utils::query_desig,
     C               => Rit::Base::Constants->new,
     timediff        => \&Para::Frame::Utils::timediff,
     timeobj         => sub{ Rit::Base::Literal::Time->get( @_ ) },
     literal         => sub{ Rit::Base::Literal->new(@_) },
     parse_query_props => \&Rit::Base::Utils::parse_query_props,
     searchobj       => sub{ $Para::Frame::REQ->session->search_collection },
    };
    Para::Frame->add_global_tt_params( $global_params );

    # Adds hanlding of .js files
    #
    my $burner_plain = Para::Frame::Burner->get_by_type('plain');
    $burner_plain->add_ext('js');


    Rit::Base::Widget->on_configure();

    warn "Done adding hooks for Rit::Base\n";

    return 1;
}


#######################################################################

=head2 init_on_startup

=cut

sub init_on_startup
{
#    warn "init_on_startup\n";

    if( $ARGV[0] eq 'setup_db' or not $Rit::dbix->table('arc' ) )
    {
	Rit::Base::Setup->setup_db();
    }


    Rit::Base::Resource->on_startup();
#    warn "init_on_startup 2\n";
    Rit::Base::Literal::Class->on_startup();
#    warn "init_on_startup 3\n";
    Rit::Base::Constants->on_startup();
#    warn "init_on_startup 4\n";

    my $cfg = $Para::Frame::CFG;

    $cfg->{'rb_default_source'} ||= 'ritbase';
    $cfg->{'rb_default_read_access'} ||= 'public';
    $cfg->{'rb_default_write_access'} ||= 'sysadmin_group';

    foreach my $key (qw(rb_default_source rb_default_read_access
                        rb_default_write_access))
    {
	my $val = $cfg->{$key};
	unless( ref $val )
	{
	    $cfg->{$key} = Rit::Base::Resource->get_by_label($val);
	}
    }
#    warn "init_on_startup 5\n";

    $Rit::Base::IN_STARTUP = 0;

#    warn "calling on_ritbase_ready\n";
    Para::Frame->run_hook( $Para::Frame::REQ, 'on_ritbase_ready');
#    warn "done init_on_startup\n";
}


#######################################################################

=head2 Resource

Returns class object for L<Rit::Base::Resource>

=cut

sub Resource ()
{
    return 'Rit::Base::Resource';
}


######################################################################

=head2 Arc

Returns class object for L<Rit::Base::Arc>

=cut

sub Arc ()
{
    return 'Rit::Base::Arc';
}


######################################################################

=head2 Arc_Lim

Returns class object for L<Rit::Base::Arc::Lim>

=cut

sub Arc_Lim ()
{
    return 'Rit::Base::Arc::Lim';
}


######################################################################

=head2 Pred

Returns class object for L<Rit::Base::Pred>

=cut

sub Pred ()
{
    return 'Rit::Base::Pred';
}


######################################################################

=head2 Constants

Returns class object for L<Rit::Base::Constants>

=cut

sub Constants ()
{
    return 'Rit::Base::Constants';
}


######################################################################

=head2 Literal

Returns class object for L<Rit::Base::Literal>

=cut

sub Literal ()
{
    return 'Rit::Base::Literal';
}


######################################################################

=head2 on_done

  Runs after each request

=cut

sub on_done ()
{
    Rit::Base::Arc->unlock_all();
    Rit::Base::Resource->commit();
}


######################################################################

=head2 add_background_jobs

  Runs after each request

=cut

sub add_background_jobs
{
    my( $delta, $sysload ) = @_;

    if( keys %Rit::Base::Cache::Changes::Added or
	keys %Rit::Base::Cache::Changes::Updated or
	keys %Rit::Base::Cache::Changes::Removed )
    {
	$Para::Frame::REQ->add_job('run_code', 'send_cache_change',
				   \&send_cache_change);
    }
}


######################################################################

=head2 send_cache_change

=cut

sub send_cache_change
{
    my( $req ) = @_;

    my @added = keys %Rit::Base::Cache::Changes::Added;
    my @removed = keys %Rit::Base::Cache::Changes::Removed;
    my @updated;
    foreach my $id ( keys %Rit::Base::Cache::Changes::Updated )
    {
	next if $Rit::Base::Cache::Changes::Added{$id};
	next if $Rit::Base::Cache::Changes::Removed{$id};
	push @updated, $id;
    }

    %Rit::Base::Cache::Changes::Added = ();
    %Rit::Base::Cache::Changes::Updated = ();
    %Rit::Base::Cache::Changes::Removed = ();

    my $fork = $req->create_fork;
    if( $fork->in_child )
    {
	my @daemons = @{$Para::Frame::CFG->{'daemons'}};

	my @params;
	if( @added )
	{
	    push @params, 'added='.join(',',@added);
	}

	if( @updated )
	{
	    push @params, 'updated='.join(',',@updated);
	}

	if( @removed )
	{
	    push @params, 'removed='.join(',',@removed);
	}

	my $request = "update_cache?" . join('&', @params);

	foreach my $site (@daemons)
	{
	    my $daemon = $site->{'daemon'};
	    debug "Sending update to $site->{site}";

	    if( grep /$site->{'site'}/, keys %Para::Frame::Site::DATA )
	    {
		debug "  Skipping this site";
		next;
	    }

	    debug "Sending update_cache to $daemon";

	    eval
	    {
		$req->send_to_daemon( $daemon, 'RUN_ACTION',
				      \$request );
	    }
		or do
		{
		    debug(0,"  failed: $@");
		};
	}

	$fork->return();
    }
}


######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>
L<Rit::Base::Object>,
L<Rit::Base::Search>,
L<Rit::Base::Utils>

=cut
