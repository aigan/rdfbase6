#  $Id$  -*-cperl-*-
package Rit::Base::Email::IMAP;
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

Rit::Base::Email::IMAP

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
#use URI;
#use MIME::Words qw( decode_mimewords );
use IMAP::BodyStructure;
#use MIME::QuotedPrint qw(decode_qp);
#use MIME::Base64 qw( decode_base64 );
#use MIME::Types;
#use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
#use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch fqdn );
use Para::Frame::Utils qw( throw debug );
#use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs alfanum_to_id is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::IMAP::Folder;
use Rit::Base::Email::IMAP::Head;

use constant EA => 'Rit::Base::Literal::Email::Address';

use base qw( Rit::Base::Email::IMAP::Part );

#######################################################################

=head2 new_by_email

=cut

sub new_by_email
{
    my( $class, $email, $head ) = @_;

    my $imap_url = $email->first_prop('has_imap_url',undef,'not_removal')->plain;
    unless( $imap_url )
    {
	confess "Faild to get has_imap_url from ".$email->id;
    }


    $imap_url =~ /;UID=(\d+)/ or
      die "Couldn't extract uid from url $imap_url";
    my $uid = $1;

    my $part = bless
    {
     email => $email,
     head => $head,       # may be undef
     imap_url => $imap_url,
     uid => $uid,
    }, $class;
    weaken( $part->{'email'} );

    return $part;
}


#######################################################################

=head2 complete_head

=cut

sub complete_head
{
   return $_[0]->{'head'} ||=
      Rit::Base::Email::IMAP::Head->
	  new_by_uid( $_[0]->folder, $_[0]->uid );
}


#######################################################################

=head2 head

  $part->head()

Returns: The L<Rit::Base::Email::IMAP::Head> object

=cut

*head = \&complete_head;


#######################################################################

=head2 header

  $email->header( $field_name )

Returns: An array

=cut

sub header
{
    unless( $_[0]->{'head'} )
    {
	$_[0]->{'head'} = Rit::Base::Email::IMAP::Head->
	  new_by_uid( $_[0]->folder, $_[0]->uid );
    }

    # LIST CONTEXT
    return( $_[0]->{'head'}->header($_[1]) );
}


#######################################################################

=head2 folder

=cut

sub folder
{
    if( my $url_plain = $_[0]->{'imap_url'} )
    {
	return Rit::Base::Email::IMAP::Folder->get_by_url($url_plain);
    }

    confess "IMAP email without URL";
    return undef;
}


#######################################################################

=head2 exist

Is the content of this email availible?

=cut

sub exist
{
    my( $part ) = @_;

    unless( defined $part->{'exist'} )
    {
	my $folder = $part->folder;
	my $uid = $part->{'uid'};
	if( $folder->imap_cmd('message_uid',$uid) )
	{
	    $part->{'exist'} = 1;
	}
	else
	{
	    debug "Doesn't message $uid exist? $@";
	    $part->{'exist'} = 0;
	}
    }

    return $part->{'exist'};
}


#######################################################################

=head2 uid

=cut

sub uid
{
    return $_[0]->{'uid'};
}


#######################################################################

=head2 top

=cut

sub top
{
    return $_[0];
}


#######################################################################

=head2 generate_name

  $part->generate_name

Generates a non-unique message name for use for attatchemnts, et al

=cut

sub generate_name
{
    my( $part ) = @_;

    return  "email".$part->uid;
}


#######################################################################

=head2 url_path

  $part->url_path

=cut

sub url_path
{
    my( $part ) = @_;

    my $email = $part->email;
    my $nid = $email->id;

    my $subject = $part->head->parsed_subject->plain;

    my $safe = $part->filename_safe($subject,"message/rfc822");

    my $s = $Para::Frame::REQ->session
      or die "Session not found";
    $s->{'email_imap'}{$nid}{$safe} = '-';
    my $path = $safe;

    my $email_url = $email->url_path;
    return $email_url . $path;
}


#######################################################################
#
#=head2 body
#
#=cut
#
#sub body
#{
#    my( $part ) = @_;
#    return "<not found>" unless $part->exist;
#
#    my $uid = $part->uid;
#    return $part->folder->imap_cmd('body_string', $uid);
#}
#
#
#######################################################################

=head2 body_as_html

=cut

sub body_as_html
{
    my( $part ) = @_;

    return "<strong>not found</strong>" unless $part->exist;

    my $type = $part->type;
    my $renderer = $part->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }


    # Register email in session
    my $req = $Para::Frame::REQ;
    my $s = $req->session
      or die "Session not found";
    my $nid = $part->email->id;
    $s->{'email_imap'}{$nid} ||= {};

#    debug $part->desig;


    my $top_path = $part->url_path;
    my $msg = "<a href=\"$top_path\">Download email</a>\n";

    my $head_path = $part->email->url_path. ".head";
    $msg .= "| <a href=\"$head_path\">View Headers</a>\n";


    $msg .= $part->$renderer();

#    my $msg = &{$renderer}($email, $struct);

    if( keys %{$part->{'attatchemnts'}} )
    {
	$msg .= "<ol>\n";

	foreach my $att ( sort values %{$part->{'attatchemnts'}} )
	{
	    my $name = $att->filename || $att->generate_name;
	    my $desc = $att->description;

	    my $name_enc = CGI->escapeHTML($name);
	    my $desc_enc = CGI->escapeHTML($desc);

	    my $type = $att->type;
	    my $size_human = $att->size_human;

	    my $url_path = $att->url_path($name);
	    my $path = $att->path;

	    my $mouse_over =
	      "onmouseover=\"TagToTip('email_file_$nid/$path')\"";

	    my $desig = "<a href=\"$url_path\">$name_enc</a>";
	    if( $desc and ($desc ne $name ) )
	    {
		$desig .= "<br>\n$desc";
	    }

	    $msg .= "<li $mouse_over>$desig</li>\n";

	    ## Adding tooltip
	    $msg .= "<span id=\"email_file_$nid/$path\" style=\"display: none\">";
	    $msg .= "$name_enc<br>\n";
	    $msg .= "Type: $type<br>\n";
	    $msg .= "Size: $size_human<br>\n";
	    $msg .= "</span>";
	}
	$msg .= "</ol>\n";
    }

    return $msg;
}


#######################################################################

=head2 struct

=cut

sub struct
{
    my( $part ) = @_;

    if( $part->{'struct'} )
    {
	return $part->{'struct'};
    }

    my $folder = $part->folder;
    my $uid = $part->uid;

    my $res = $folder->imap_cmd('fetch', $uid,"bodystructure");

    do
    {
	shift @$res;
	die "No BODYSTRUCTURE found in response" unless scalar(@$res);
    } until( $res->[0] =~ /BODYSTRUCTURE/ );
    pop @$res;
    my $raw = join "", @$res;
    $raw =~ s/^\* \d+ FETCH \(UID \d+ BODYSTRUCTURE/(BODYSTRUCTURE/;
#    debug "Cleanded:\n$raw\n";

    my $struct = IMAP::BodyStructure->new( $raw );
    unless( $struct )
    {
	die "No struct returned for\n$raw";
    }

#    debug datadump $struct;

#    debug $part->part_desig( $struct );

    return $part->{'struct'} = $struct;
}


#######################################################################

=head2 charset_guess

=cut

sub charset_guess
{
    my( $part ) = @_;

    my $charset = $part->charset;

    unless( $charset )
    {
	if( $part->type =~ /^text\// )
	{
	    debug "Should guess charset from language";
	    debug "Falling back on Latin-1";
	    $charset = "iso-8859-1";
	}
    }

    return $charset;
}


#######################################################################

=head2 see

=cut

sub see
{
    my( $part ) = @_;

    my $uid = $part->uid;
    my $folder = $part->folder;

    debug "  Mark email $uid as seen";
    $folder->imap_cmd('see', $uid);
}


#######################################################################

=head2 unsee

=cut

sub unsee
{
    my( $part ) = @_;

    my $uid = $part->uid;

    debug "Mark email as unseen";
    my $folder = $part->folder;

    $folder->imap_cmd('unset_flag', "\\Seen", $uid);
    return 1;
}


#######################################################################

=head2 is_seen

=cut

sub is_seen
{
    my( $part ) = @_;

    my $uid = $part->uid;

    my $folder = $part->folder;
#    my $flags = $folder->imap->flags($uid)
#      or confess $folder->diag("Could not get flags of email $uid");
    my $flags = $folder->imap_cmd('flags', $uid);
    foreach my $flag ( @$flags )
    {
	if( $flag eq '\\Seen' )
	{
	    return 1;
	}
    }

    return 0;
}


#######################################################################

=head2 is_flagged

=cut

sub is_flagged
{
    my( $part ) = @_;

    my $uid = $part->uid;

    my $folder = $part->folder;
#    my $flags = $folder->imap->flags($uid)
#      or confess $folder->diag("Could not get flags of email $uid");
    my $flags = $folder->imap_cmd('flags', $uid);
    foreach my $flag ( @$flags )
    {
	if( $flag eq '\\Flagged' )
	{
	    return 1;
	}
    }

    return 0;
}


#######################################################################

1;
