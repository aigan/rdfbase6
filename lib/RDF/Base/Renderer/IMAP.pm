package RDF::Base::Renderer::IMAP;
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

RDF::Base::Renderer::IMAP

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use base qw( Para::Frame::Renderer::Custom );

use Encode;                     # encode decode
use Carp qw( croak confess cluck );
use MIME::Base64 qw( decode_base64 );
use MIME::QuotedPrint qw(decode_qp);
use DateTime::Duration;

use Para::Frame::Reload;
use Para::Frame::Time qw( now );
use Para::Frame::Utils qw( throw debug datadump catch client_send
                           validate_utf8 );

use RDF::Base::Resource;


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

    my( $nid, $search, $head, $tt );
    if ( $path =~ /\/(\d+)(?:\/([^\/]*?)(?:\.(head|tt))?)$/ )
    {
#	debug "$1 - $2 - $3 - $4";

        $nid = $1;
        $search = $2;
        my $arg = $3 || '';

        if ( $arg eq 'head' )
        {
            $head = 1;          # Show the headers
        }
        elsif ( $arg eq 'tt' )
        {
            $tt = 1;            # Compile TT template
            debug "Render TT";
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

    my $email = RDF::Base::Resource->get($nid);
    my $top = $email->obj;


    my( $imap_path, $part, $type, $encoding );

    if ( $search )
    {
        if ( $search =~ /^[\d\.]+$/ )
        {
            $imap_path = $search;
        }
        else
        {
            $search =~ s/%20/ /g;
            $imap_path = $lookup->{$search};
        }

        if ( not $imap_path )
        {
            debug "file '$search' not found as a part of message";
            my $s = $req->session;
            debug "Session ($s) :\n".
              datadump($s->{'email_imap'});
            return undef;
        }
        elsif ( $imap_path eq '-' )
        {
            $imap_path = undef;
        }


#	debug "Search is $search";

        if ( $search =~ /\.html$/ )
        {
            $type = 'text/html';
            debug "Setting type based on search extenstion";
        }
    }

    if ( $imap_path )
    {
        $part = $top->new_by_path($imap_path);

        $type = $part->type || '';

        $encoding = $part->encoding;
    }
    else
    {
        $encoding = $top->encoding;
    }

    my $updated = $email->first_arc('has_imap_url')->updated;
    my $epoch = $updated->epoch;

    $resp->set_header( 'Last-Modified', $updated->internet_date );

    my $max_age = DateTime::Duration->new(seconds => 7*24*60*60);
    my $expire = now->add_duration( $max_age );

    $resp->set_header( 'Expires', $expire->internet_date );
    $resp->set_header( 'Cache-Control', "max-age=" . $max_age->delta_seconds );


    $resp->set_http_status(200);

    if ( my $client_time = $req->http_if_modified_since )
    {
        if ( $updated <= $client_time )
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

    $resp->{'encoding'} = 'raw';

    if ( $head )
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


    my( $data, $charset );
    if ( not $imap_path )
    {
        if ( $type eq "text/html" )
        {
            ($data,$charset) = $top->body_with_sensible_charset;
        }
        else
        {
#            debug "Returning the whole message (no imap_path)";

            $type = "message/rfc822";
            return $top->raw;
        }
    }
    else
    {
#	debug "Getting bodypart ".$top->uid." $imap_path";
        ($data,$charset) = $part->body_with_sensible_charset;
#        debug "Sensible Charset set to $charset";
#	$data = $folder->imap_cmd('bodypart_string', $uid, $imap_path);
        #    debug "bodypart_string: ".validate_utf8( \$data );
    }



    #### Convert to requested format
    if( my $format = $resp->req->q->param('format') )
    {
        ($data,$type) = convert_data($data,
                                     {
                                      type => $type,
                                      name => $name,
                                      format => $format,
                                     });
    }



    $part ||= $top;
    $rend->{'content_type'} = $type;
#    $rend->{'charset'} = $part->charset_guess;
    $rend->{'charset'} = $charset;
#    debug "Charset set to ".$rend->{'charset'};


    if ( $type eq 'text/html' )
    {
        use bytes;              # Don't touch original encoding!

        my $email_path = $top->email->url_path;
        $$data =~ s/(=|")\s*cid:([^> "]+?)("|\s|>)/$1$email_path$lookup->{$2}$3/gi;

        if ( $tt )
        {
            my $tt_params =
            {
             in_web_version => 1,
             web_version => 'WEB VERSION',
             optout => 'OPTOUT',
            };

            my $burner = Para::Frame::Burner->get_by_type('plain');
            my $parser = $burner->parser;
            my $tmpl_out = "";
            my $outref = \$tmpl_out;
            my $parsedoc = $parser->parse( $$data, {} ) or
              throw('template', "parse error: ".$parser->error);
            my $doc = Template::Document->new($parsedoc) or
              throw('template', $Template::Document::ERROR);
            $burner->burn($rend, $doc, $tt_params, $outref) or
              throw('template', $Template::Document::ERROR);

            $data = $outref;
        }


        unless( $$data =~ s/<body(.*?)>/<body onLoad="parent.onLoadPage();"$1>/is )
        {
            my $subject;
            eval
            {
                $subject = encode( $top->charset_guess, $email->subject );
            } or do
            {
                $subject = $email->subject;
            };


#	    debug "Subject '$subject': ".validate_utf8(\$subject);
            my $subject_out = CGI->escapeHTML($subject);

            my $header = "<html><title>$subject_out</title>";
            $header .= "<body onLoad=\"parent.onLoadPage()\">\n";
            my $footer = "</body></html>\n";

#            debug "BODY ".validate_utf8($data);

            $$data = $header . $$data . $footer;
        }
    }


    debug "Body is ".length($$data)." chars long";
    if ( $type =~ /^test\// )
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

#    debug "Set ctype to ".$rend->{'content_type'}." with ".$rend->{'charset'};

    $ctype->set_type( $rend->{'content_type'} );
    $ctype->set_charset( $rend->{'charset'} );
}


##############################################################################

sub convert_data
{
    my( $data, $args ) = @_;

    my $type = $args->{type};
    my $format = $args->{format};
    my $name = $args->{name};

    return( $data, $type ) unless $format eq 'png';
    return( $data, $type ) unless $type eq 'application/pdf';
    debug "from type $type";

#    ### Using temporary files
#
#    my $tmpdir = Para::Frame::Dir->
#      new_possible_sysfile($Para::Frame::CFG->{'dir_var'}.'/imap');
#    debug "tmpdir ".$tmpdir->sysdesig;
#    my $f = $tmpdir->get_virtual($$.'-'.$name);
#    $f->set_content($data);
#    debug "Saved pdf in ".$f->sys_path;
#
#    my $converted_name = $name;
#    $converted_name =~ s/(\.pdf)?$/.png/i;
#    my $f2 = $tmpdir->get_virtual($$.'-'.$converted_name);
#
#    use Image::Magick;
#
#    my $image = Image::Magick->new;
#    $image->Set(density=>150);
#    $image->Read($f->sys_path);
#    debug "Width ".$image->Get('width');
#    $image->Write(filename => $f2->sys_path, density=>150);
#    $data = $f2->contentref;


    ### In-memory conversion

    use Image::Magick;

    my $image = Image::Magick->new;
    $image->Set(density=>150); # Maby 100 is enough...
    $image->BlobToImage($$data);
    debug "Width ".$image->Get('width');
    my $blob = $image->ImageToBlob(magick=>'png');
    $data = \ $blob;

    $type = 'image/png';

    return( $data, $type );
}


##############################################################################


1;
