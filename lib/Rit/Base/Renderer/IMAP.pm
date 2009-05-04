package Rit::Base::Renderer::IMAP;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

=head1 NAME

Rit::Base::Renderer::IMAP

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Renderer::Custom );

use Encode;
use Carp qw( croak confess cluck );
use MIME::Base64 qw( decode_base64 );
use MIME::QuotedPrint qw(decode_qp);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump catch client_send
                           validate_utf8 );

use Rit::Base::Resource;


##############################################################################

=head2 render_output

=cut

sub render_output
{
    my( $rend, $args_in ) = @_;


    my $resp = $rend->response;
    my $p = $resp->page;

    my $path = $p->path;
    my $name = $p->name;

    debug "LOOKING for $name";

    my $req = $rend->req;

    my( $nid, $search, $head );
    if( $path =~ /\/(\d+)(?:\/([^\/]*?)(\.head)?)$/ )
    {
#	debug "$1 - $2 - $3 - $4";

	$nid = $1;
	$search = $2;

	if( $3 )
	{
	    $head = 1; # Show the headers
	}
    }
    else
    {
	debug "Path in invalid format: $path";
	return undef;
    }

    my $lookup = $req->session->{'email_imap'}{$nid};
    unless( $lookup )
    {
	debug "Node not registred in session";
	return undef;
    }

    my $email = Rit::Base::Resource->get($nid);
    my $top = $email->obj;


    my( $imap_path, $part, $type, $charset, $encoding );

    if( $search )
    {
	if( $search =~ /^[\d\.]+$/ )
	{
	    $imap_path = $search;
	}
	else
	{
	    $search =~ s/%20/ /g;
	    $imap_path = $lookup->{$search};
	}

	if( not $imap_path )
	{
	    debug "file '$search' not found as a part of message";
	    my $s = $req->session;
	    debug "Session ($s) :\n".
	      datadump($s->{'email_imap'});
	    return undef;
	}
	elsif( $imap_path eq '-' )
	{
	    $imap_path = undef;
	}


#	debug "Search is $search";

	if( $search =~ /\.html$/ )
	{
	    $type = 'text/html';
	    debug "Setting type based on search extenstion";
	}
    }

    if( $imap_path )
    {
	$part = $top->new_by_path($imap_path);

	$type = $part->type || '';
#	debug "part type is $type";
	if( $type =~ m/^text\// )
	{
	    $charset = $part->charset_guess;
	    unless( $charset )
	    {
		debug "Charset undefined. Falling back on ISO-8859-1";
		$charset = "iso-8859-1";
	    }
	}

	$encoding = $part->encoding;
#	debug "Metadata registred: $type - $charset";
    }
    else
    {
	$encoding = $top->encoding;
	$charset = $top->charset_guess;
    }

    my $updated = $email->first_arc('has_imap_url')->updated;
    my $epoch = $updated->epoch;

    $resp->set_header( 'Last-Modified', $updated->internet_date );

    my $max_age = DateTime::Duration->new(seconds => 7*24*60*60);
    my $expire = $updated->add_duration( $max_age );

    $resp->set_header( 'Expires', $expire->internet_date );
    $resp->set_header( 'Cache-Control', "max-age=" . $max_age->delta_seconds );


    if( my $client_time = $req->http_if_modified_since )
    {
	if( $updated <= $client_time )
	{
	    debug "Not modified";
	    $resp->set_http_status(304);
	    $req->set_header_only(1);
	}
	else
	{
	    debug "Modified recently";
	}
    }

    $resp->set_http_status(200);
    $resp->{'encoding'} = 'raw';


    if( $head )
    {
	$part ||= $top;

	$rend->{'content_type'} = "text/html";
	$rend->{'charset'} = "UTF-8";

	my $head = $part->head_complete;

	my $data = $head->as_html;
	return \$data;
    }



#    my $client = $req->client;

#    my $folder = $top->folder;
#    my $uid = $top->uid;


    my $data;
    if( not $imap_path )
    {
	if( $type eq "text/html" )
	{
	    $data = $top->body;
#	    $data = $folder->imap_cmd('body_string', $uid);
	}
	else
	{
	    # TODO: Create function for returning whole message
	    $type = "message/rfc822";
	    my $folder = $top->folder;
	    my $uid = $top->uid;
	    $data = \ $folder->imap_cmd('message_string', $uid);
	}
    }
    else
    {
#	debug "Getting bodypart $uid $imap_path";
	$data = $part->body;
#	$data = $folder->imap_cmd('bodypart_string', $uid, $imap_path);
	#    debug "bodypart_string: ".validate_utf8( \$data );
    }


    $rend->{'content_type'} = $type;
    $rend->{'charset'} = $charset;

    if( $type eq "message/rfc822" )
    {
#	debug "Returning the whole message (no imap_path)";
	return $data;
    }

#    # Set encoding if missing
#    $encoding ||= '8bit'; ### Reasonable default?
#    debug "Using encoding '$encoding'";
#
#    if( $encoding eq 'base64' )
#    {
#	$data = decode_base64($data);
#    }
#    elsif( $encoding eq '8bit' )
#    {
#	# Ok
#    }
#    elsif( $encoding eq 'binary' )
#    {
#	# Ok (same as 8bit)
#    }
#    elsif( $encoding eq '7bit' )
#    {
#	# Ok
#    }
#    elsif( $encoding eq 'quoted-printable' )
#    {
#	$data = decode_qp($data);
#    }
#    else
#    {
#	die "Encoding $encoding unsupported";
#    }

#    debug "decoded data: ".validate_utf8(\$data);
#    debug "type is $type";

    if( $type eq 'text/html' )
    {
	use bytes; # Don't touch original encoding!

	my $email_path = $top->email->url_path;
	$$data =~ s/(=|")\s*cid:(.+?)("|\s|>)/$1$email_path$lookup->{$2}$3/gi;
	unless( $$data =~ s/<body(.*?)>/<body onLoad="parent.onLoadPage();"$1>/is )
	{
	    my $subject = encode( $charset, $email->subject );
#	    debug "Subject '$subject': ".validate_utf8(\$subject);
	    my $subject_out = CGI->escapeHTML($subject);

	    my $header = "<html><title>$subject_out</title>";
	    $header .= "<body onLoad=\"parent.onLoadPage()\">\n";
	    my $footer = "</body></html>\n";
	    $$data = $header . $$data . $footer;
	}
    }


    debug "Body is ".length($$data)." chars long";
    if( $type =~ /^test\// )
    {
	debug "  ".validate_utf8($data);
    }

#    debug $data;

    return $data;
}

##############################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    $ctype->set_type( $rend->{'content_type'} );
    $ctype->set_charset( $rend->{'charset'} );
}


##############################################################################



1;
