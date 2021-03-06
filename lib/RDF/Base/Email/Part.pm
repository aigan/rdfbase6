package RDF::Base::Email::Part;
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

RDF::Base::Email::Part

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;
use base qw( RDF::Base::Object );
use constant EA => 'RDF::Base::Literal::Email::Address';

use Carp qw( croak confess cluck shortmess );
use Scalar::Util qw(weaken);
#use MIME::Words qw( decode_mimewords );
use MIME::WordDecoder qw( mime_to_perl_string );
use MIME::QuotedPrint qw(decode_qp);
use MIME::Base64 qw( decode_base64 );
use MIME::Types;
#use CGI;
use Number::Bytes::Human qw(format_bytes);
use File::MMagic::XS qw(:compat);
use Encode;                     # encode decode

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump validate_utf8 );
use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use RDF::Base;
use RDF::Base::Utils qw( parse_propargs is_undef );
use RDF::Base::Constants qw( $C_email );
use RDF::Base::Literal::String;
use RDF::Base::Literal::Time qw( now ); #);
use RDF::Base::Literal::Email::Address;
use RDF::Base::Literal::Email::Subject;
use RDF::Base::Email::Head;
use RDF::Base::Email::Raw::Part;
use RDF::Base::Email::Interpart;
use RDF::Base::Email::Classifier;

#our $MIME_TYPES;


##############################################################################

=head2 new

=cut

sub new
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 interpart

=cut

sub interpart
{
    return RDF::Base::Email::Interpart::new(shift, @_);
}


##############################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 top

=cut

sub top
{
    return( $_[0]->{'top'} or die "Top part not given");
}


##############################################################################

=head2 folder

=cut

sub folder
{
    confess "WRONG TURN";
}


##############################################################################

=head2 struct

=cut

sub struct
{
    confess "WRONG TURN";
}



##############################################################################

=head2 exist

Is the content of this part availible?

=cut

sub exist
{
    return 1;
}


##############################################################################

=head2 email

Returns the RB email node

=cut

sub email
{
    return $_[0]->{'email'};
}


##############################################################################

=head2 envelope

=cut

sub envelope
{
    die "IMPLEMENT ME";
}


##############################################################################

=head2 first_part_with_type

=cut

sub first_part_with_type
{
    my( $part, $type ) = @_;
#    debug "first_part_with_type($type)";
    my $class = ref($part);

    if ( $part->type =~ /^$type/ )
    {
        return $part;
    }
    else
    {
        return $part->first_subpart_with_type( $type );
    }
}


##############################################################################

=head2 first_subpart_with_type

=cut

sub first_subpart_with_type
{
    my( $part, $type ) = @_;
#    debug "first_subpart_with_type($type)";
    my $class = ref($part);

    foreach my $sub ( $part->parts )
    {
#        debug "  check ".$sub->type;
        if ( $sub->type =~ /^$type/ )
        {
            return $sub;
        }
        elsif ( my $match = $sub->first_subpart_with_type($type) )
        {
            return $match;
        }
    }

    if ( $part->guess_type eq 'message/rfc822' )
    {
        if ( my $body_part = $part->body_part )
        {
            return $body_part->first_part_with_type($type);
        }
    }

    return undef;
}


##############################################################################

=head2 first_non_multi_part

=cut

sub first_non_multi_part
{
    my( $part ) = @_;
    my $class = ref($part);

    if ( $part->type =~ /^multipart\// )
    {
        my( $sub ) = ($part->parts)[0]
          or return $part;      # type may be wrong
        return $sub->first_non_multi_part;
    }

    return $part;
}


##############################################################################

=head2 parts

  my @parts = $part->parts();

Returns: A list of parts, not counting itself

=cut

sub parts
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 path

=cut

sub path
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 parent

=cut

sub parent
{
    unless ( $_[0]->{'parent'} )
    {
        debug datadump $_[0];
        confess "no parent";
    }
    return $_[0]->{'parent'};
}


##############################################################################

=head2 charset

=cut

sub charset
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 encoding

=cut

sub encoding
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 cid

=cut

sub cid
{
    return $_[0]->head->header('content-id') ||
      $_[0]->head->header('content-location','cid');
}


##############################################################################

=head2 type

=cut

sub type
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 content_type

Alias for L</effective_type>

=cut

sub content_type
{
    return shift->effective_type(@_);
}


##############################################################################

=head2 effective_type

  $part->effective_type

  $part->effective_type( $type )

Mostly the same as L</type>.

Any entity with an unrecognized Content-Transfer-Encoding must be
treated as if it has a Content-Type of "application/octet-stream",
regardless of what the Content-Type header field actually says.

On the other hand; If the type is given as "application/octet-stream"
but we recognize the file extension, the type will be given based on
the file extension.

Returns: A plain scalar string of the mime-type

See also: L<MIME::Entity/effective_type>

=cut

sub effective_type
{
    if ( $_[0]->{'effective_type'} )
    {
        return $_[0]->{'effective_type'};
    }

    my $MIME_TYPES = MIME::Types->new();
#    &mime_types_init unless $MIME_TYPES;

    my $type_name = $_[1] || $_[0]->type;

    unless( $type_name =~ /^[a-z]+\/[a-z\-\+\.0-9]+$/ )
    {
        if ( $type_name =~ s/\s*charset\s*=.*//i )
        {
#	    debug "Cleaning up mimetype";
            return $_[0]->effective_type($type_name);
        }

        debug "Mime-type $type_name malformed";
        $type_name = 'application/octet-stream';
    }

    if ( $type_name eq 'image/jpg' )
    {
        $type_name = 'image/jpeg';
    }

    unless( $MIME_TYPES->type($type_name) )
    {
        debug "Mime-type $type_name not recognized";
        $type_name = 'application/octet-stream';
    }


    if ( $type_name eq 'application/octet-stream' )
    {
        $_[0]->filename =~ /\.([^\.]+)$/;
        if ( my $ext = $1 )
        {
            if ( my $type = $MIME_TYPES->mimeTypeOf($ext) )
            {
                $type_name = $type->type;
#		cluck "HERE";
#		debug "Got type $type_name from extension";
            }
        }
    }

    if ( $type_name eq 'application/octet-stream' )
    {
        $type_name = $_[0]->guess_type;
    }

    return $_[0]->{'effective_type'} = $type_name;
}


##############################################################################

=head2 guess_type

  $part->guess_type

Called from L</effective_type> when the content-type is not
recognized. Guesses the content-type from the part body.

Will make special parsing for detecting message/rfc822

Returns: A plain scalar string of the mime-type

=cut

sub guess_type
{
    my( $part ) = @_;

    # For large headers...
    my $body_part = $part->body_with_original_charset(5000);

    my $m = File::MMagic::XS->new();
    my $res = $m->checktype_contents($$body_part);
    $res ||= 'application/octet-stream';

    # File::MMagic::XS may/will not recognize message/rfc822
    #
    if ( $res eq 'text/plain' )
    {
#        debug "  looking at text/plain for possibly headers";
        my $ok = 1;
        my $rows = 0;
        foreach ( split /^/, $$body_part )
        {
            if ( /^[A-Za-z\-]+:/ )
            {
                $rows++;
#                debug "  Yes: $_";
            }
            elsif ( /^\r?\n$/ )
            {
                # End of header
                last;
            }
            elsif ( /^\s+/ )
            {
#                debug "  Yes: $_";
                # ok
            }
            else
            {
                # Nonheader stuff
#                debug "  No: $_";
                $ok = 0;
                last;
            }
        }

        if ( $ok and $rows )
        {
            $res = 'message/rfc822';
        }
    }


#   debug "Guessed content type '$res'";

    if ( $res eq 'message/rfc822' )
    {
        # Assume we have to convert to raw part
        # ... (the need for it could be checked)
#	$part->{'_convert_to_raw'} = 1;
#	debug "should convert to raw part"; ### DEBUG
    }

    return $res;
}


##############################################################################

=head2 disp

Returns the content-disposition of the part. One of 'inline' or 'attachment', usually.

See L<IMAP::BodyStructure/disp>

=cut

sub disp
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 description

=cut

sub description
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 size

  $part->size

Returns the size of the part in octets. It is I<NOT> the size of the
data in the part, which may be encoded as quoted-printable leaving us
without an obvious method of calculating the exact size of original
data.

NOTE: Is this the size of the body of the part??? I'll assume it is.

=cut

sub size
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 size_human

=cut

sub size_human
{
    my $size = $_[0]->size;
    if ( defined $size )
    {
        return format_bytes($size);
    }

    return "";
}


##############################################################################

=head2 body_head_complete

  $part->body_head_complete()

This will return the headers of the rfc822 part.



Returns: a L<RDF::Base::Email::Head> object

=cut

sub body_head_complete
{
    confess "NOT IMPLEMENTED";
}

##############################################################################

=head2 body_head

  $part->body_head()

The returned head object may not contain all the headers. See
L<RDF::Base::Email::IMAP::Head>

See L</body_head_complete>.

Returns: a L<RDF::Base::Email::Head> object

=cut

sub body_head
{
    return shift->body_head_complete(@_);
}


##############################################################################

=head2 head_complete

  $part->head_complete()

This will return the head of the current part.

Returns: a L<RDF::Base::Email::Head> object

=cut

sub head_complete
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 header_obj

Alias for L</head_complete>

=cut

sub header_obj
{
    return shift->head_complete(@_);
}


##############################################################################

=head2 head

  $part->head()

The returned head object may not contain all the headers. See
L<RDF::Base::Email::IMAP::Head>

See L</head_complete>.

Returns: a L<RDF::Base::Email::Head> object

=cut

sub head
{
    return shift->head_complete(@_);
}

##############################################################################

=head2 header

  $part->header( $name )

Returns in scalar context: The first header of $name, or the empty
string if not existing.

Retuns in list context: A list of all $name headers

=cut

sub header
{
#    debug "Getting header $_[1]";

    if ( $_[1] eq 'to' )
    {
        $_[0]->head->init_to;
    }

    if ( wantarray )
    {
        my( @h ) = $_[0]->head->
          header($_[1]);

        my @res;

        foreach my $str (@h )
        {
            $str =~ s/;\s+(.*?)\s*$//;

            if ( $_[2] )
            {
                my $params = $1;
                foreach my $param (split /\s*;\s*/, $params )
                {
                    if ( $param =~ /^(.*?)\s*=\s*(.*)/ )
                    {
                        my $key = lc $1;
                        next unless $key eq $_[2];

                        my $val = $2;
                        $val =~ s/^"(.*)"$/$1/; # non-standard variant

                        push @res, $val;
                    }
                }
            }
            else
            {
                push @res, $str;
            }
        }

        return @res;
    }

    # SCALAR CONTEXT
    #
    my $str = $_[0]->head->
      header($_[1]);
    return '' unless $str;

    $str =~ s/;\s+(.*?)\s*$//;

    if ( $_[2] )
    {
#	my %param;
        my $params = $1;
        foreach my $param (split /\s*;\s*/, $params )
        {
            if ( $param =~ /^(.*?)\s*=\s*(.*)/ )
            {
                my $key = lc $1;
                next unless $key eq $_[2];

                my $val = $2;
                $val =~ s/^"(.*)"$/$1/; # non-standard variant

                return $val;
#		$param{ $key } = $val;
            }
        }

#	return $param{$_[1]};
    }

    return $str;
}


##############################################################################

=head2 body_header

  $part->body_header( $name )

Returns in scalar context: The first header of $name

Retuns in list context: A list of all $name headers

=cut

sub body_header
{
    # LIST CONTEXT
    return( $_[0]->body_head->header($_[1]) );
}


##############################################################################

=head2 charset_guess

  $part->charset_guess

  $part->charset_guess(\%args)

Args:

  sample => \$data

=cut

sub charset_guess
{
    my( $part, $args ) = @_;

    my $DEBUG = 0;

    my $charset = $part->{'charset'};

    if ( $charset )
    {
        $charset =~ s/'//g;     # Cleanup
        if ( find_encoding($charset) )
        {
            debug "Charset previously set to $charset" if $DEBUG;
            return $charset;
        }
    }

    debug "Determining charset for ".$part->path if $DEBUG;

    $charset = $part->charset;

    # windows-1252 is backward compatible with Latin-1 for all
    # printable chars and many texts that are windows-1252 is labeld
    # as Latin-1
    if ( $charset eq 'iso-8859-1' )
    {
        $charset = 'windows-1252';
    }

    $args ||= {};

    unless( $charset )
    {
#	my $type = $args->{'unwind'} ? $part->type : $part->effective_type;
        my $type = $part->effective_type;
        if ( $type =~ /^text\// )
        {
            my $sample;
            if ( $args->{'sample'} )
            {
#		debug "Finding charset from provided sample";
                $sample = $args->{'sample'};
#		debug "SAMPLE: $$sample"
            }
            else
            {
#		debug "Finding charset from body";
                $sample = $part->body_with_original_charset(2000);
#		debug "BODY SAMPLE: $$sample"
            }

            require Encode::Detect::Detector;
            $charset = lc Encode::Detect::Detector::detect($$sample);

            if ( $charset )
            {
                debug "Got charset from content sample: $charset";
            }
            elsif ( not $part->is_top )
            {
                $charset = $part->top->charset_guess;
            }

            unless( $charset )
            {
                debug "Should guess charset from language";
                debug "Falling back on Latin-1";
                $charset = "iso-8859-1";
            }
        }
    }

    debug "Found charset $charset" if $DEBUG;
    return $part->{'charset'} = $charset;
}


##############################################################################

=head2 url_path

  $part->url_path( $name, $type )

=cut

sub url_path
{
    my( $part, $name, $type_name ) = @_;

    my $email = $part->email;
    my $nid = $email->id;
    my $path = $part->path;
    $path =~ s/\.TEXT$/.1/;     # For embedded messages

    if ( $name )
    {
        my $safe = $part->filename_safe($name,$type_name);

        my $s = $Para::Frame::REQ->session
          or die "Session not found";
        $s->{'email_imap'}{$nid}{$safe} = $path;
        $path = $safe;
    }

    my $email_url = $email->url_path;

#    debug "Returning url_path $email_url$path";

    return $email_url . $path;
}


##############################################################################

=head2 filename_safe

=cut

sub filename_safe
{
    my( $part, $name, $type_name ) = @_;

    $name ||= $part->filename || $part->generate_name;
    $type_name ||= $part->type;

    my $safe = lc $name;
    $safe =~ s/.*[\/\\]//;      # Remove path
    $safe =~ s/\..{1,4}\././;   # Remove multiple extenstions
    my $ext;
    if ( $safe =~ s/\.([^.]*)$// ) # Extract the extenstion
    {
        $ext = $1;
    }

    $safe =~ tr[àáâäãåæéèêëíìïîóòöôõøúùüûýÿðþß]
               [aaaaaaaeeeeiiiioooooouuuuyydps];

    $safe =~ s/[^a-z0-9_\- ]//g;
    $safe =~ s/  / /g;


#    debug "Safe base name: $safe";
#    debug "type name: $type_name";

#    &mime_types_init unless $MIME_TYPES;
    my $MIME_TYPES = MIME::Types->new();

    # Try to figure out octet-streams
    if ( $ext and ($type_name eq 'application/octet-stream') )
    {
        debug "Guessing type from ext $ext for octet-stream";
        if ( my $type = $MIME_TYPES->mimeTypeOf($ext) )
        {
            $type_name = $type->type;
            debug "  Guessed $type_name";
        }
        else
        {
            debug "  No type associated to ext $ext for application/octet-stream";
        }
    }


    if ( $type_name eq 'file/pdf' )
    {
        $type_name = 'application/pdf';
    }

    if ( my $type = $MIME_TYPES->type($type_name) )
    {
        # debug "Got type $type";

        if ( $ext )
        {
            foreach my $e ( $type->extensions )
            {
                if ( $ext eq $e )
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

    $ext ||= 'bin';    # default coupled to 'application/octet-stream'

#    debug "  extension $ext";

    return $safe .'.'. $ext;
}


##############################################################################

=head2 filename

=cut

sub filename
{
    my( $part ) = @_;

    my $name = (
                $part->disp('filename')
                ||
                $part->disp('name')
                ||
                $part->type('filename')
                ||
                $part->type('name')
               );

    if ( $name )                # decode fields
    {
        $name = mime_to_perl_string( $name );
        utf8::upgrade( $name );
    }
    elsif ( $part->type eq "message/rfc822" )
    {
        $name = $part->body_head->parsed_subject->plain.".eml";
    }

    return lc $name;
}

##############################################################################

=head2 generate_name

  $part->generate_name

Generates a non-unique message name for use for attachemnts, et al

=cut

sub generate_name
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 select_renderer

=cut

sub select_renderer
{
    my( $part, $type ) = @_;

#    debug "Selecting renderer for $type";

    my $renderer;
    foreach (
             [ qr{text/plain}            => '_render_textplain'  ],
             [ qr{text/html}             => '_render_texthtml'   ],
             [ qr{multipart/alternative} => '_render_alt'        ],
             [ qr{multipart/mixed}       => '_render_mixed'      ],
             [ qr{multipart/related}     => '_render_related'    ],
             [ qr{image/gif}             => '_render_image'      ],
             [ qr{image/jpeg}            => '_render_image'      ],
             [ qr{image/png}             => '_render_image'      ],
             [ qr{message/rfc822}        => '_render_rfc822'     ],
             [ qr{multipart/parallel}    => '_render_mixed'      ],
             [ qr{multipart/report}      => '_render_mixed'      ],
             [ qr{multipart/}            => '_render_mixed'      ],
             [ qr{text/rfc822-headers}   => '_render_headers'    ],
             [ qr{text/}                 => '_render_textplain'  ],
             [ qr{message/delivery-status}=>'_render_delivery_status' ],
             [ qr{message/disposition-notification}=>'_render_delivery_status' ],
             [ qr{application/pdf}       => '_render_pdf'      ],
            )
    {
        $type =~ $_->[0]
          and $renderer = $_->[1]
            and last;
    }

    return $renderer;
}


##############################################################################

sub _render_textplain
{
    my( $part ) = @_;

#    debug "  rendering textplain - ".$part->path;


    my $data_dec = $part->body;
    my $data_enc = CGI->escapeHTML($$data_dec);

#    my $charset = $part->charset_guess;
#   my $msg = "| $charset\n<br/>\n";
    my $msg = "<br/>\n";
    $data_enc =~ s/\n/<br>\n/g;
    $msg .= $data_enc;

#    debug "  rendering textplain - done";

    return $msg;
}


##############################################################################

sub _render_texthtml
{
    my( $part, $args ) = @_;

    $args ||= {};
    my $minimal = $args->{'minimal'} || 0;

    my $url_path = $part->url_path(undef,'text/html');
    if ( $args->{'tt'} )
    {
        $url_path .= '.tt';
    }


    my $msg = "";

    unless( $minimal )
    {
        $msg .= qq(| <a href="$url_path">View HTML message</a>\n );

        if ( my $other = $part->top->{'other'} )
        {
            foreach my $alt (@$other)
            {
                my $type = $alt->type;
                my $url = $alt->url_path;
                $msg .= " | <a href=\"$url\">View alt in $type</a>\n";
            }
        }
#    debug "  rendering texthtml - ".$part->path." ($url_path)";
        $msg .= "<br>";
    }

    $msg .= <<EOT;
<iframe class="iframe_autoresize_height" src="$url_path" scrolling="auto" marginwidth="0" marginheight="0" frameborder="0" vspace="0" hspace="0" width="100%" height="500" style="overflow:scroll; display:block; position:static"></iframe>

EOT
    ;

#    debug "  rendering texthtml - done";

    return $msg;
}


##############################################################################

sub _render_delivery_status
{
    my( $part ) = @_;

#    debug "  rendering delivery_status - ".$part->path;

    my $data_dec = $part->body;
    my $data_enc = CGI->escapeHTML($$data_dec);

    my $msg = "<div style=\"background:yellow\"><h2>Delivery report</h2>\n";
    $data_enc =~ s/\n/<br>\n/g;
    $msg .= $data_enc;
    $msg .= "</div>\n";

#    debug "  rendering delivery_status - done";

    return $msg;
}


##############################################################################

sub _render_headers
{
    my( $part ) = @_;

#    debug "  rendering headers - ".$part->path;

    my $data_dec = $part->body;
    my $msg;

    my $header = RDF::Base::Email::Head->new($$data_dec );
    unless( $header )
    {
        $msg = "<h3>Malformed header</h3>\n";
        $msg .= $part->_render_textplain;
    }
    else
    {
        $msg = $header->as_html;
    }

#    debug "  rendering headers - done";

    return $msg;
}


##############################################################################

sub _render_alt
{
    my( $part, $args ) = @_;

#    debug "  rendering alt - ".$part->path;

    my @alts = $part->parts;

    my %prio =
      (
       'multipart/related' => 3,
       'text/html' => 2,
       'text/plain' => 0,
      );

#    debug "ALTS: @alts";

    my $choice = shift @alts;
    return "" unless $choice;

#   debug sprintf "Considering %s at %s",
#     $choice->type, $choice->path;
    my $score = $prio{ $choice->type } || 1; # prefere first part

    my @other;

    foreach my $alt (@alts)
    {
        next unless $alt;
        my $type = $alt->type;
#	debug "Considering $type at ".$alt->path;

        unless( $type )
        {
            push @other, $alt;
            next;
        }

        if ( ($prio{$type}||0) > $score )
        {
#	    debug sprintf "  %d is better than %d",
#	      ($prio{$type}||1), $score;
            push @other, $choice;
            $choice = $alt;
            $score = $prio{$type};
        }
        else
        {
#	    debug "  not better";
            push @other, $alt;
        }
    }

    $part->top->{'other'} = \@other;

    my $type = $choice->effective_type;
    my $path = $part->path;

    my $renderer = $part->select_renderer($type);
    unless( $renderer )
    {
        debug "No renderer defined for $type";
        return "<code>No renderer defined for <strong>$type</strong></code>";
    }

#    debug "  rendering alt - done";

    return $choice->$renderer($args);
}


##############################################################################

sub _render_mixed
{
    my( $part, $args ) = @_;

#    debug "  rendering mixed - ".$part->path;


    unless( $part->is_top or $part->parent->effective_type eq 'message/rfc822' )
    {
        # It is possible that the parent should have been a
        # rfc822, but that the email is malformed

        # Treat this as a rfc822 if it has a subject, from or recieved
        # header

        my $h = $part->head_complete;
        if ( $h->header('received') or
             $h->header('from') or
             $h->header('subject') )
        {
#	    debug "Interpart a RFC822";
            my $rfc822 = $part->parent->interpart($part);
            my $msg = $rfc822->_render_rfc822($args);
#	    debug "Interpart a RFC822 - done";
            return $msg;
        }
    }


    debug $part->desig;

    my @alts = $part->parts;

    my $msg = "";

    $part->top->{'attachemnts'} ||= {};

    foreach my $alt (@alts)
    {
        my $apath = $alt->path;

#	debug "  mixed part $apath";

        my $type = $alt->effective_type;
        my $renderer = $part->select_renderer($type);

#	unless( $alt->disp )
#	{
#	    debug "No disp found";
#	    debug $alt->head->as_string;
#	}

        if ( ($alt->disp||'') eq 'inline' )
        {
            if ( $alt ne $alts[0] )
            {
                $msg .= "<hr/>\n";
            }


            if ( $renderer )
            {
                $msg .= $alt->$renderer($args);
            }
            else
            {
                debug "No renderer defined for $type";
                $msg .= "<code>No renderer defined for part $apath <strong>$type</strong></code>";
                $part->top->{'attachemnts'}{$alt->path} = $alt;
            }
        }
        #
        # Part marked as NOT inline
        # ... but if we know how to render the part,
        # we may want to do it anyway.
        #
        elsif ( $renderer )
        {
#	    if( $type eq 'message/rfc822' or
#		$type eq 'multipart/alternative'
#	      )
#	    {
            $msg .= $alt->$renderer($args);
#	    }
#	    else
#	    {
#		$part->top->{'attachemnts'}{$alt->path} = $alt;
#	    }
        }
        else                    # Not requested for inline display
        {
            $part->top->{'attachemnts'}{$alt->path} = $alt;
        }
    }

#    debug "  rendering mixed - done";

    return $msg;
}


##############################################################################

sub _render_related
{
    my( $part, $args ) = @_;

#    debug "  rendering related - ".$part->path;

    my $path = $part->path;

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
        my $apath = $alt->path;

        if ( my $file = $alt->filename )
        {
            $files{$file} = $apath;
        }

        if ( my $cid = $alt->cid )
        {
            $cid =~ s/^<//;
            $cid =~ s/>$//;
            $files{$cid} = $apath;
#	    debug "Path $apath -> $cid";
        }
    }

    my $s = $req->session
      or die "Session not found";
    my $id = $part->email->id;
    foreach my $file ( keys %files )
    {
        $s->{'email_imap'}{$id}{$file} = $files{$file};
    }

    my $choice = shift @alts;
    my $score = $prio{ $choice->effective_type } || 1; # prefere first part

    foreach my $alt (@alts)
    {
        my $type = $alt->effective_type;
        next unless $type;

        if ( ($prio{$type}||0) > $score )
        {
            $choice = $alt;
            $score = $prio{$type};
        }
    }

    my $type = $choice->effective_type;
    my $renderer = $part->select_renderer($type);
    unless( $renderer )
    {
        debug "No renderer defined for $type";
        return "<code>No renderer defined for <strong>$type</strong></code>";
    }

    my $data = $choice->$renderer($args);

#"cid:part1.00090900.07060702@avisita.com"

    my $email_path = $part->email->url_path();
    $data =~ s/(=|")\s*cid:(.+?)("|\s|>)/$1$email_path$files{$2}$3/gi;

#    debug "  rendering related - done";

    return $data;
}


##############################################################################

sub _render_image
{
    my( $part ) = @_;

#    debug "  rendering image - ".$part->path;

    my $url_path = $part->url_path;

    my $desig = $part->filename || "image";
    if ( my $desc = $part->description )
    {
        $desig .= " - $desc";
    }

    my $desig_out = CGI->escapeHTML($desig);

    $part->top->{'attachemnts'} ||= {};
    $part->top->{'attachemnts'}{$part->path} = $part;

#    debug "  rendering image - done";

    return "<img alt=\"$desig_out\" src=\"$url_path\"><br clear=\"all\">\n";
}


##############################################################################

sub _render_pdf
{
    my( $part ) = @_;

    debug "  rendering PDF - ".$part->path;

    my $url_path = $part->url_path;

    $url_path .= '?format=png';

    my $desig = $part->filename || "image";
    if ( my $desc = $part->description )
    {
        $desig .= " - $desc";
    }

    my $desig_out = CGI->escapeHTML($desig);

    $part->top->{'attachemnts'} ||= {};
    $part->top->{'attachemnts'}{$part->path} = $part;

#    debug "  rendering image - done";

    return "<img alt=\"$desig_out\" class=\"wide\" src=\"$url_path\"><br clear=\"all\">\n";
}


##############################################################################

sub _render_rfc822
{
    my( $part, $args ) = @_;

#    debug "  rendering rfc822 - ".$part->path;

#    if( $part->path eq '2.2.2' ) ### DEBUG
#    {
#	my $struct = $part->struct;
#	debug "struct is\n".datadump($struct);
#	debug $part;
#    }

    my $head = $part->body_head;

    my $msg = "";

    $msg .= "\n<br>\n<table class=\"admin\" style=\"background:#E0E0EA\">\n";

    my $subj_lab = CGI->escapeHTML(loc("Subject"));
    my $subj_val = $head->parsed_subject->as_html;
    $msg .= "<tr><td>$subj_lab</td><td width=\"100%\"><strong>$subj_val</strong></td></tr>\n";

    my $from_lab = CGI->escapeHTML(loc("From"));
    my $from_val = $head->parsed_address('from')->as_html;
    $msg .= "<tr><td>$from_lab</td><td>$from_val</td></tr>\n";

    my $date_lab = CGI->escapeHTML(loc("Date"));
    my $date_val = $head->parsed_date->as_html;
    $msg .= "<tr><td>$date_lab</td><td>$date_val</td></tr>\n";

    my $to_lab = CGI->escapeHTML(loc("To"));
    my $to_val = $head->parsed_address('to')->as_html;
    $msg .= "<tr><td>$to_lab</td><td>$to_val</td></tr>\n";

    $msg .= "<tr><td colspan=\"2\" style=\"background:#FFFFE5\">";


    # Create a path to the email
    my $email = $part->email;
    my $nid = $email->id;
    my $subject = $head->parsed_subject->plain;
    my $path = $part->path;
    my $safe = $path .'-'. $part->filename_safe($subject,"message/rfc822");
    my $s = $Para::Frame::REQ->session
      or die "Session not found";
    $s->{'email_imap'}{$nid}{$safe} = $part->path;
    my $eml_path = $email->url_path . $safe;
    $msg .= "<a href=\"$eml_path\">Download email</a>\n";



    my $head_path = $part->url_path. ".head";
    $msg .= "| <a href=\"$head_path\">View Headers</a>\n";

    my $sub = $part->body_part;
    my $sub_type = $sub->effective_type;
    my $renderer = $sub->select_renderer($sub_type);

    unless( $renderer )
    {
        my $sub_path = $sub->path;
        debug "No renderer defined for $sub_type";
        return "<code>No renderer defined for part $sub_path <strong>$sub_type</strong></code>";
    }

    $msg .= $sub->$renderer($args);

    $msg .= "</td></tr></table>\n";

#    debug "  rendering rfc822 - done";

    return $msg;
}


##############################################################################

=head2 body_with_sensible_charset

  returns( $bodyref, $charset )

=cut

sub body_with_sensible_charset
{
    my( $part, $length, $args ) = @_;

    my $dataref = $part->body_with_original_charset( $length, $args );

    unless( $part->type =~ m/^text\// )
    {
        return( $dataref, undef );
    }

    $args ||= {};

    my $charset = $part->charset_guess({%$args,sample=>$dataref});
#    debug "Body charset is $charset";
#    debug "Data ".validate_utf8($dataref);
    if ( $charset eq 'iso-8859-1' )
    {
        # No changes
    }
    elsif ( $charset eq 'windows-1252' )
    {
        # No changes
    }
    elsif ( $charset eq 'utf-8' )
    {
#        debug "Decode utf8 to internal format";
        utf8::decode( $$dataref );
    }
    else
    {
#	debug "decoding from $charset";
        eval
        {
#            my $decoder = find_encoding($charset);

#            debug "BEFORE ".validate_utf8($dataref);

            $$dataref = decode($charset,$$dataref);
            $charset = 'utf-8'; # Now utf-8


#            debug "AFTER ".validate_utf8($dataref);
        } or do
        {
            debug "Failed decoding body: ".$@;
#            debug "Removing faulty charset ".$part->{'charset'};
#            $part->{'charset'} = undef; # fallback
        };
    }


    return( $dataref, $charset);
}


##############################################################################

=head2 body_with_original_charset

=cut

sub body_with_original_charset
{
    my( $part, $length, $args ) = @_;

    my $encoding = $part->encoding;
    my $dataref = $part->body_raw( $length );

    unless( $encoding )
    {
        my $path = $part->path;
#	debug "No encoding found for body $path. Using 8bit";
        $encoding = '8bit';
    }

#    debug "Original body with encoding $encoding: ".$dataref;

    if ( $encoding eq 'quoted-printable' )
    {
        $dataref = \ decode_qp($$dataref);
    }
    elsif ( $encoding eq '8bit' )
    {
        #
    }
    elsif ( $encoding eq 'binary' )
    {
        #
    }
    elsif ( $encoding eq '7bit' )
    {
        #
    }
    elsif ( $encoding eq 'base64' )
    {
        $dataref = \ decode_base64($$dataref);
    }
    else
    {
        die "encoding $encoding not supported";
    }

    return $dataref;
}


##############################################################################

=head2 body

Always returns string in perl character encoding

Returns scalar ref

=cut

sub body
{
    my( $part, $length, $args ) = @_;

    my $dataref = $part->body_with_original_charset( $length, $args );

    unless( $part->type =~ m/^text\// )
    {
        return $dataref;
    }

    # RB::Email::RB takes body from DB and is already valid utf8. Only
    # decode body if it is not marked and valid.
    #
    if ( utf8::is_utf8($$dataref) and utf8::valid($$dataref) )
    {
        return $dataref;
    }

    $args ||= {};

    my $charset = $part->charset_guess({%$args,sample=>$dataref});
#    debug "Body charset is $charset";
#    debug "Data ".validate_utf8($dataref);
    eval
    {
#        debug "BEFORE ".validate_utf8($dataref);

        $$dataref = decode($charset,$$dataref);

#        debug "AFTER ".validate_utf8($dataref);
    } or do
    {
        debug "Failed decoding body: ".$@;
    };

    return $dataref;
}


##############################################################################

=head2 body_raw

=cut

sub body_raw
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 body_part

=cut

sub body_part
{
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 guess_content_part

=cut

sub guess_content_part
{
    my( $part ) = @_;

    my $ctype = "text/plain";

    # Prefere html for some systems
    my $return_path = $part->header('return-path')||'';
    if ( $return_path =~ /\@live\.\w\w\w?>/ )
    {
        $ctype = "text/html";
    }

    my( $cpart );
    if ( $part->effective_type eq $ctype )
    {
        $cpart = $part;
    }
    elsif ( $part->effective_type =~ /multipart/i )
    {
        ($cpart) = $part->first_part_with_type($ctype);
    }

    $cpart ||= $part->first_non_multi_part() || $part;

    return $cpart;
}


##############################################################################

=head2 body_as_text

returns in list context: ($bodyr, $ct_source)

returns in scalar context: $bodyr

=cut

sub body_as_text
{
    my( $part ) = shift @_;

    my( $bodyr, $ct_source );

    my $ctype = $part->effective_type;
    if ( $ctype eq 'text/plain' )
    {
        $ct_source =  'plain';
        $bodyr = $part->body(@_);
    }
    elsif ( $ctype eq 'text/html' )
    {
#        debug "Returning body as text from html";
        require HTML::TreeBuilder;
        my $tree = HTML::TreeBuilder->new_from_content($part->body(@_));
        require HTML::FormatText;
        my $formatter = HTML::FormatText->new(leftmargin => 0,
                                              rightmargin => 1000);
        $ct_source =  'html';
        $bodyr = \ $formatter->format($tree);
    }
    else
    {
        debug "Content-type $ctype not handled in body_as_text";
        #return( $part->body(@_), undef );

        $ct_source =  '';
        $bodyr = \ "";
    }

#    debug "body_as_text returning ".(wantarray?'list':'scalar');
#    debug "  ($bodyr, $ct_source)";
    return wantarray ? ($bodyr, $ct_source) : $bodyr;

}


##############################################################################

=head2 body_extract

Returns a string

=cut

sub body_extract
{
    my( $part ) = @_;

    # Tested on 17026070 18603873 18603623 18603599
    # 17484078 17511721* 18380590* 18571911 6256684* 7485060* 7545438*

    my $cpart = $_[0]->guess_content_part;
    my( $bodyr, $ct_source ) = $cpart->body_as_text(8000);
    return "" unless $ct_source;
    my $str = $$bodyr;
    my $length = length($str);
    my $trunc = 0;

    # Remove header
    #
    $str =~ s/^\s*//;
    my @p;                      # Paragraphs of content
    for (0..2)
    {
        $str =~ s/^(.*?(\h*\r?\n)+)//s or last;
        push @p, $1;
    }
    push @p, $str if length($str);

    for ( my $i=0; $i<=$#p; $i++ )
    {
        my $len1 = length($p[$i]);
        my $len2 = length($p[$i+1]||'');
#        debug "Part $i: ".$p[$i];

        if ( $len1 < 40 and $len2-$len1 > 20 )
        {
#            debug "  len ".$len1;
#            debug "  next is ".$len2;
            debug "Cutting out header: ".$p[$i];
            $p[$i] = '';
            $trunc ++;
            next;
        }

        last;
    }
    $str = join '', @p;

    my $body = $part->footer_remove($str);

    # Reformat
    $body =~ s/(\h*\r?\n){2,}/\n\n/g;
    $body =~ s/\s*$//;
    if ( $ct_source eq 'plain' )
    {
        $body =~ s/^(.{70,}?)\h*\r?\n(\S+)/$1 $2/mg;
    }

#    if( $trunc ){ $body .= " \x{2026}" }

    return $body;
}


##############################################################################

=head2 viewtree

=cut

sub viewtree
{
    my( $part, $ident ) = @_;

    $ident ||= 0;

#debug "t1";
    my $type = $part->type      || '-';
#debug "t2";
    my $enc  = $part->encoding  || '-';
#debug "t3";
    my $size = $part->size      || '-';
#debug "t4";
    my $disp = $part->disp      || '-';
#debug "t5";
    my $char = $part->charset   || '-';
#debug "t6";
    my $file = $part->disp('filename') || '-';
#debug "t7";
    my $path = $part->path;
#debug "t8";

#    my $lang = $struct->{lang}   || '-';
#    my $loc = $struct->{loc}     || '-';
#    my $cid = $struct->{cid}     || '-';
#    my $desc = $struct->description || '-';

    my $msg = ('  'x$ident)."$path $type $enc $size $disp $char $file\n";
#    debug $msg;
    $ident ++;
    foreach my $subpart ( $part->parts )
    {
#	debug "  subpart $subpart";
        $msg .= $subpart->viewtree($ident);
    }

    if ( $part->guess_type eq 'message/rfc822' )
    {
        if ( my $body_part = $part->body_part )
        {
#            debug "  body_part";
            $msg .= $body_part->viewtree($ident);
        }
        else
        {
#            debug "  body_part missing";
        }
    }
    else
    {
#        debug "  no body_part";
    }

    return $msg;
}


##############################################################################

=head2 tick

=cut

sub tick
{
    my $subn = (caller(1))[3];
    $subn =~ s/.*:://;
    return $_[0]->path.':'.$subn.'>';
}


##############################################################################

# MUST BE INITIATED BEFORE FORK!

#sub mime_types_init
#{
#    $MIME_TYPES = MIME::Types->new;
#    my @types;
#
##    push @types, (
###		  MIME::Type->new(
###				  encoding => 'quoted-printable',
###				  extensions => ['xlsx'],
###				  type => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
###				 ),
###		  MIME::Type->new(
###				  encoding => 'base64',
###				  extensions => ['xcf'],
###				  type => 'image/x-xcf',
###				 ),
###		  MIME::Type->new(
###				  extensions => ['jpg'],
###				  type => 'image/jpg',
###				 ),
##		 );
##    $MIME_TYPES->addType(@types);
#
#    # Added in MIME::Types v1.24
##    $MIME_TYPES->type('message/rfc822')->{'MT_extensions'} = ['eml'];
#}
#

##############################################################################

=head2 desig

=cut

sub desig
{
    my( $part ) = @_;

    return $part->generate_name;
}

##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $part ) = @_;

    return $part->generate_name;
}

##############################################################################

=head2 is_top

=cut

sub is_top
{
    return 0;
}

##############################################################################

=head2 match

Expecting the normal case of html email and/or plain text email

=cut

sub match
{
    my( $part, $qx_in ) = @_;

    my $part_plain = $part->first_part_with_type('text/plain');
    my $part_html = $part->first_part_with_type('text/html');

    my $qx = qr/$qx_in/;

    if ( $part_html and ${$part_html->body} =~ $qx )
    {
        debug "match in html part";
        return 1;
    }
    elsif ( $part_plain and ${$part_plain->body} =~ $qx )
    {
        debug "match in plain part";
        return 1;
    }
    elsif ( $part->effective_type =~ /^text\// and
            ${$part->body} =~ $qx )
    {
        debug "match in only part";
        return 1;
    }

    debug "No match in html or plain";
    return 0;
}


##############################################################################

=head2 attachments

=cut

sub attachments
{
    my( $part ) = @_;

    my $top = $part->top;
    my $attachments = $top->{'attachemnts'};
    unless( $attachments )
    {
        my $type = $top->type;
        my $renderer = $top->select_renderer($type);
        unless( $renderer )
        {
            debug "No renderer defined for $type";
            return "";
        }

        # Somewhat wasteful. Should maby optimize for only getting
        # attachments
        #
        $top->$renderer({only_attachments=>1});

        $attachments = $top->{'attachemnts'};
    }

    return $attachments;
}


##############################################################################

=head2 attachments_as_html

=cut

sub attachments_as_html
{
    my( $part ) = @_;
    my $atts = $part->attachments;

    my $msg = "";

    if ( keys %$atts )
    {
        my $nid = $part->email->id;

        $msg .= "<ol>\n";

        foreach my $att ( sort values %$atts )
        {
            my $name = $att->filename || $att->generate_name;
            my $desc = $att->description;

            my $name_enc = CGI->escapeHTML($name);
            my $desc_enc = CGI->escapeHTML($desc);

            my $type = $att->effective_type;
            my $size_human = $att->size_human;

            my $url_path = $att->url_path($name);
            my $path = $att->path;

            my $mouse_over =
              "onmouseover=\"TagToTip('email_file_$nid/$path',DELAY,1000,OFFSETY,20,DURATION,10000)\"";

            my $desig = "<a href=\"$url_path\">$name_enc</a>";
            if ( $desc and (lc($desc) ne lc($name) ) )
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


##############################################################################

=head2 footer_remove

  $body = footer_remove($str)

Also used from E::Classifier

=cut

sub footer_remove
{
    my( $part, $str ) = @_;

    $str =~ s/^(--|____)[^a-zA-Z]*\n.*//ms;

    ### Find common ending phrases

    $str =~ s/\v+\s*\*?( Med.vänlig.hälsning
              | Bästa.hälsningar
              | (Best|Kind).Regards
              | Mvh\s*
              | Med.vänliga.hälsningar
              | Vänligen\h*\v
              | Trevlig.fortsättning
              | \/\/\s*\w\w+
              ).*//soxi;

    ### Remove comments
#    $str =~ s/\v+>+.*//soxi;

    # Find common ending politeness phrases
    #
    $str =~ s/\v+\s*( Tack.(för.hjälpen.)?på.förhand
              | Tack
              )\W*\s*$//soxi;

#    # Name without phrase
#    if( my $from = $part->head->parsed_address('from')->get_first_nos )
#    {
#        if( my $name = $from->name )
#        {
#            debug "Posted by $name";
#            $str =~ s/\v+\s*$name.*$//im;
#        }
#    }


    return $str;
}


##############################################################################

=head2 classified

=cut

sub classified
{
    my( $part ) = @_;
    return $part->{'classified'} =
      RDF::Base::Email::Classifier->new( $part->top );
}


##############################################################################

1;
