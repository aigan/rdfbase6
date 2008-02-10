#  $Id$  -*-cperl-*-
package Rit::Base::Email;
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
use MIME::Types;
use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch fqdn );
use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs alfanum_to_id is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::Header;
use Rit::Base::Email::Classifier::Bounce;
use Rit::Base::Email::Classifier::Vacation;

use constant EA => 'Rit::Base::Literal::Email::Address';

#######################################################################

=head2 get

=cut

sub get
{
    my( $class, $args ) = @_;

    my $uid = $args->{'uid'} or croak "uid not given";
    my $folder = $args->{'folder'} or croak "folder not given";


    my $R = Rit::Base->Resource;

    my $headers = Rit::Base::Email::Header->new_by_uid( $folder, $uid );

#    my $headers_in = $folder->imap_cmd('parse_headers',$uid,'ALL');
#    my $headers = $class->parse_headers( $headers_in );

    # Messge id without surrounding brackets
    my( $message_id ) = $headers->header("message-id");
    unless( $message_id )
    {
	debug $folder->diag("Failed getting header");
	debug datadump($args,1);
    }
    $message_id =~ s/^<|>$//g;

    debug "SEARCHING for Message-ID $message_id";

    my $folder_url_string = $folder->url->as_string;
    my $url_string = "$folder_url_string/;UID=$uid";

    my $emails = $R->find({
			   has_message_id => $message_id,
			   is => $C_email,
			  });

    unless( $emails->size )
    {
	$emails = $R->find({
			    has_imap_url => $url_string,
			    is => $C_email,
			   });
    }

    my $email;

    if( $emails->size )
    {
	$email = $emails->get_first_nos;
	$email->{'email_headers'} = $headers;
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

	$email->{'email_headers'} = $headers;
	$email->process;
    }

    return $email;
}


#######################################################################

=head2 folder

=cut

sub folder
{
    my( $email ) = @_;

    if( my $url = $email->first_prop('has_imap_url') )
    {
	return Rit::Base::Email::Folder->get($url->plain);
    }
    else
    {
	return undef;
    }
}


#######################################################################

=head2 uid_plain

=cut

sub uid_plain
{
    my( $email ) = @_;

    unless( $email->{'email_uid_plain'} )
    {
	my $url_str = $email->first_prop('has_imap_url')->plain;
	$url_str =~ /;UID=(\d+)/ or
	  die "Couldn't extract uid from url $url_str";
	$email->{'email_uid_plain'} = $1;
    }

    return $email->{'email_uid_plain'} ;
}


#######################################################################

=head2 uid

=cut

sub uid
{
    my( $email ) = @_;

    unless( $email->{'email_uid'} )
    {
	$email->{'email_uid'} = Rit::Base::Literal::String->new($email->uid_plain);
    }

    return $email->{'email_uid'} ;
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
	    $mid = $email->header("message-id")->[0];
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
    my $in_reply_to = $email->header("in-reply-to");
    foreach my $mid ( @$in_reply_to )
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
    my $in_reply_to = $email->header("references");
    foreach my $mid_string ( @$in_reply_to )
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

=cut

sub exist
{
    my( $email ) = @_;

    unless( defined $email->{'email_exist'} )
    {
	if( $email->prop('has_imap_url' ) )
	{
	    my $folder = $email->folder;
	    my $uid = $email->uid_plain;
	    if( $folder->imap_cmd('message_uid',$uid) )
	    {
		$email->{'email_exist'} = 1;
	    }
	    else
	    {
		debug "Doesn't message $uid exist? $@";
		$email->{'email_exist'} = 0;
	    }
	}
	else
	{
	    $email->{'email_exist'} = 1;
	}
    }

    return $email->{'email_exist'};
}


#######################################################################

=head2 headers

  $email->headers()

Returns: The L<Rit::Base::Email::Header> object

=cut

sub headers
{
    unless( $_[0]->{'email_headers'} )
    {
	$_[0]->{'email_headers'} = Rit::Base::Email::Header->
	  new_by_uid( $_[0]->folder, $_[0]->uid_plain );
    }
    return $_[0]->{'email_headers'};
}


#######################################################################

=head2 header

  $email->header( $field_name )

Returns: An array ref

=cut

sub header
{
    unless( $_[0]->{'email_headers'} )
    {
	$_[0]->{'email_headers'} = Rit::Base::Email::Header->
	  new_by_uid( $_[0]->folder, $_[0]->uid_plain );
    }

    # LIST CONTEXT
    return([ $_[0]->{'email_headers'}->header($_[1]) ]);
}


#######################################################################

=head2 subject

Returns: A L<Rit::Base::Literal::String>

=cut

sub subject
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_subject'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_subject'} =
	      $email->headers->parsed_subject;
	}
	return $email->{'email_subject'};
    }
    else
    {
	return $email->prop('email_subject');
    }
}


#######################################################################

=head2 date

=cut

sub date
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_date'} )
	{
	    return is_undef unless $email->exist;
	    my $date_raw = $email->header("date")->[0];
	    eval
	    {
		$email->{'email_date'} = Rit::Base::Literal::Time->get( $date_raw );
	    };
	    if( $@ )
	    {
		debug $@;
		$email->{'email_date'} = is_undef;
	    }
	}
	return $email->{'email_date'};
    }
    else
    {
	return $email->prop('email_sent');
    }
}


#######################################################################

=head2 from

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub from
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_from'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_from'} =
	      $email->headers->parsed_address('from');
	}
	return $email->{'email_from'};
    }
    else
    {
	return $email->prop('email_from');
    }
}


#######################################################################

=head2 sender

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub sender
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_sender'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_sender'} =
	      $email->headers->parsed_address('sender');
	}
	return $email->{'email_sender'};
    }
    else
    {
	return Para::Frame::List->new_empty;
    }
}


#######################################################################

=head2 to

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub to
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_to'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_to'} =
	      $email->headers->parsed_address('to');
	}
	return $email->{'email_to'};
    }
    else
    {
	return $email->prop('email_to');
    }
}


#######################################################################

=head2 bcc

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub bcc
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_bcc'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_bcc'} =
	      $email->headers->parsed_address('bcc');
	}
	return $email->{'email_bcc'};
    }
    else
    {
	return $email->prop('email_bcc');
    }
}


#######################################################################

=head2 cc

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub cc
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_cc'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_cc'} =
	      $email->headers->parsed_address('cc');
	}
	return $email->{'email_cc'};
    }
    else
    {
	return '';#$email->prop('email_cc');
    }
}


#######################################################################

=head2 reply_to

Returns: a L<Para::Frame::List> of L<Rit::Base::Literal::Email::Address>

=cut

sub reply_to
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_reply_to'} )
	{
	    return is_undef unless $email->exist;
	    $email->{'email_reply_to'} =
	      $email->headers->parsed_address('reply-to');
	}
	return $email->{'email_reply_to'};
    }
    else
    {
	return $email->prop('email_reply_to');
    }
}


#######################################################################

=head2 charset_plain

=cut

sub charset_plain
{
    my( $email, $part ) = @_;

#    debug "Determining charset";

    if( $part )
    {
#	debug "  from part";
	my $charset = lc $part->charset;

	unless( $charset )
	{
	    my $params = $part->{'params'};
#	    debug "  using params";
	    foreach my $key (keys %$params )
	    {
		if( lc($key) eq 'charset' )
		{
#		    debug "    charset key";
		    $charset = lc( $params->{$key} );
#		    debug "    found it";
		    last;
		}
	    }
	}

	unless( $charset )
	{
	    my $type = lc $part->type;
	    if( $type =~ /^text\// )
	    {
#		debug "  from sample";
		my $sample = $email->bodypart_decoded($part,2000);
		require Encode::Detect::Detector;
		$charset = lc Encode::Detect::Detector::detect($sample);

		if( $charset )
		{
		    debug "Got charset from content sample: $charset";
		}
		else
		{
		    $charset = $email->charset_plain;
		}

		unless( $charset )
		{
		    debug "Should guess charset from language";
		    debug "Falling back on Latin-1";
		    $charset = "iso-8859-1";
		}
	    }
	}

	return $charset;
    }


    my $charset;

#    debug "  from main email";

    if( $email->prop('has_imap_url' ) )
    {
	unless( defined $email->{'email_charset'} )
	{
#	    debug "  initializing email_charset";
	    if( $email->exist )
	    {
		my $ctype_name = $email->content_type_plain;
#		debug "  using content-type $ctype_name";
	    }
	}

	$charset = $email->{'email_charset'};
    }

    unless( $charset )
    {
#	debug "  still not found";
	if( $email->content_type_plain =~ /^text\// )
	{
	    debug "Should guess charset from language";
	    debug "Falling back on Latin-1";
	    $charset = "iso-8859-1";
	}
    }

    return $charset;
}


#######################################################################

=head2 format_plain

=cut

sub format_plain
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( defined $email->{'email_format'} )
	{
	    return is_undef unless $email->exist;

	    $email->content_type_plain;
	}

	return $email->{'email_format'};
    }
    else
    {
	return undef;
    }
}


#######################################################################

=head2 content_type_plain

TODO: Implement effective_type, as in L<MIME::Entity/effective_type>

=cut

sub content_type_plain
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_content_type'} )
	{
	    return is_undef unless $email->exist;
	    my $content_type_raw = $email->header("content-type")->[0];
	    my @parts = split /\s*;\s*/, $content_type_raw;

	    $email->{'email_content_type'} = shift @parts;

	    my %ctype;
	    foreach my $part (@parts)
	    {
		if( $part =~ /^(.*?)\s*=\s*(.*)/ )
		{
		    $ctype{lc $1} = $2;
		}
		else
		{
		    die "Unparsable ctype part $part";
		}
	    }

	    $email->{'email_charset'} = lc $ctype{'charset'} || '';
	    $email->{'email_format'} = lc $ctype{'format'} || '';
	}

	return $email->{'email_content_type'};
    }
    else
    {
	return undef;
    }
}


#######################################################################

=head2 effective_type_plain

TODO: Implement effective_type, as in L<MIME::Entity/effective_type>

=cut

sub effective_type_plain
{
    return $_[0]->content_type_plain;
}


#######################################################################

=head2 encoding_plain

=cut

sub encoding_plain
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	unless( $email->{'email_encoding'} )
	{
	    return is_undef unless $email->exist;
	    my $encoding_raw =
	      $email->header("content-transfer-encoding")->[0];
	    $email->{'email_encoding'} = lc $encoding_raw;
	}

	return $email->{'email_encoding'};
    }
    else
    {
	return undef;
    }
}


#######################################################################

=head2 body

=cut

sub body
{
    my( $email ) = @_;

    if( $email->prop('has_imap_url' ) )
    {
	return "<not found>" unless $email->exist;

	my $uid = $email->uid_plain;
#	my $imap = $email->folder->imap;
#	return $imap->body_string($uid);
	return $email->folder->imap_cmd('body_string', $uid);
    }
    else
    {
	return $email->prop('email_body');
    }
}


#######################################################################

=head2 body_as_html

=cut

sub body_as_html
{
    my( $email ) = @_;

    unless( $email->prop('has_imap_url' ) )
    {
	my $data = CGI->escapeHTML($email->prop('email_body'));
	$data =~ s/\n/<br>\n/g;
	return $data;
    }

    return "<strong>not found</strong>" unless $email->exist;

    my $struct = $email->body_structure;

    my $type = $struct->type;
    my $renderer = $email->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }


    # Register email in session
    my $req = $Para::Frame::REQ;
    my $s = $req->session
      or die "Session not found";
    my $nid = $email->id;
    $s->{'email_imap'}{$nid} ||= {};

    my $msg = &{$renderer}($email, $struct);

    if( keys %{$email->{'email_attatchemnts'}} )
    {
	$msg .= "<ol>\n";

	foreach my $att ( sort values %{$email->{'email_attatchemnts'}} )
	{
	    my $name = $email->part_filename($att) ||
	      $email->generate_name($att);
	    my $name_enc = CGI->escapeHTML($name);
	    my $type = $att->type;
	    my $desc = CGI->escapeHTML($att->description);

	    my $url_path = $email->part_url_path($att, $name);
	    my $desig = "<a href=\"$url_path\">$name</a>";
	    if( $desc )
	    {
		$desig .= " - $desc";
	    }
	    $desig .= " ($type)";

	    $msg .= "<li>$desig</li>\n";
	}
	$msg .= "</ol>\n";
    }

    return $msg;
}


#######################################################################

=head2 select_renderer

=cut

sub select_renderer
{
    my( $email, $type ) = @_;

    debug "Selecting renderer for $type";

    my $renderer;
    foreach (
	     [ qr{text/plain}            => \&_render_textplain  ],
	     [ qr{text/html}             => \&_render_texthtml   ],
	     [ qr{multipart/alternative} => \&_render_alt        ],
	     [ qr{multipart/mixed}       => \&_render_mixed      ],
	     [ qr{multipart/related}     => \&_render_related    ],
	     [ qr{image/}                => \&_render_image      ],
	     [ qr{message/rfc822}        => \&_render_rfc822     ],
	     [ qr{multipart/parallel}    => \&_render_mixed      ],
	     [ qr{multipart/report}      => \&_render_mixed      ],
	     [ qr{multipart/}            => \&_render_mixed      ],
	     [ qr{text/rfc822-headers}   => \&_render_headers    ],
	     [ qr{text/}                 => \&_render_textplain  ],
	     [ qr{message/delivery-status}=> \&_render_delivery_status ],
	    )
    {
        $type =~ $_->[0]
	  and $renderer = $_->[1]
            and last;
    }

    return $renderer;
}


#######################################################################

=head2 body_structure

=cut

sub body_structure
{
    my( $email ) = @_;

    if( $email->{'email_body_structure'} )
    {
	return $email->{'email_body_structure'};
    }

    my $folder = $email->folder;
    my $uid = $email->uid_plain;

#    my $imap = $folder->imap;
#    my $res = $imap->fetch($uid,"bodystructure")
#      or die $folder->diag("Can't get bodystructure");
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

#    debug $email->part_desig( $struct );

    return $email->{'email_body_struct'} = $struct;
}


#######################################################################

=head2 part

=cut

sub part
{
    my( $email, $path ) = @_;

    my $struct = $email->body_structure;

    unless( $path )
    {
	return $struct;
    }

    return $struct->part_at($path);
}


#######################################################################

=head2 part_desig

=cut

sub part_desig
{
    my( $email, $part ) = @_;

    $part ||= $email->body_structure;

    my $type = $part->type     || '-';
    my $enc = $part->encoding  || '-';
    my $size = $part->size     || '-';
    my $disp = $part->disp     || '-';
    my $char = $part->charset  || '-';
    my $file = $part->filename || '-';
    my $lang = $part->{lang}   || '-';
    my $loc = $part->{loc}     || '-';
    my $cid = $part->{cid}     || '-';
    my $desc = $part->description || '-';

    my $path = $part->part_path;

    my $msg = "$path $type $enc $size $disp $char $file $lang $loc $cid $desc\n";
#    debug $msg;
    foreach my $subpart ( $part->parts )
    {
#	debug "  subpart $subpart";
	$msg .= $email->part_desig($subpart);
    }

    return $msg;
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

=head2 see

=cut

sub see
{
    my( $email ) = @_;

    my $uid = $email->uid_plain;

    debug "Mark email as seen";
    my $folder = $email->folder;
#    $folder->imap->see($uid)
#      or debug $folder->diag("Could not see email $uid");
    $folder->imap_cmd('see', $uid);
}

#######################################################################

=head2 unsee

=cut

sub unsee
{
    my( $email ) = @_;

    my $uid = $email->uid_plain;

    debug "Mark email as unseen";
    my $folder = $email->folder;

    $folder->imap_cmd('unset_flag', "\\Seen", $uid);
    return 1;
}

#######################################################################

=head2 is_seen

=cut

sub is_seen
{
    my( $email ) = @_;

    my $uid = $email->uid_plain;

    my $folder = $email->folder;
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
    my( $email ) = @_;

    my $uid = $email->uid_plain;

    my $folder = $email->folder;
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

=head2 sysdesig

=cut

sub sysdesig
{
    my( $email ) = @_;

    return "Email ". $email->id .': '. $email->desig;
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

=head2 part_filename

=cut

sub part_filename
{
    my( $email, $part ) = @_;

    $part ||= $email->body_structure;

    my $name = $part->filename;
    unless( $name )
    {
	my $display_raw = $part->{'disp'};
	if( UNIVERSAL::isa  $display_raw, 'ARRAY' )
	{
	    foreach my $elem (@$display_raw)
	    {
		if( UNIVERSAL::isa $elem, 'HASH' )
		{
		    foreach my $key ( keys %$elem )
		    {
			if( lc($key) eq 'filename' )
			{
			    $name = $elem->{$key};
#			    debug "Filename from disp filename";
			}
			elsif( lc($key) eq 'name' )
			{
			    $name = $elem->{$key};
#			    debug "Filename from disp name";
			}
		    }
		}
	    }
	}
    }

    unless( $name )
    {
	if( my $params = $part->{'params'} )
	{
	    foreach my $key ( keys %$params )
	    {
		if( lc($key) eq 'filename' )
		{
		    $name = $params->{$key};
#		    debug "Filename from param filename";
		}
		elsif( lc($key) eq 'name' )
		{
		    $name = $params->{$key};
#		    debug "Filename from param name";
		}
	    }
	}
    }

    unless( $name )
    {
	my $type = lc $part->type;
	if( $type eq "message/rfc822" )
	{
	    $name = $part->{'envelope'}{'subject'} .".eml";
	}
    }

    my $name_dec;
    if( $name )
    {
	$name_dec = decode_mimewords( $name );

	utf8::upgrade( $name_dec );
    }

    return $name_dec;
}

#######################################################################

=head2 part_filename_safe

=cut

sub part_filename_safe
{
    my( $email, $part, $name ) = @_;

    $part ||= $email->body_structure;
    $name ||= $email->part_filename($part) ||
      $email->generate_name($part);

    my $type_name = lc $part->type;

    my $safe = lc $name;
    $safe =~ s/.*[\/\\]//; # Remove path
    $safe =~ s/\..*\././;  # Remove multiple extenstions
    my $ext;
    if( $safe =~ s/\.(.*)// )
    {
	$ext = $1;
    }

    $safe =~ tr[àáâäãåæéèêëíìïîóòöôõøúùüûýÿðþß]
               [aaaaaaaeeeeiiiioooooouuuuyydps];

    $safe =~ s/[^a-z0-9_\- ]//g;

#    debug "Safe base name: $safe";
#    debug "type name: $type_name";

    my $mt = MIME::Types->new;
    if( $type_name eq 'file/pdf' )
    {
	$type_name = 'application/pdf';
    }

    if( my $type = $mt->type($type_name) )
    {
	if( $type->type eq 'message/rfc822')
	{
	    # Not in db! :-P
	    $type->{'MT_extensions'} = ['eml'];
	}

	# debug "Got type $type";

	if( $ext )
	{
	    foreach my $e ( $type->extensions )
	    {
		if( $ext eq $e )
		{
		    return $safe .'.'. $ext;
		}
	    }
	    $ext = undef;
	}

	unless( $ext )
	{
	    ( $ext ) = $type->extensions;
	}
    }

#    debug "  extension $ext";

    return $safe .'.'. $ext;
}


#######################################################################

=head2 generate_name

  $email->generate_name

  $email->generate_name( $part )

Generates a non-unique message name for use for attatchemnts, et al

=cut

sub generate_name
{
    my( $email, $part ) = @_;

    my $name = "email".$email->uid;

    if( $part )
    {
	$name .= "-part".$part->part_path;
    }

    return $name;
}


#######################################################################

=head2 part_url_path

=cut

sub part_url_path
{
    my( $email, $part, $name ) = @_;

    my $home = $Para::Frame::REQ->site->home_url_path;
    my $nid = $email->id;
    my $path = $part ? $part->part_path : '';
    $path =~ s/\.TEXT$/.1/; # For embedded messages

    if( $name )
    {
	my $safe = $email->part_filename_safe($part, $name);

	my $s = $Para::Frame::REQ->session
	  or die "Session not found";
	$s->{'email_imap'}{$nid}{$safe} = $path;
	$path = $safe;
    }

    return "$home/admin/email/files/$nid/$path";
}


#######################################################################

=head2 is_message_bounce

=cut

sub is_message_bounce
{
    return $_[0]->message_bounce->is_bounce;
}


#######################################################################

=head2 message_bounce

=cut

sub message_bounce
{
    my( $email ) = @_;

    return $email->{'message'}{'bounce'} ||=
      Rit::Base::Email::Classifier::Bounce->new($email);
}


#######################################################################

=head2 is_message_vacation

=cut

sub is_message_vacation
{
    return $_[0]->message_vacation->is_vacation;
}


#######################################################################

=head2 message_vacation

=cut

sub message_vacation
{
    my( $email ) = @_;

    return $email->{'message'}{'vacation'} ||=
      Rit::Base::Email::Classifier::Vacation->new($email);
}


#######################################################################

=head2 is_message_challenge_response

Taken from L<Mail::DeliveryStatus::BounceParser>

=cut

sub is_message_challenge_response
{
    my( $email ) = @_;

    my $da = $email->header("x-delivery-agent")->[0] || '';

    if( $da =~ /^TMDA/ )
    {
	debug "Challenge / Response system autoreply";
	return 1;
    }

    return 0;
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

sub _render_textplain
{
    my( $email, $part ) = @_;

    debug "  rendering textplain";

    my $charset = $email->charset_plain($part);

    my $data_dec = $email->bodypart_decoded($part);
    my $data_enc = CGI->escapeHTML($data_dec);

    my $msg = "<p>Charset: $charset</p>\n";
    $data_enc =~ s/\n/<br>\n/g;
    $msg .= $data_enc;

    return $msg;
}


#######################################################################

sub _render_texthtml
{
    my( $email, $part ) = @_;

    debug "  rendering texthtml";

    my $url_path = $email->part_url_path($part);

    my $msg = qq(<a href="$url_path">Download HTML message</a>\n );

    if( my $other = $email->{'email_other'} )
    {
	foreach my $alt (@$other)
	{
	    my $type = $alt->type;
	    my $url = $email->part_url_path($alt);
	    $msg .= " | <a href=\"$url\">View alt in $type</a>\n";
	}
    }

$msg .= <<EOT;
<br>
<iframe class="iframe_autoresize" src="$url_path" scrolling="no" marginwidth="0" marginheight="0" frameborder="0" vspace="0" hspace="0" width="100%" style="overflow:visible; display:block; position:static"></iframe>

EOT
;

}


#######################################################################

sub _render_delivery_status
{
    my( $email, $part ) = @_;

    debug "  rendering delivery_status";

    my $data_dec = $email->bodypart_decoded($part);
    my $data_enc = CGI->escapeHTML($data_dec);

    my $msg = "<div style=\"background:yellow\"><h2>Delivery report</h2>\n";
    $data_enc =~ s/\n/<br>\n/g;
    $msg .= $data_enc;
    $msg .= "</div>\n";

    return $msg;
}


#######################################################################

sub _render_headers
{
    my( $email, $part ) = @_;

    debug "  rendering headers";

    my $data_dec = $email->bodypart_decoded($part);
    my $msg;

    my $header = Rit::Base::Email::Header->new(\$data_dec );
    unless( $header )
    {
	$msg = "<h3>Malformed header</h3>\n";
	$msg .= _render_textplain($email, $part);
    }
    else
    {
	$msg = $header->as_html;
    }

#    my $msg = "<div style=\"background:#e8e9e3\"><h3>The headers</h3>\n";
#    my $data_enc = CGI->escapeHTML($data_dec);
#    $data_enc =~ s/\n/<br>\n/g;
#    $msg .= $data_enc;
#    $msg .= "</div>\n";

    return $msg;
}


#######################################################################

sub _render_alt
{
    my( $email, $part ) = @_;

    debug "  rendering alt";

    my @alts = $part->parts;

    my %prio =
      (
       'text/html' => 3,
       'text/plain' => 2,
      );

    my $choice = shift @alts;
    my $score = $prio{ $choice->type } || 1; # prefere first part

    my @other;

    foreach my $alt (@alts)
    {
	my $type = $alt->type;
	unless( $type )
	{
	    push @other, $alt;
	    next;
	}

	if( ($prio{$type}||0) > $score )
	{
	    push @other, $choice;
	    $choice = $alt;
	    $score = $prio{$type};
	}
	else
	{
	    push @other, $alt;
	}
    }

    $email->{'email_other'} = \@other;

    my $type = $choice->type;
    my $path = $part->part_path;

    my $renderer = $email->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }

    return &{$renderer}($email, $choice);
}


#######################################################################

sub _render_mixed
{
    my( $email, $part ) = @_;

    debug "  rendering mixed";

#    debug $email->part_desig;

    my @alts = $part->parts;

    my $msg = "";

    $email->{'email_attatchemnts'} ||= {};

    foreach my $alt (@alts)
    {
	my $apath = $alt->part_path;

	my $type = $alt->type;
	my $renderer = $email->select_renderer($type);

	if( lc($alt->disp) eq 'inline' )
	{
	    if( $renderer )
	    {
		$msg .= &{$renderer}($email, $alt);
	    }
	    else
	    {
		debug "No renderer defined for $type";
		$msg .= "<code>No renderer defined for part $apath <strong>$type</strong></code>";
		$email->{'email_attatchemnts'}{$alt->part_path} = $alt;
	    }
	}
	elsif( $renderer ) # Display some things anyway...
	{
	    if( $type eq 'message/rfc822' )
	    {
		$msg .= &{$renderer}($email, $alt);
	    }
	    else
	    {
		$email->{'email_attatchemnts'}{$alt->part_path} = $alt;
	    }
	}
	else # Not requested for inline display
	{
	    $email->{'email_attatchemnts'}{$alt->part_path} = $alt;
	}
    }

    return $msg;
}


#######################################################################

sub _render_related
{
    my( $email, $part ) = @_;

    debug "  rendering related";

    my $path = $part->part_path;

    my $req = $Para::Frame::REQ;

    my @alts = $part->parts;

    my %prio =
      (
       'text/html' => 3,
       'text/plain' => 2,
      );

    my %files = ();

    foreach my $alt (@alts)
    {
	my $apath = $alt->part_path;

	if( my $file = $alt->filename )
	{
	    $files{$file} = $apath;
	}

	if( my $cid = $alt->{'cid'} )
	{
	    $cid =~ s/^<//;
	    $cid =~ s/>$//;
	    $files{$cid} = $apath;
	    debug "Path $apath -> $cid";
	}
    }

    my $s = $req->session
      or die "Session not found";
    my $id = $email->id;
    $s->{'email_imap'}{$id} = \%files;

    my $choice = shift @alts;
    my $score = $prio{ $choice->type } || 1; # prefere first part

    foreach my $alt (@alts)
    {
	my $type = $alt->type;
	next unless $type;

	if( ($prio{$type}||0) > $score )
	{
	    $choice = $alt;
	    $score = $prio{$type};
	}
    }

    my $type = $choice->type;
    my $renderer = $email->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }

    my $data = &{$renderer}($email, $choice);

#"cid:part1.00090900.07060702@avisita.com"

    my $url_path = $email->part_url_path();
    $data =~ s/(=|")\s*cid:(.+?)("|\s|>)/$1$url_path$files{$2}$3/gi;
    return $data;
}


#######################################################################

sub _render_image
{
    my( $email, $part ) = @_;

    debug "  rendering image";

    my $url_path = $email->part_url_path($part);

    my $desig = $email->part_filename($part) || "image";
    if( my $desc = $part->description )
    {
	$desig .= " - $desc";
    }

    my $desig_out = CGI->escapeHTML($desig);

    $email->{'email_attatchemnts'} ||= {};
    $email->{'email_attatchemnts'}{$part->part_path} = $part;

    return "<img alt=\"$desig_out\" src=\"$url_path\"><br clear=\"all\">\n";
}


#######################################################################

sub _render_rfc822
{
    my( $email, $part ) = @_;

    debug "  rendering rfc822";

    my $env = $part->{'envelope'};

    my $msg = "";

    $msg .= "\n<br>\n<table class=\"admin\" style=\"background:#E0E0EA\">\n";

    my $subj_lab = CGI->escapeHTML(loc("Subject"));
    my $subj_val = CGI->escapeHTML(scalar decode_mimewords($env->{'subject'}));
    $msg .= "<tr><td>$subj_lab</td><td width=\"100%\"><strong>$subj_val</strong></td></tr>\n";

    my $from_lab = CGI->escapeHTML(loc("From"));
    my $from_val =  CGI->escapeHTML( join "<br>\n", map {scalar decode_mimewords($_->{'full'})} @{$env->{'from'}} );
    $msg .= "<tr><td>$from_lab</td><td>$from_val</td></tr>\n";

    my $date_lab = CGI->escapeHTML(loc("Date"));
    my $date_val = CGI->escapeHTML(Rit::Base::Literal::Time->get($env->{'date'}));
    $msg .= "<tr><td>$date_lab</td><td>$date_val</td></tr>\n";

    my $to_lab = CGI->escapeHTML(loc("To"));
    my $to_val = CGI->escapeHTML( join "<br>\n", map {scalar decode_mimewords($_->{'full'})} @{$env->{'to'}} );
    $msg .= "<tr><td>$to_lab</td><td>$to_val</td></tr>\n";

    my $filename = $email->part_filename($part);
    my $url_path = $email->part_url_path($part);
    $msg .= "<tr><td colspan=\"2\"><a href=\"$url_path\">Download as email</a></td></tr>\n";




    $msg .= "<tr><td colspan=\"2\" style=\"background:#FFFFE5\">";

    my $struct = $part->{'bodystructure'};
    my $path = $struct->part_path;
    my $type = $struct->type;


    my $renderer = $email->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for part $path <strong>$type</strong></code>";
    }

    $msg .= &{$renderer}($email, $struct);

    $msg .= "</td></tr></table>\n";

    return $msg;
}


#######################################################################

sub bodypart_decoded
{
    my( $email, $part, $length ) = @_;

#    my $charset = $email->charset_plain($part);
    my $encoding = lc $part->encoding || $email->encoding_plain;

    my $folder = $email->folder;
    my $uid = $email->uid_plain;
    my $path = $part->part_path;
    debug "Getting bodypart $uid $path";
#    my $imap = $folder->imap;
#    my $data = $imap->bodypart_string($uid, $path, $length)
#      or die $folder->diag("Could not get message $uid part $path");
    my $data = $folder->imap_cmd('bodypart_string', $uid, $path, $length);

    my $data_dec;

    if( $encoding eq 'quoted-printable' )
    {
	return decode_qp($data);
    }
    elsif( $encoding eq '8bit' )
    {
	return $data;
    }
    elsif( $encoding eq '7bit' )
    {
	return $data;
    }
    elsif( $encoding eq 'base64' )
    {
	return decode_base64($data);
    }
    else
    {
	die "encoding $encoding not supported";
    }

    return $data_dec;
}


#######################################################################

1;
