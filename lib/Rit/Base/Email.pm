#  $Id$  -*-cperl-*-
package Rit::Base::Email;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Template;
use Template::Context;
use URI;
use MIME::Words qw( decode_mimewords );
use IMAP::BodyStructure;
use MIME::QuotedPrint qw(decode_qp);
use MIME::Base64 qw( decode_base64 );
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Email::Classifier;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch fqdn );
use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs alphanum_to_id is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::IMAP;
use Rit::Base::Email::RB;
use Rit::Base::Email::RB::Head;
use Rit::Base::Email::Head;
use Rit::Base::Email::IMAP::Folder;
use Rit::Base::Email::IMAP::Head;

use constant EA => 'Rit::Base::Literal::Email::Address';

BEGIN
{
    $Email::Classifier::CLASS_HEADER = "Rit::Base::Email::Head";
}


#######################################################################

=head2 get

=cut

sub get
{
    my( $class, $args ) = @_;

    my $uid = $args->{'uid'} or croak "uid not given";
    my $folder = $args->{'folder'} or croak "folder not given";


    my $R = Rit::Base->Resource;

    my $head = Rit::Base::Email::IMAP::Head->new_by_uid( $folder, $uid );

    # Messge id without surrounding brackets
    my( $message_id ) = $head->header("message-id");
    unless( $message_id )
    {
	debug $folder->diag("Failed getting header");
	debug datadump($args,1);
    }
    $message_id =~ s/^<|>$//g;

    my $folder_url_string = $folder->url->as_string;
    my $url_string = "$folder_url_string/;UID=$uid";

    debug "SEARCHING for $url_string";

    my $emails = $R->find({
			   has_imap_url => $url_string,
			   is => $C_email,
			  },['not_removal']);


    my $email;

    if( $emails->size )
    {
	$email = $emails->get_first_nos;

	unless( $email->is($C_email) )  # May gotten removed (inactive)
	{
	    debug "Email ".$email->sysdesig." is removed from database";
	    debug "  $message_id";
	    debug "  $url_string";
	    debug "  REACTIVATING";

	    $email->add({
			 is => $C_email,
			 has_message_id => $message_id,
			 has_imap_url => $url_string,
			},
			{
			 activate_new_arcs => 1,
			});

#	    # Mark as read...
#	    $folder->imap_cmd('see', $uid);
	}

	$email->{'email_obj'} =
	  Rit::Base::Email::IMAP->new_by_email($email, $head);
    }
    else
    {
#	die "Creating email DISABLED"; ### DEBUG

	$email =
	  $R->create({
		      is => $C_email,
		      has_message_id => $message_id,
		      has_imap_url => $url_string,
		     },
		     {
		      activate_new_arcs => 1,
		     });

	$email->{'email_obj'} =
	  Rit::Base::Email::IMAP->new_by_email($email, $head);
    }

    return $email;
}


#######################################################################

=head2 url_path

TODO: Make path base a config

=cut

sub url_path
{
    my $home = $Para::Frame::REQ->site->home_url_path;
    my $nid = $_[0]->id;
    return "$home/admin/email/files/$nid/";
}


#######################################################################

=head2 folder

=cut

sub folder
{
    return $_[0]->obj->folder;
}


#######################################################################

=head2 message_id_plain

=cut

sub message_id_plain
{
    my( $email ) = @_;

    my $mid = $email->first_prop('has_message_id')->plain;
    unless( $mid )
    {
	if( $email->prop('has_imap_url' ) )
	{
	    $mid = $email->header("message-id");
	    if( $mid )
	    {
		$mid =~ s/^<|>$//g;
		my $root = Rit::Base::Resource->get_by_label('root');
		$Para::Frame::U->become_temporary_user($root);
		eval
		{
		    $email->update({'has_message_id' => $mid},
				   { activate_new_arcs => 1 });
		};
		$Para::Frame::U->revert_from_temporary_user;
		die $@ if $@;
	    }
	}
    }
    return $mid;
}


#######################################################################

=head2 in_reply_to

Returns: a L<Para::Frame::List> of L<Rit::Base::Email>. Replyto
elements not found will reside in the list as L<Rit::Base::Undef>.

=cut

sub in_reply_to
{
    my( $email ) = @_;

    my @emails;
    my( @in_reply_to ) = $email->header("in-reply-to");
    foreach my $mid ( @in_reply_to )
    {
	debug "In-Reply-To $mid";
	$mid =~ s/^<|>$//g;

	my $parent = Rit::Base::Resource->
	  find({
		has_message_id => $mid,
		is => $C_email,
	       })->get_first_nos;

	push @emails, $parent || is_undef;
    }

    return Rit::Base::List->new(\@emails);
}


#######################################################################

=head2 references

Returns: a L<Para::Frame::List> of L<Rit::Base::Email>. Reference
elements not found will reside in the list as L<Rit::Base::Undef>.

=cut

sub references
{
    my( $email ) = @_;

    my @emails;
    my( @in_reply_to ) = $email->header("references");
    foreach my $mid_string ( @in_reply_to )
    {
	$mid_string =~ s/^<|>$//g;
	foreach my $mid ( split />\s*</, $mid_string )
	{
	    debug "References $mid";

	    my $refered = Rit::Base::Resource->
	      find({
		    has_message_id => $mid,
		    is => $C_email,
		   })->get_first_nos;

	    push @emails, $refered || is_undef;
	}
    }

    return Rit::Base::List->new(\@emails);
}


#######################################################################

=head2 exist

Is the content of this email availible?

=cut

sub exist
{
    return $_[0]->obj->exist;
}


#######################################################################

=head2 obj

  $email->obj()

Returns: A specific subclass of L<Rit::Base::Email::Part>

=cut

sub obj
{
    unless( $_[0]->{'email_obj'} )
    {
	if( $_[0]->prop('has_imap_url', undef, ['not_removal'] ) )
	{
	    $_[0]->{'email_obj'} =
	      Rit::Base::Email::IMAP->new_by_email( $_[0] );
	}
	else
	{
	    $_[0]->{'email_obj'} =
	      Rit::Base::Email::RB->new_by_email( $_[0] );
	}
    }

    return $_[0]->{'email_obj'};
}



#######################################################################

=head2 header

  $email->header( $field_name )

Returns: An array ref

=cut

sub header
{
    return $_[0]->obj->body_header($_[1]);
}


#######################################################################

=head2 subject

Returns: A L<Rit::Base::Literal::Email::Subject>

=cut

sub subject
{
    return  $_[0]->{'email_subject'} ||=
      $_[0]->obj->body_head->parsed_subject;
}


#######################################################################

=head2 date

=cut

sub date
{
    return $_[0]->{'email_date'} ||=
      $_[0]->obj->body_head->parsed_date;
}


#######################################################################

=head2 from

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub from
{
    return $_[0]->{'email_from'} ||=
      $_[0]->obj->body_head->parsed_address('from');
}


#######################################################################

=head2 sender

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub sender
{
    unless( defined $_[0]->{'email_sender'} )
    {
	return $_[0]->{'email_sender'} =
	  $_[0]->obj->body_head->parsed_address('sender');
    }
    return $_[0]->{'email_sender'};
}


#######################################################################

=head2 to

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub to
{
    return $_[0]->{'email_to'} ||=
      $_[0]->obj->body_head->parsed_address('to');
}


#######################################################################

=head2 bcc

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub bcc
{
    unless( defined $_[0]->{'email_bcc'} )
    {
	return $_[0]->{'email_bcc'} =
	  $_[0]->obj->body_head->parsed_address('bcc');
    }
    return $_[0]->{'email_bcc'};
}


#######################################################################

=head2 cc

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub cc
{
    unless( defined $_[0]->{'email_cc'} )
    {
	return $_[0]->{'email_cc'} =
	  $_[0]->obj->body_head->parsed_address('cc');
    }
    return $_[0]->{'email_cc'};
}


#######################################################################

=head2 reply_to

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub reply_to
{
    unless( defined $_[0]->{'email_reply_to'} )
    {
	return $_[0]->{'email_reply_to'} =
	  $_[0]->obj->body_head->parsed_address('reply-to');
    }
    return $_[0]->{'email_reply_to'};
}


#######################################################################

=head2 body

  $email->body

Returns: a ref to the string of the decoded body.

=cut

sub body
{
    return $_[0]->obj->body_part->body;
}


#######################################################################

=head2 as_html

  $email->as_html

Return: the head and body presented as html

=cut

sub as_html
{
    return $_[0]->obj->as_html;
}


#######################################################################

=head2 body_as_html

  $email->body_as_html

Return: the string of the body presented as html

=cut

sub body_as_html
{
    return $_[0]->obj->body_as_html;
}


#######################################################################

=head2 part

=cut

sub part
{
    my( $email, $path ) = @_;

    return $email->obj->new_by_path( $path );
}


#######################################################################

=head2 vacuum

Reprocesses email after arc vacuum

=cut

sub vacuum
{
    my( $email ) = @_;

    $email = $email->Rit::Base::Resource::vacuum;
    $email->process;
    return $email;
}


#######################################################################

=head2 process

=cut

sub process
{
    my( $email ) = @_;

    die "not implemented";
}


#######################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $email ) = @_;

    return sprintf "Email %d: %s",
      $email->id, $email->obj->sysdesig;
}

#######################################################################

=head2 desig

=cut

sub desig
{
    my( $email ) = @_;

    if( $email->exist )
    {
	#my $from = $email->from->plain;
	my $date = $email->date->plain || '<no date>';
	my $subject = $email->subject->plain || '<no subject>';
	return "$date: $subject";
    }
    else
    {
	return "<deleted>";
    }
}


#######################################################################

=head2 send

Send the e-mail.  Sets sent date.

Supported args are:

  redirect: true for setting header for redirecting the email. Must be
            used if using proxy and to header differs from reciever

=cut

sub send
{
    my( $email, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    die "implement me";

    return "Email sent";
}


#######################################################################
#
#=head2 on_bless
#
#=cut
#
#sub on_bless
#{
#    $_[0]->reset_cache;
#}
#
#######################################################################
#
#=head2 on_unbless
#
#=cut
#
#sub on_unbless
#{
#    $_[0]->reset_cache;
#}
#
#######################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    $_[0]->reset_email_cache;
}

#######################################################################

=head2 on_arc_del

=cut

sub on_arc_del
{
    $_[0]->reset_email_cache;
}

#######################################################################

=head2 init

=cut

sub init
{
    $_[0]->reset_email_cache;
    return $_[0];
}

#######################################################################

=head2 reset_email_cache

=cut

sub reset_email_cache
{
#    debug "Resetting cached properties for email";

    my @keys = keys %{$_[0]};

    foreach my $key (@keys)
    {
	if( $key =~ /^email_/ )
	{
	    delete $_[0]->{$key};
	}
    }
}

#######################################################################

1;
