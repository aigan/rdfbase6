package RDF::Base 6.96;
#=============================================================================
#
# AUTHOR
#		Jonas Liljegren		<jonas@paranormal.se>
#
# COPYRIGHT
#		Copyright (C) 2005-2022 Avisita AB.	 All Rights Reserved.
#
#		This module is free software; you can redistribute it and/or
#		modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use JSON;
use IMAP::BodyStructure 1.02;
use LWP::UserAgent;

use Para::Frame 2.14;
use Para::Frame::Utils qw( debug );
use Para::Frame::Reload;
use Para::Frame::Site;

use RDF::Base::Utils;
use RDF::Base::Object;
use RDF::Base::Node;
use RDF::Base::Undef;
use RDF::Base::Resource;
use RDF::Base::Arc;
use RDF::Base::Pred;
use RDF::Base::User;
use RDF::Base::Session;
use RDF::Base::L10N;
use RDF::Base::Widget;
use RDF::Base::Search::Collection;
use RDF::Base::Search::Result;
use RDF::Base::Literal::String; # Needed by RB::Utils
use RDF::Base::Class;
use RDF::Base::Setup;
use RDF::Base::Plugins;
use RDF::Base::Domain;
use RDF::Base::Email::Address;


=head1 NAME

RDF::Base - The ultimate database

=cut

=head1 DESCRIPTION

See L<RDF::Base::Object> for the baseclass for most classes.

=cut


# Used in RDF::Base::Resource->first_bless()
our %LOOKUP_CLASS_FOR =
	(
	 'RDF::Base::Resource'	 => 1,
	 'RDF::Base::User::Meta' => 1,
	);

our	 $IN_STARTUP = 1;						# Set to 0 after db init
our	 $VACUUM_ALL = 0;						# Only for initialization and repair

#########################################################################

BEGIN
{
	$Para::Frame::HOOK{'on_rdfbase_ready'} = [];
}

#########################################################################
################################	Constructors	#########################

=head1 Constructors

These can be called with the class name

=head2 init

=cut

sub init
{
	my( $this ) = @_;

	warn "Adding hooks for RDF::Base\n";

	# Just in case we temporarily switched to root and got an exception
	Para::Frame->add_hook('on_error_detect', sub
												{
													RDF::Base::User->revert_from_temporary_user();
													if ( $Para::Frame::U )
													{
														$Para::Frame::U->set_default_propargs(undef);
													}
												});

	Para::Frame->add_hook('on_startup', \&init_on_startup);

	# Can't unlock all arcs in the middle of an operation. Wait until
	# we are done. Also wait with resources...
	#
#		 Para::Frame->add_hook('before_db_commit', sub
#				{
#						RDF::Base::Resource->commit();
#						RDF::Base::Arc->unlock_all();
#				});

	Para::Frame->add_hook('after_db_rollback', sub
												{
													RDF::Base::Resource->rollback();
													RDF::Base::Arc->rollback();
													RDF::Base::Email::Address->rollback();
													RDF::Base::Domain->rollback();
												});

	Para::Frame->add_hook('done', \&on_done);

	Para::Frame->add_hook('busy_background_job', \&add_background_jobs);

	$Para::Frame::CFG->{'search_collection_class'} ||=
		'RDF::Base::Search::Collection';
	$Para::Frame::CFG->{'search_result_class'} ||=
		'RDF::Base::Search::Result';
	$Para::Frame::CFG->{'email_subject_class'} ||=
		'RDF::Base::Literal::Email::Subject';
	$Para::Frame::CFG->{'email_class'} ||=
		'RDF::Base::Email';
	$Para::Frame::CFG->{'daemons'} ||= [];



	my $global_params =
	{
	 rb							 => bless( {}, 'RDF::Base'),
	 find						 => sub{ RDF::Base::Resource->find(@_) },
	 get						 => sub{ RDF::Base::Resource->get(@_) },
	 create					 => sub{ RDF::Base::Resource->create(@_) },
	 set_one				 => sub{ RDF::Base::Resource->set_one(@_) },
	 find_set				 => sub{ RDF::Base::Resource->find_set(@_) },
	 new_search			 => sub{ RDF::Base::Search->new(@_) },
	 query_desig		 => \&RDF::Base::Utils::query_desig,
	 C							 => RDF::Base::Constants->new,
	 timediff				 => \&Para::Frame::Utils::timediff,
	 timeobj				 => sub{ RDF::Base::Literal::Time->get( @_ ) },
	 literal				 => sub{ RDF::Base::Literal->new(@_) },
	 parse_query_props => \&RDF::Base::Utils::parse_query_props,
	 searchobj			 => sub{ $Para::Frame::REQ->session->search_collection },
	 to_json				 => \&JSON::to_json,
	 from_json			 => \&JSON::from_json,
	 plugins				 => sub{ RDF::Base::Plugins->new(@_) },
	};
	Para::Frame->add_global_tt_params( $global_params );

	# Adds hanlding of .js files
	#
	my $burner_plain = Para::Frame::Burner->get_by_type('plain');
	$burner_plain->add_ext('js');


	RDF::Base::Widget->on_configure();

#		 warn "Done adding hooks for RDF::Base\n";

	return 1;
}


##############################################################################

=head2 init_on_startup

Sets up db if first run.

Calls on_startup() for a series of RB classes.

Calls L<RDF::Base::Setup/upgrade_db>.

Runs hook "on_rdfbase_ready" after init.

=cut

sub init_on_startup
{
#		 warn "init_on_startup\n";

	if ( ( $ARGV[0] and $ARGV[0] eq 'setup_db'
				 and $ARGV[1] and $ARGV[1] eq 'clear' )
			 or not $RDF::dbix->table('arc') )
	{
		RDF::Base::Setup->setup_db();
	}

	RDF::Base::Setup->upgrade_tables();
	RDF::Base::Resource->on_startup();
	RDF::Base::Literal->on_startup();
	RDF::Base::Literal::Class->on_startup();
	RDF::Base::Constants->on_startup();

	my $cfg = $Para::Frame::CFG;

	$cfg->{'rb_default_source'} ||= 'rdfbase';
	$cfg->{'rb_default_read_access'} ||= 'public';
	$cfg->{'rb_default_write_access'} ||= 'contentadmin_group';

	foreach my $key (qw(rb_default_source rb_default_read_access
											rb_default_write_access))
	{
		my $val = $cfg->{$key};
		unless( ref $val )
		{
			$cfg->{$key} = RDF::Base::Resource->get_by_label($val,{nonfatal => 1});
		}
	}


	RDF::Base::Setup->upgrade_db();

	RDF::Base::Class->on_startup();

	$RDF::Base::IN_STARTUP = 0;
	$RDF::Base::IN_SETUP_DB = 0;

	########################################

	Para::Frame->run_hook( $Para::Frame::REQ, 'on_rdfbase_ready');
}


##############################################################################

=head2 Resource

Returns class object for L<RDF::Base::Resource>

=cut

sub Resource ()
{
	return 'RDF::Base::Resource';
}


######################################################################

=head2 Arc

Returns class object for L<RDF::Base::Arc>

=cut

sub Arc ()
{
	return 'RDF::Base::Arc';
}


######################################################################

=head2 Arc_Lim

Returns class object for L<RDF::Base::Arc::Lim>

=cut

sub Arc_Lim ()
{
	return bless {}, 'RDF::Base::Arc::Lim';
}


######################################################################

=head2 Pred

Returns class object for L<RDF::Base::Pred>

=cut

sub Pred ()
{
	return 'RDF::Base::Pred';
}


######################################################################

=head2 Constants

Returns class object for L<RDF::Base::Constants>

=cut

sub Constants ()
{
	return 'RDF::Base::Constants';
}


######################################################################

=head2 Literal

Returns class object for L<RDF::Base::Literal>

See also L<RDF::Base::Utils/string>

=cut

sub Literal ()
{
	return 'RDF::Base::Literal';
}


######################################################################

=head2 Search_Collection

Returns class object for L<RDF::Base::Search::Colletion> or what was
specified by $Para::Frame::CFG->{'search_collection_class'}

=cut

sub Search_Collection ()
{
	return $Para::Frame::CFG->{'search_collection_class'};
}


######################################################################

=head2 on_done

	Runs after each request

=cut

sub on_done ()
{
	RDF::Base::Arc->unlock_all();
	RDF::Base::Resource->commit();
	$RDF::dbix->commit();
}


######################################################################

=head2 add_background_jobs

	Runs after each request

=cut

sub add_background_jobs
{
	my( $delta, $sysload ) = @_;

#		 debug "*******================************ May send_cache_change";
	if ( keys %RDF::Base::Cache::Changes::Added or
			 keys %RDF::Base::Cache::Changes::Updated or
			 keys %RDF::Base::Cache::Changes::Removed )
	{
		send_cache_change(undef);
#	debug "	 prepending job";
#	$Para::Frame::REQ->prepend_background_job('send_cache_change',
#							\&send_cache_change);
	}
}


######################################################################

=head2 send_cache_change

	send_cache_change()
	send_cache_change($req)

=cut

sub send_cache_change
{
	my( $req ) = @_;

	$req ||= $Para::Frame::REQ || Para::Frame::Request->new_bgrequest();

	my @added = keys %RDF::Base::Cache::Changes::Added;
	my @removed = keys %RDF::Base::Cache::Changes::Removed;
	my @updated;
	foreach my $id ( keys %RDF::Base::Cache::Changes::Updated )
	{
		next if $RDF::Base::Cache::Changes::Added{$id};
		next if $RDF::Base::Cache::Changes::Removed{$id};
		push @updated, $id;
	}

	%RDF::Base::Cache::Changes::Added = ();
	%RDF::Base::Cache::Changes::Updated = ();
	%RDF::Base::Cache::Changes::Removed = ();

	my $fork = $req->create_fork;
	if ( $fork->in_child )
	{
		my @daemons = @{$Para::Frame::CFG->{'daemons'}};

		my @params;
		if ( @added )
		{
			push @params, 'added='.join(',',@added);
		}

		if ( @updated )
		{
			push @params, 'updated='.join(',',@updated);
		}

		if ( @removed )
		{
			push @params, 'removed='.join(',',@removed);
		}

		my $server = sprintf("%s:%d",
												 Para::Frame::Site->get('default')->host,
												 $Para::Frame::CFG->{'port'});
		push @params, 'callback='.$server;

		my $params_joined = join('&', @params);

		foreach my $site (@daemons)
		{
			my $daemon = $site->{'daemon'};

			### TODO: check if port and IP is the same
			#
			if ( grep /$site->{'site'}/, keys %Para::Frame::Site::DATA )
			{
				debug "	 Skipping this site";
				next;
			}

			if ( my $rest = $site->{'rest'} )
			{
				my $host = $site->{'site'};
				my $protocol = $site->{'protocol'} || 'http';
				my $url = "$protocol://$host$rest/update_cache";
				debug "Sending update_cache to $url";
				my $ua = LWP::UserAgent->new;
				$ua->ssl_opts( verify_hostname => 0, SSL_verify_mode => 0x00 );
				my $res = $ua->post($url, Content => $params_joined);
				debug($res->content);
			}
			else
			{
				debug "Sending update_cache to $daemon";
				eval
				{
					my $request = "update_cache?" . $params_joined;
					$req->send_to_daemon( $daemon, 'RUN_ACTION',
																\$request );
				}
				or do
			{
				debug(0,"failed send_cache_change to $site->{site}: $@");
			};
			}
		}

		$fork->return();
	}
}


######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>
L<RDF::Base::Object>,
L<RDF::Base::Search>,
L<RDF::Base::Utils>

=cut
