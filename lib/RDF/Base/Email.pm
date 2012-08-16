package RDF::Base::Email;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use constant EA => 'RDF::Base::Literal::Email::Address';

use Carp qw( croak confess cluck );
use Template;
use Template::Context;
use URI;
#use CGI;

use Email::Classifier;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch fqdn );
use Para::Frame::L10N qw( loc );
use Para::Frame::List;
use Para::Frame::Email::Sending;

use RDF::Base;
use RDF::Base::Utils qw( parse_propargs alphanum_to_id is_undef );
use RDF::Base::Constants qw( $C_email );
use RDF::Base::Literal::String;
use RDF::Base::Literal::Time qw( now ); #);
use RDF::Base::Literal::Email::Address;
use RDF::Base::Literal::Email::Subject;
use RDF::Base::Email::IMAP;
use RDF::Base::Email::RB;
use RDF::Base::Email::RB::Head;
use RDF::Base::Email::Head;
use RDF::Base::Email::IMAP::Folder;
use RDF::Base::Email::IMAP::Head;
use RDF::Base::Renderer::Email::From_email;

BEGIN
{
    $Email::Classifier::CLASS_HEADER = "RDF::Base::Email::Head";
}


##############################################################################

=head2 get

=cut

sub get
{
    my( $class, $args ) = @_;

    my $uid = $args->{'uid'} or croak "uid not given";
    my $folder = $args->{'folder'} or croak "folder not given";


    my $R = RDF::Base->Resource;

    my $head = RDF::Base::Email::IMAP::Head->new_by_uid( $folder, $uid );

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

    my $email;
    my $by_mid = 0;


    debug "SEARCHING for $url_string";
    my $emails = $R->find({
			   has_imap_url => $url_string,
			   is => $C_email,
			  },['not_removal']);

    unless( $emails->size )
    {
        debug "SEARCHING for $message_id";
        $emails = $R->find({
                            has_message_id => $message_id,
                            is => $C_email,
                           },['not_removal']);
        $by_mid = 1;
    }

    if( $emails->size )
    {
	$email = $emails->get_first_nos;
    }

    if( $email )
    {
        if( $by_mid )
        {
            $email->update({has_imap_url=>$url_string},{activate_new_arcs => 1});
        }

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
    }
    else
    {
	$email =
	  $R->create({
		      is => $C_email,
		      has_message_id => $message_id,
		      has_imap_url => $url_string,
		     },
		     {
		      activate_new_arcs => 1,
		     });
    }

    $email->{'email_obj'} =
      RDF::Base::Email::IMAP->new_by_email($email, $head);

    return $email;
}


##############################################################################

=head2 url_path

TODO: Make path base a config

=cut

sub url_path
{
    my $home = $Para::Frame::REQ->site->home_url_path;
    my $nid = $_[0]->id;
    return "$home/admin/email/files/$nid/";
}


##############################################################################

=head2 folder

=cut

sub folder
{
    return $_[0]->obj->folder;
}


##############################################################################

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
		my $root = RDF::Base::Resource->get_by_label('root');
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


##############################################################################

=head2 in_reply_to

Returns: a L<Para::Frame::List> of L<RDF::Base::Email>. Replyto
elements not found will reside in the list as L<RDF::Base::Undef>.

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

	my $parent = RDF::Base::Resource->
	  find({
		has_message_id => $mid,
		is => $C_email,
	       })->get_first_nos;

	push @emails, $parent || is_undef;
    }

    return RDF::Base::List->new(\@emails);
}


##############################################################################

=head2 references

Returns: a L<Para::Frame::List> of L<RDF::Base::Email>. Reference
elements not found will reside in the list as L<RDF::Base::Undef>.

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

	    my $refered = RDF::Base::Resource->
	      find({
		    has_message_id => $mid,
		    is => $C_email,
		   })->get_first_nos;

	    push @emails, $refered || is_undef;
	}
    }

    return RDF::Base::List->new(\@emails);
}


##############################################################################

=head2 exist

Is the content of this email availible?

=cut

sub exist
{
    if( my $obj = $_[0]->obj )
    {
	return $obj->exist;
    }

    return 0;
}


##############################################################################

=head2 obj

  $email->obj()

Returns: A specific subclass of L<RDF::Base::Email::Part>

=cut

sub obj
{
    unless( $_[0]->{'email_obj'} )
    {
	if( $_[0]->prop('has_imap_url', undef, ['not_removal'] ) )
	{
	    $_[0]->{'email_obj'} =
	      RDF::Base::Email::IMAP->new_by_email( $_[0] );
	}
	elsif( $_[0]->prop('email_body', undef, ['not_removal'] ) )
	{
	    $_[0]->{'email_obj'} =
	      RDF::Base::Email::RB->new_by_email( $_[0] );
	}
	elsif( $_[0]->prop('has_email_body_template_email',
			   undef, ['not_removal'] ) )
	{
	    $_[0]->{'email_obj'} =
	      RDF::Base::Email::RB->new_by_email( $_[0] );
	}
	else
	{
	    $_[0]->{'email_obj'} = is_undef;
	}
    }

    return $_[0]->{'email_obj'};
}



##############################################################################

=head2 header

  $email->header( $field_name )

Returns: An array ref

=cut

sub header
{
    return $_[0]->obj->header($_[1]);
}


##############################################################################

=head2 subject

Returns: A L<RDF::Base::Literal::Email::Subject>

=cut

sub subject
{
    return  $_[0]->{'email_subject'} ||=
      $_[0]->obj->head->parsed_subject;
}


##############################################################################

=head2 date

The date the email was sent

Returns: A L<RDF::Base::Time>

=cut

sub date
{
    return $_[0]->{'email_date'} ||=
      $_[0]->obj->head->parsed_date;
}


##############################################################################

=head2 from

Returns: a L<Para::Frame::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub from
{
    return $_[0]->{'email_from'} ||=
      $_[0]->obj->head->parsed_address('from');
}


##############################################################################

=head2 sender

Returns: a L<Para::Frame::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub sender
{
    unless( defined $_[0]->{'email_sender'} )
    {
	return $_[0]->{'email_sender'} =
	  $_[0]->obj->head->parsed_address('sender');
    }
    return $_[0]->{'email_sender'};
}


##############################################################################

=head2 to

Returns: a L<Para::Frame::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub to
{
    return $_[0]->{'email_to'} ||=
      $_[0]->obj->head->parsed_address('to');
}


##############################################################################

=head2 count_to

Returns: The number of to addresses

=cut

sub count_to
{
    debug "Returning the count of to";
    my $cnt = $_[0]->obj->head->count_to();
    debug "counted $cnt";
    return $cnt;
}


##############################################################################

=head2 bcc

Returns: a L<Para::Frame::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub bcc
{
    unless( defined $_[0]->{'email_bcc'} )
    {
	return $_[0]->{'email_bcc'} =
	  $_[0]->obj->head->parsed_address('bcc');
    }
    return $_[0]->{'email_bcc'};
}


##############################################################################

=head2 cc

Returns: a L<Para::Frame::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub cc
{
    unless( defined $_[0]->{'email_cc'} )
    {
	return $_[0]->{'email_cc'} =
	  $_[0]->obj->head->parsed_address('cc');
    }
    return $_[0]->{'email_cc'};
}


##############################################################################

=head2 reply_to

Returns: a L<Para::Frame::List> of L<RDF::Base::Literal::Email::Address>

=cut

sub reply_to
{
    unless( defined $_[0]->{'email_reply_to'} )
    {
	return $_[0]->{'email_reply_to'} =
	  $_[0]->obj->head->parsed_address('reply-to');
    }
    return $_[0]->{'email_reply_to'};
}


##############################################################################

=head2 body

  $email->body

Returns: a ref to the string of the decoded body.

=cut

sub body
{
    return $_[0]->obj->body;
}


##############################################################################

=head2 as_html

  $email->as_html

Return: the head and body presented as html

=cut

sub as_html
{
    return $_[0]->obj->as_html;
}


##############################################################################

=head2 body_as_html

  $email->body_as_html

Return: the string of the body presented as html

=cut

sub body_as_html
{
    return $_[0]->obj->body_as_html;
}


##############################################################################

=head2 attachments_as_html

  $email->attachments_as_html

=cut

sub attachments_as_html
{
    return $_[0]->obj->attachments_as_html;
}


##############################################################################

=head2 body_extract

  $email->body_extract

Return: the string of an extract of the body

=cut

sub body_extract
{
    return $_[0]->obj->body_extract;
}


##############################################################################

=head2 part

=cut

sub part
{
    my( $email, $path ) = @_;

    return $email->obj->new_by_path( $path );
}


##############################################################################

=head2 raw_part

=cut

sub raw_part
{
    my( $email, $path ) = @_;

    return $email->obj->raw_part;
}


##############################################################################

=head2 match

=cut

sub match
{
    return shift->obj->match(@_);
}


##############################################################################

=head2 vacuum

Reprocesses email after arc vacuum

=cut

sub vacuum
{
    my( $email ) = @_;

    $email = $email->RDF::Base::Resource::vacuum;
    $email->process;
    return $email;
}


##############################################################################

=head2 process

=cut

sub process
{
    my( $email ) = @_;

    die "not implemented";
}


##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $email ) = @_;

    if( my $obj = $email->obj )
    {
	return sprintf "Email %d: %s",
	  $email->id, $email->obj->sysdesig;
    }
    elese
    {
	return "Email ".$email->id;
    }
}

##############################################################################

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


##############################################################################

=head2 send

  $email->send( \%args )

Send the e-mail.  Sets sent date.

Supported args are:

  redirect: true for setting header for redirecting the email. Must be
            used if using proxy and to header differs from reciever


  params: extra params for the email template

=cut

sub send
{
    my( $email, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $esp_in = $args->{'params'};
    my $es = Para::Frame::Email::Sending->new($esp_in);
    my $esp = $es->params;
    my $now = now();

    $esp->{'from'}      = $email->from->get_first_nos;

    my $to_list = $email->list( 'email_to', undef, $args );
    my $to_obj_list = $email->list( 'email_to_obj', undef, $args );

    my $first_to = $to_list->get_first_nos;
    $first_to ||= $to_obj_list->get_first_nos->email_main;

    if( $email->prop('has_imap_url', undef, $args ) )
    {
	my $uid = $email->obj->uid;
	my $message_string = $email->folder->imap_cmd('message_string', $uid);

	if( $args->{'redirect'} )
	{
	    my $mid = Para::Frame::Email::Sending->generate_message_id({time=>$now});
	    my $useragent = "ParaFrame/$Para::Frame::VERSION (RDFbase/$RDF::Base::VERSION)";
	    my $datestr = $now->internet_date;

	    my $from = $Para::Frame::REQ->user->email;
	    $from ||= EA->new($Para::Frame::CFG->{'email'});

	    unless( $first_to )
	    {
		throw 'validation', "No recipient given";
	    }

	    my $extra = "";
	    $extra .= "Resent-From: $from\n";
	    $extra .= "Resent-To: $first_to\n";
	    $extra .= "Resent-Date: $datestr\n";
	    $extra .= "Resent-Message-Id: <$mid>\n";
	    $extra .= "Resent-User-Agent: $useragent\n";

	    $message_string = $extra . $message_string;
	}


	$es->renderer->set_dataref( \$message_string );
    }
    elsif( $email->prop('email_body', undef, $args ) )
    {
	$esp->{'plaintext'} = $email->email_body;
	$esp->{'reply_to'}  = $email->email_reply_to;
	$esp->{'subject'}   = $email->email_subject;
	$esp->{'template'}  = 'plaintext.tt';
    }
    elsif( my $te = $email->first_prop('has_email_body_template_email',
				       undef, $args ) )
    {
	$esp->{'reply_to'}  = $email->email_reply_to;
	$esp->{'subject'}   = $email->email_subject;

	debug "Adding email as a template";

	my $rend = RDF::Base::Renderer::Email::From_email->
	  new({ template => $te, params => $esp });

	$es->{'renderer'}  = $rend;
    }
    else
    {
	throw 'validation', "Email has no body";
    }

    my $req = $Para::Frame::REQ;
    #debug datadump($email, 3);

    debug "Sending email";

    my( $to, $to_err ) = $to_list->get_first;
    while( !$to_err )
    {
	debug "To $to";
	eval {
	    $es->send_by_proxy({%$args, to => $to });
	};
	$req->may_yield;
	( $to, $to_err ) = $to_list->get_next;
    }

    $to_obj_list->reset;
    my( $to_obj, $to_obj_err ) = $to_obj_list->get_first;
    while( !$to_obj_err )
    {
	my $to = $to_obj->email_main;
	debug "To $to";

	unless( $to_obj_list->count % 100 )
	{
	    $req->note("Sent email ".$to_obj_list->count);
	    die "cancelled" if $req->cancelled;
	}

	eval {
	    $es->send_by_proxy({%$args,
				to => $to,
				to_obj => $to_obj,
			       });
	};
	$req->may_yield;
	( $to_obj, $to_obj_err ) = $to_obj_list->get_next;
    }

    my( @good ) = $es->good;

    if( @good )
    {
	$email->add({ email_sent => now() }, {%$args, activate_new_arcs=>1});
    }
    else
    {
	debug "No email sent";
	my( @bad ) = $es->bad;
	debug "Couldn't send to @bad" if @bad;
	debug $es->error_msg;
	debug $@ if $@;
	if( $req->{'result'} )
	{
	    $req->{'result'}->exception if $@;
	    if( $es->error_msg )
	    {
		$req->{'result'}->error('email',$es->error_msg);
	    }
	}
	return 0;
    }


    $res->autocommit;

    return 1;
}


##############################################################################

=head2 validate_as_template

  $email->validate_as_template( \%args )

to_obj

=cut

sub validate_as_template
{
    my( $email, $args_in ) = @_;
    my( $args, $arclim, $res ) = parse_propargs($args_in);

    my $esp_in = $args->{'params'};
    my $es = Para::Frame::Email::Sending->new($esp_in);
    my $esp = $es->params;
    my $now = now();

    $esp->{'from'}      = $email->from->get_first_nos;

    my $to_list = $email->list( 'email_to', undef, $args );
    my $to_obj_list = $email->list( 'email_to_obj', undef, $args );

    my $to_obj = $to_obj_list->get_first_nos || $args->{'to_obj'};
    my $to = $to_obj->first_prop('email_main');

    $esp->{'reply_to'}  = $email->email_reply_to;
    $esp->{'subject'}   = $email->email_subject || "Test subject";

    my $rend = RDF::Base::Renderer::Email::From_email->
      new({ template => $email, params => $esp });

    $es->{'renderer'}  = $rend;

    my $from_addr = Para::Frame::Email::Address->parse( $esp->{'from'} );
    $from_addr or throw('mail', "Failed to parse address $esp->{'from'}\n");
    $esp->{'from_addr'} = $from_addr;
    $esp->{'envelope_from_addr'} = $from_addr;
    my( $to_addr ) = Para::Frame::Email::Address->parse( $to );
    $to_addr or throw('mail',"Failed parsing $to\n");

    my $dataref = $es->renderer->render_message($to_addr);
    return 1;
}


##############################################################################
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
##############################################################################
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
##############################################################################

=head2 on_arc_add

=cut

sub on_arc_add
{
    $_[0]->reset_email_cache;
}

##############################################################################

=head2 on_arc_del

=cut

sub on_arc_del
{
    $_[0]->reset_email_cache;
}

##############################################################################

=head2 init

=cut

sub init
{
    $_[0]->reset_email_cache;
    return $_[0];
}

##############################################################################

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

##############################################################################

1;
