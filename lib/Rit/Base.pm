#  $Id$  -*-cperl-*-
package Rit::Base;
#=====================================================================
#
# DESCRIPTION
#   Ritbase package main class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
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
    $VERSION = "6.51";
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame;
use Para::Frame::Utils qw( debug );
use Para::Frame::Reload;

use Rit::Base::Resource;
use Rit::Base::Arc;
use Rit::Base::Pred;
use Rit::Base::User;
use Rit::Base::Session;
use Rit::Base::L10N;

# Used in Rit::Base::Resource->first_bless()
our %LOOKUP_CLASS_FOR =
    (
     Rit::Base::Resource   => 1,
     Rit::Base::User::Meta => 1,
    );

our %COLTYPE_num2name =
(
 1 => 'obj',
 2 => 'valfloat',
 3 => 'valbin',
 4 => 'valdate',
 5 => 'valtext',
 6 => 'value',
);


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

    Para::Frame->add_hook('on_error_detect', sub
			  {
			      Rit::Base::User->revert_from_temporary_user();
			      if( $Para::Frame::U )
			      {
				  $Para::Frame::U->set_default_propargs(undef);
			      }
			  });

    Para::Frame->add_hook('on_startup', \&init_on_startup);

    Para::Frame->add_hook('before_db_commit', sub
			  {
			      Rit::Base::Resource->commit();
			  });
    Para::Frame->add_hook('after_db_rollback', sub
			  {
			      Rit::Base::Resource->rollback();
			  });

    Para::Frame->add_hook('done', \&on_done);

    Para::Frame->add_hook('add_background_jobs', \&add_background_jobs);



    my $global_params =
    {
     find            => sub{ Rit::Base::Resource->find(@_) },
     get             => sub{ Rit::Base::Resource->get(@_) },
     new_search      => sub{ Rit::Base::Search->new(@_) },
     find_preds      => sub{ Rit::Base::Pred->find(@_) },
     find_rules      => sub{ Rit::Base::Rule->find(@_) },
     find_constants  => sub{ Rit::Base::Constants->find(@_) },
     query_desig     => \&Rit::Base::Utils::query_desig,
     C               => Rit::Base::Constants->new,
     timediff        => \&Para::Frame::Utils::timediff,
     timeobj         => sub{ Rit::Base::Time->get( @_ ) },
     parse_query_props => \&Rit::Base::Utils::parse_query_props,
    };
    Para::Frame->add_global_tt_params( $global_params );
}



#######################################################################

=head2 init_on_startup

=cut

sub init_on_startup
{
    Rit::Base::Constants->init;

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
	    $cfg->{$key} = Rit::Base::Resource->get_by_constant_label($val);
	}
    }

    Para::Frame->run_hook( $Para::Frame::REQ, 'on_ritbase_ready');
}

#######################################################################

=head2 Resource

Returns class object for Rit::Base::Resource

=cut

sub Resource ()
{
    return 'Rit::Base::Resource';
}

######################################################################

=head2 Arc

Returns class boject for Rit::Base::Arc

=cut

sub Arc ()
{
    return 'Rit::Base::Arc';
}

######################################################################

=head2 Pred

Returns class boject for Rit::Base::Pred

=cut

sub Pred ()
{
    return 'Rit::Base::Pred';
}

######################################################################

=head2 Constants

Returns class boject for Rit::Base::Constants

=cut

sub Constants ()
{
    return 'Rit::Base::Constants';
}

######################################################################

=head2 on_done

  Runs after each request

=cut

sub on_done ()
{
    # Releas arc locks
    Rit::Base::Arc->unlock_all();
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
