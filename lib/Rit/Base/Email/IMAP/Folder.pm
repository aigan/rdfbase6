#  $Id$  -*-cperl-*-
package Rit::Base::Email::IMAP::Folder;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email::IMAP::Folder

=cut

use strict;
use Carp qw( croak confess cluck );
use Mail::IMAPClient;
use URI;
use URI::imap;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use Rit::Base::Literal::Time qw( now );
use Rit::Base::Utils qw( );
use Rit::Base::Email;

### DEFAULT CONFIG...
our $USER   = 'avisita.com_rg-tickets';
our $SERVER = 'skinner.ritweb.se';


our %FOLDERS;

#######################################################################

=head2 get

=cut

sub get
{
    my( $this, $val_in ) = @_;

    my( $cfg, $server, $user, $password, $foldername, $url );
    $val_in ||= {};
    if( UNIVERSAL::isa $val_in, 'HASH' )
    {
	$server = $val_in->{'server'} || $SERVER;
	$user   = $val_in->{'user'}   || $USER;
	$foldername = $val_in->{'foldername'} || 'INBOX';

	# look out for reserved chars in user
	my $url_str = "imap://$user\@$server/$foldername";

	if( my $folder = $FOLDERS{$url_str} )
	{
#	    debug "Found folder in cache";
	    $folder->awake;
	    return $folder;
	}

	$password = $val_in->{'password'};
	$url = URI->new($url_str);
    }
    else
    {
	$val_in =~ s/\/;UID=.*//;

	if( my $folder = $FOLDERS{$val_in} )
	{
#	    debug "Found folder in cache";
	    $folder->awake;
	    return $folder;
	}

	$url = URI->new( $val_in );

	$user = $url->userinfo;
	$server = $url->host;
	if( $url->path =~ /\/(.*)/ )
	{
	    $foldername = $1;
	}
	else
	{
	    die "Could not extract foldername from $val_in";
	}

    }

    $password ||= $Para::Frame::CFG->{imap_access}{$server}{$user}
      or throw 'IMAP', "Password for $user\@$server not found";

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


#######################################################################

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

    unless( $Para::Frame::CFG->{'check_email'} )
    {
	$email->unsee;
    }

    return $email;
}


#######################################################################

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

    if( $imap )
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
					Timeout => 1,
				       )
	    or throw 'IMAP', "Cannot connect to $server as $user: $@";
    }

    if( $imap->IsConnected )
    {
	if( $imap->IsAuthenticated )
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

#######################################################################

=head2 awake

=cut

sub awake
{
    my( $folder ) = @_;

    my $imap = $folder->{'imap'};

    if( my $idle = $folder->{'idle'} )
    {
	debug "Stops ideling ($idle)";
	$folder->{'idle'} = undef;

	if( $imap->IsUnconnected )
	{
	    $folder->connect;
	}
	elsif(not $imap->done( $idle ) )
	{
	    debug "Couldn't stop ideling: $@";
	    if( $imap->IsUnconnected )
	    {
		$folder->connect;
	    }
	}

	my $foldername = $folder->{'foldername'}
	  or throw 'IMAP', "Foldername missing from obj";
#	debug "Reselecting folder. (Short server memory?)";
	$imap->select($foldername)
	  or throw 'IMAP', $folder->diag("Could not select folder $foldername");
    }

    return $folder;
}


#######################################################################

=head2 idle

=cut

sub idle
{
    my( $folder ) = @_;

    return if $folder->{'idle'}; # Already in idle state

    # Check connection
    my $imap = $folder->{'imap'};
    if( $imap->IsConnected )
    {
	if( $folder->{'idle'} = $imap->idle )
	{
	    debug "Starts ideling ($folder->{'idle'})";
	}
	else
	{
	    debug $folder->diag("Couldn't idle");
	    debug "Disconnecting...";

	    # TODO: This call sometimes hangs. We should set a timelimit
	    $imap->disconnect;
	}
    }
    else
    {
	debug "Lost connection to ".$folder->sysdesig;
	debug "But keeps it that way for now...";
    }

    return $folder;
}


#######################################################################

=head2 imap

=cut

sub imap
{
    my( $folder ) = @_;

    # Check connection
    unless( $folder->{'imap'}->IsConnected )
    {
	debug "Lost connection to ".$folder->sysdesig;
	$folder->connect;
    }

#    debug "IMAP connected. Returning obj $folder->{'imap'}";

    return $folder->{'imap'};
}


#######################################################################

=head2 imap_cmd

=cut

sub imap_cmd
{
    my( $folder, $cmd ) = (shift, shift );

    my $imap = $folder->{'imap'};
    my $res = $imap->$cmd(@_);
    unless( defined $res )
    {
	if( $imap->IsUnconnected )
	{
	    $res = $folder->connect->imap->$cmd(@_);
	}

	if( $@ )
	{
	    throw 'IMAP', $folder->diag("Failed to run cmd $cmd(@_)");
	}
    }

    return $res;
}


#######################################################################

=head2 unseen_count

=cut

sub unseen_count
{
    return $_[0]->imap_cmd('unseen_count');
}


#######################################################################

=head2 unseen

  $folder->unseen

Returns: A L<Rit::Base::List> of messages, in order

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


#######################################################################

=head2 user_string

  $folder->user_string

=cut

sub user_string
{
    my( $folder ) = @_;

    return $folder->{'user'};
}


#######################################################################

=head2 foldername_raw_string

  $folder->foldername_raw_string

=cut

sub foldername_enc_string
{
    my( $folder ) = @_;

    return $folder->{'foldername'};
}


#######################################################################

=head2 url

Returns: imap url for the folder

=cut

sub url
{
    my( $folder ) = @_;

    return $folder->{'url'};
}


#######################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    return $_[0]->{'url'}->as_string;
}


#######################################################################

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
    if( $imap )
    {
	$err ||= $imap->LastError;
	$msg .= "Last command: ".join("",$imap->Results)."\n";
	$msg .= "State: ".$imap->State."\n";
    }

    return $msg;
}


#######################################################################


1;
