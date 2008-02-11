#  $Id$  -*-cperl-*-
package Rit::Base::Renderer::IMAP;
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

Rit::Base::Renderer::IMAP

=head1 DESCRIPTION

=cut

use strict;

use Encode;
use Carp qw( croak confess cluck );
use MIME::Base64 qw( decode_base64 );
use MIME::QuotedPrint qw(decode_qp);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use Para::Frame::Utils qw( throw debug datadump catch client_send
                           validate_utf8 );

use Rit::Base::Resource;

use base qw( Para::Frame::Renderer::Custom );

#######################################################################

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

    unless( $path =~ /\/(\d+)\/([^\/]+)$/ )
    {
	debug "Path in invalid format: $path";
	return undef;
    }

    my $nid = $1;
    my $search = $2;

    my $lookup = $req->session->{'email_imap'}{$nid};
    unless( $lookup )
    {
	debug "Node not registred in session";
	return undef;
    }

    my $imap_path;

    if( $search =~ /^[\d\.]+$/ )
    {
	$imap_path = $search;
    }
    else
    {
	$imap_path = $lookup->{$search};
    }

    unless( $imap_path )
    {
	debug "file not found as a part of message";
	return undef;
    }


    my $email = Rit::Base::Resource->get($nid);
    my $top = $email->structure;
    my $part = $top->new_by_path($imap_path);

    my $type = $part->type;
    my $charset = $part->charset_guess;

    unless( $charset )
    {
	debug "Charset undefined. Falling back on ISO-8859-1";
	$charset = "iso-8859-1";
    }


    $rend->{'content_type'} = $type;
    $rend->{'charset'} = $charset;

    my $encoding = lc($part->struct->encoding);


    debug "Metadata registred: $type - $charset";


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



    my $client = $req->client;

    my $folder = $top->folder;
    my $uid = $top->uid_plain;

    debug "Getting bodypart $uid $imap_path";
    my $data = $folder->imap_cmd('bodypart_string', $uid, $imap_path);
#    debug "bodypart_string: ".validate_utf8( \$data );

    my $data_dec;
    if( $encoding eq 'base64' )
    {
	$data = decode_base64($data);
    }
    elsif( $encoding eq '8bit' )
    {
	# Ok
    }
    elsif( $encoding eq '7bit' )
    {
	# Ok
    }
    elsif( $encoding eq 'quoted-printable' )
    {
	$data = decode_qp($data);
    }
    else
    {
	die "Encoding $encoding unsupported";
    }

#    debug "decoded data: ".validate_utf8(\$data);

    if( $type eq 'text/html' )
    {
	use bytes; # Don't touch original encoding!

	my $url_path = $top->url_path;
	$data =~ s/(=|")\s*cid:(.+?)("|\s|>)/$1$url_path$lookup->{$2}$3/gi;
	unless( $data =~ s/<body(.*?)>/<body onLoad="parent.onLoadPage();"$1>/is )
	{
	    my $subject = encode( $charset, $email->subject );
#	    debug "Subject '$subject': ".validate_utf8(\$subject);
	    my $subject_out = CGI->escapeHTML($subject);

	    my $header = "<html><title>$subject_out</title>";
	    $header .= "<body onLoad=\"parent.onLoadPage()\">\n";
	    my $footer = "</body></html>\n";
	    $data = $header . $data . $footer;
	}
    }

    $resp->{'encoding'} = 'raw';

#    debug "Body is ".length($data)." chars long: ".validate_utf8(\$data);

    return \ $data;
}

#######################################################################

sub set_ctype
{
    my( $rend, $ctype ) = @_;

    $ctype->set_type( $rend->{'content_type'} );
    $ctype->set_charset( $rend->{'charset'} );
}


#######################################################################



1;
