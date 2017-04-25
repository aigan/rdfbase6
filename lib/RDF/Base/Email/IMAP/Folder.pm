package RDF::Base::Email::IMAP::Folder;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::IMAP::Folder

=cut

use 5.010;
use strict;
use warnings;

no warnings 'portable';

use Carp qw( croak confess cluck );
use Mail::IMAPClient;
use URI;
use URI::imap;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use RDF::Base::Literal::Time qw( now );
use RDF::Base::Utils qw( );
use RDF::Base::Email;


our %FOLDERS;

##############################################################################

=head2 get

=cut

sub get
{
	my( $this, $args ) = @_;

	$args ||= {};

	unless( UNIVERSAL::isa $args, 'HASH' )
	{
		$args =
		{
		 user => $args,
		};
	}

	my $server = $args->{'server'} ||
		$Para::Frame::CFG->{'imap_access_default'}{'server'} ||
		die "No default server given";

	my $user = $args->{'user'} ||
		$Para::Frame::CFG->{'imap_access_default'}{'user'} ||
		die "No default user given";

	my $foldername = $args->{'foldername'} || 'INBOX';

	# look out for reserved chars in user
	my $url_str = "imap://$user\@$server/$foldername";

	return $this->get_by_url($url_str);
}


##############################################################################

=head2 get_by_url

=cut

sub get_by_url
{
	my( $this, $url_in ) = @_;

	$url_in =~ s/\/;UID=.*//;

	if ( my $folder = $FOLDERS{$url_in} )
	{
		$folder->awake;
		return $folder;
	}

	my $url = URI->new( $url_in );

	my $foldername;
	my $user = $url->userinfo;
	my $server = $url->host;
	if ( $url->path =~ /\/(.*)/ )
	{
		$foldername = $1;
	}
	else
	{
		die "Could not extract foldername from $url_in";
	}

	my $password = $Para::Frame::CFG->{imap_access}{$server}{$user};
	unless( $password )
	{
		$Para::Frame::REQ->result_message("Password for $user\@$server not found");
		return undef;
	}
#    cluck("No password") unless $password;
#    $password or throw 'IMAP', "Password for $user\@$server not found";

	my $folder = bless
	{
	 server => $server,
	 user => $user,
	 password => $password,
	 foldername => $foldername,
	 url => $url,
	}, $this;

	$folder->connect;

	$FOLDERS{$url->as_string} = $folder;

	return $folder;
}


##############################################################################

=head2 store

Store a message in the folder

=cut

sub create
{
	my( $folder, $args ) = @_;

	my $dataref = $args->{'dataref'};

	my $folder_name = $folder->foldername_enc_string;

	my $uid = $folder->imap_cmd('append',$folder_name, $$dataref);

	debug "Stored uid $uid in folder $folder_name";

	unless( $uid )
	{
		debug "Faild to store message in folder?";
	}


	debug "Reconnecting...";
	$folder->connect;

	my $email = $Para::Frame::CFG->{'email_class'}->
		get({
				 uid => $uid,
				 folder => $folder,
				});

	unless ( $Para::Frame::CFG->{'check_email'} )
	{
		$email->obj->unsee;
	}

	return $email;
}


##############################################################################

=head2 connect

=cut

sub connect
{
	my( $folder ) = @_;

	debug "Connecting to ".$folder->sysdesig;

	my $server = $folder->{'server'};
	my $user = $folder->{'user'};
	my $password = $folder->{'password'};
	my $foldername = $folder->{'foldername'};

	my $imap = $folder->{'imap'};

	if ( $imap and eval( $imap->can('IsConnected') ) )
	{
		$imap->disconnect if $imap->IsConnected;
		$folder->{'imap'} =
			$imap->connect or throw 'IMAP', "Could not reconnect: $@";
	}
	else
	{
		$folder->{'imap'} =
			$imap = Mail::IMAPClient->new(
																		Server => $server,
																		User    => $user,
																		Password=> $password,
																		Clear => 5,
																		Uid => 1,
																		Timeout => 3,
																		Keepalive => 1,
																	 )
	    or throw 'IMAP', "Cannot connect to $server as $user: $@";
	}

	if ( $imap->IsConnected )
	{
		if ( $imap->IsAuthenticated )
		{
	    # All good
		}
		else
		{
	    $imap->Showcredentials(1);
	    $imap->login or
	      throw 'IMAP', $folder->diag("Login failed for $user");
		}
	}
	else
	{
		throw 'IMAP', $folder->diag("Connection failed for $server");
	}

#    debug "Selecting folder $foldername";
	$imap->select($foldername)
		or throw 'IMAP', $folder->diag("Could not select folder $foldername");

	$folder->{'imap'} = $imap;
	$folder->{'idle'} = undef;

	return $folder;
}

##############################################################################

=head2 awake

=cut

sub awake
{
	my( $folder ) = @_;

	my $imap = $folder->{'imap'};

	if ( my $idle = $folder->{'idle'} )
	{
		debug "Stops ideling ($idle)";
		$folder->{'idle'} = undef;

		if ( $imap->IsUnconnected )
		{
	    $folder->connect;
		}
		elsif (not $imap->done( $idle ) )
		{
	    debug "Couldn't stop ideling: $@";
	    if ( $imap->IsUnconnected )
	    {
				$folder->connect;
	    }
		}

		$imap = $folder->{'imap'};

		my $foldername = $folder->{'foldername'}
			or throw 'IMAP', "Foldername missing from obj";
#	debug "Reselecting folder. (Short server memory?)";
		$imap->select($foldername)
			or throw 'IMAP', $folder->diag("Could not select folder $foldername");
	}

	return $folder;
}


##############################################################################

=head2 idle

=cut

sub idle
{
	my( $folder ) = @_;

	return if $folder->{'idle'};	# Already in idle state

	# Check connection
	my $imap = $folder->{'imap'};
	if ( $imap and $imap->IsConnected )
	{
		if ( $folder->{'idle'} = $imap->idle )
		{
	    debug "Starts ideling ($folder->{'idle'})";
		}
		elsif ( $imap->IsConnected ) # could change on $imap->idle
		{
	    debug $folder->diag("Couldn't idle");
	    debug "Disconnecting...";

	    eval
	    {
				local $SIG{ALRM} = sub { die "timeout\n" };
				alarm 2;
				$imap->disconnect;
				alarm 0;
	    };
	    if ( $@ )
	    {
				debug $folder->diag($@);
	    }
		}
		else
		{
	    debug "Lost connection to ".$folder->sysdesig;
	    debug "But keeps it that way for now...";
		}
	}
	else
	{
		debug "Lost connection to ".$folder->sysdesig;
		debug "But keeps it that way for now...";
	}

	return $folder;
}


##############################################################################

=head2 imap

=cut

sub imap
{
	my( $folder ) = @_;

	# Check connection
	unless ( $folder->{'imap'}->IsConnected )
	{
		debug "Lost connection to ".$folder->sysdesig;
		$folder->connect;
	}

#    debug "IMAP connected. Returning obj $folder->{'imap'}";

	return $folder->{'imap'};
}


##############################################################################

=head2 imap_cmd

=cut

sub imap_cmd
{
	my( $folder, $cmd ) = (shift, shift );

	my $imap = $folder->{'imap'};

	debug "imap_cmd $cmd " . join(' ', map((defined ? $_ : 'NUL'), @_));

	unless( $imap and
					eval{ $imap->can('IsConnected') } and
					$imap->IsConnected )
	{
		debug "Must reconnect";
		$folder->connect;
	}

	my $res = $imap->$cmd(@_);
	unless( defined $res )
	{
		if ( $imap->IsUnconnected )
		{
			debug "Reconnecting and resending";
	    $res = $folder->connect->imap->$cmd(@_);
		}

		if ( $@ )
		{
	    confess $folder->diag("Failed to run cmd $cmd(@_)");
#	    throw 'IMAP', $folder->diag("Failed to run cmd $cmd(@_)");
		}
	}

	return $res;
}


##############################################################################

=head2 unseen_count

=cut

sub unseen_count
{
	return $_[0]->imap_cmd('unseen_count');
}


##############################################################################

=head2 unseen

  $folder->unseen

Returns: A L<RDF::Base::List> of messages, in order

=cut

sub unseen
{
	my( $folder ) = @_;

	my $unseen = $folder->imap_cmd('unseen');
	my $mat =
		sub
	{
	  my $elem = $_[0]->{'_DATA'}[$_[1]];
	  debug "Getting uid elem $elem";
	  return $Para::Frame::CFG->{'email_class'}->
	    get({
					 uid => $elem,
					 folder => $folder,
					});
	};


	my $list = Para::Frame::List->new( $unseen,
																		 {
																			materializer => $mat,
																		 });

	return $list;
}


##############################################################################

=head2 message_count

=cut

sub message_count
{
	return $_[0]->imap_cmd('message_count');
}


##############################################################################

=head2 messages

  $folder->messages

Returns: A L<RDF::Base::List> of messages, in order

=cut

sub messages
{
	my( $folder ) = @_;

	my $messages = $folder->imap_cmd('messages');
	my $mat =
		sub
	{
	  my $elem = $_[0]->{'_DATA'}[$_[1]];
	  debug "Getting uid elem $elem";
	  return $Para::Frame::CFG->{'email_class'}->
	    get({
					 uid => $elem,
					 folder => $folder,
					});
	};


	my $list = Para::Frame::List->new( $messages,
																		 {
																			materializer => $mat,
																		 });

	return $list;
}


##############################################################################

=head2 user_string

  $folder->user_string

=cut

sub user_string
{
	my( $folder ) = @_;

	return $folder->{'user'};
}


##############################################################################

=head2 foldername_raw_string

  $folder->foldername_raw_string

=cut

sub foldername_enc_string
{
	my( $folder ) = @_;

	return $folder->{'foldername'};
}


##############################################################################

=head2 url

Returns: imap url for the folder

=cut

sub url
{
	my( $folder ) = @_;

	return $folder->{'url'};
}


##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
	return $_[0]->{'url'}->as_string;
}


##############################################################################

=head2 desig

=cut

sub desig
{
	return $_[0]->{'url'}->as_string;
}


##############################################################################

=head2 diag

Diagnostic message

=cut

sub diag
{
	my( $folder, $msg ) = @_;
	my $imap = $folder->{'imap'};
	my $err = $@;
	$msg ||= "";
	$msg .= ": $err\n";
	$msg .= "In folder ".$folder->sysdesig."\n";
	if ( $imap )
	{
		$err ||= $imap->LastError;
		$msg .= "Last command: ".join("",$imap->Results)."\n";
		$msg .= "State: ".$imap->State."\n";
	}

	return $msg;
}


##############################################################################

=head2 servername

=cut

sub servername
{
	my( $folder ) = @_;

	return $folder->{'server'};
}


##############################################################################

=head2 username

=cut

sub username
{
	my( $folder ) = @_;

	return $folder->{'user'};
}


##############################################################################

=head2 foldername

=cut

sub foldername
{
	my( $folder ) = @_;

	return $folder->{'foldername'};
}


##############################################################################

=head2 equals

=cut

sub equals
{
	my( $folder, $folder2 ) = @_;

	return( $folder->url eq $folder2->url );
}


##############################################################################


1;
