#  $Id$  -*-cperl-*-
package Rit::Base::Email::Part;
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

Rit::Base::Email::Part

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck shortmess );
use Scalar::Util qw(weaken);
use MIME::Words qw( decode_mimewords );
use MIME::QuotedPrint qw(decode_qp);
use MIME::Base64 qw( decode_base64 );
use MIME::Types;
use CGI;
use Number::Bytes::Human qw(format_bytes);
use File::MMagic::XS qw(:compat);

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::Head;
use Rit::Base::Email::Raw::Part;
use Rit::Base::Email::Interpart;

use constant EA => 'Rit::Base::Literal::Email::Address';

our $MIME_TYPES;


#######################################################################

=head2 new

=cut

sub new
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 interpart

=cut

sub interpart
{
    return Rit::Base::Email::Interpart::new(shift, @_);
}


#######################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 top

=cut

sub top
{
    return $_[0]->{'top'} or die "Top part not given";
}


#######################################################################

=head2 folder

=cut

sub folder
{
    confess "WRONG TURN";
}


#######################################################################

=head2 struct

=cut

sub struct
{
    confess "WRONG TURN";
}



#######################################################################

=head2 exist

Is the content of this part availible?

=cut

sub exist
{
    return 1;
}


#######################################################################

=head2 email

=cut

sub email
{
    return $_[0]->{'email'};
}


#######################################################################

=head2 envelope

=cut

sub envelope
{
    die "IMPLEMENT ME";
}


#######################################################################

=head2 first_part_with_type

=cut

sub first_part_with_type
{
    my( $part, $type ) = @_;
    my $class = ref($part);

    foreach my $sub ( $part->parts )
    {
	if( $sub->type =~ /^$type/ )
	{
	    return $sub;
	}
	elsif( $sub->type =~ /^multipart\// )
	{
	    if( my $match = $sub->first_part_with_type($type) )
	    {
		return $match;
	    }
	}
    }

    return undef;
}


#######################################################################

=head2 first_non_multi_part

=cut

sub first_non_multi_part
{
    my( $part ) = @_;
    my $class = ref($part);

    if( $part->type =~ /^multipart\// )
    {
	my( $sub ) = ($part->parts)[0]
	  or return $part; # type may be wrong
	return $sub->first_non_multi_part;
    }

    return $part;
}


#######################################################################

=head2 parts


Returns: A list of parts, not counting itself

=cut

sub parts
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 path

=cut

sub path
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 parent

=cut

sub parent
{
    unless( $_[0]->{'parent'} )
    {
	debug datadump $_[0];
	confess "no parent";
    }
    return $_[0]->{'parent'};
}


#######################################################################

=head2 charset

=cut

sub charset
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 encoding

=cut

sub encoding
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 cid

=cut

sub cid
{
    return $_[0]->head->header('content-id') ||
      $_[0]->head->header('content-location','cid');
}


#######################################################################

=head2 type

Alias: content_type

=cut

sub type
{
    confess "NOT IMPLEMENTED";
}

*content_type = \&type;


#######################################################################

=head2 effective_type

  $part->effective_type

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
    if( $_[0]->{'effective_type'} )
    {
	return $_[0]->{'effective_type'};
    }

    my $type_name = $_[0]->type;
    if( $type_name eq 'application/octet-stream' )
    {
	$_[0]->filename =~ /\.([^\.]+)$/;
	if( my $ext = $1 )
	{
	    if( my $type = $MIME_TYPES->mimeTypeOf($ext) )
	    {
		$type_name = $type->type;
	    }
	}
    }
    elsif( $type_name eq 'multipart/mixed' )
    {
	# May be a nonstandard embedded rfc822
#	debug "*** looking at mixed part";
#	debug $_[0]->head->as_string;
    }
    elsif( not $MIME_TYPES->type($type_name) )
    {
	debug "Mime-type $type_name not recognized";
#	cluck "HERE";
	$type_name = $_[0]->guess_type;
    }

    return $_[0]->{'effective_type'} = $type_name;
}


#######################################################################

=head2 guess_type

  $part->guess_type

Called from L</effective_type> when the content-type is not
recognized. Guesses the content-type from the part body.

Returns: A plain scalar string of the mime-type

=cut

sub guess_type
{
    my( $part ) = @_;

    # For large headers...
    my $body_part = $part->body(5000, {unwind=>1}); # calls charset_guess

    my $m = File::MMagic::XS->new();
    my $res = $m->checktype_contents($$body_part);
    $res ||= 'application/octet-stream';


#   debug "Guessed content type '$res'";

    if( $res eq 'message/rfc822' )
    {
	# Assume we have to convert to raw part
	# ... (the need for it could be checked)
#	$part->{'_convert_to_raw'} = 1;
#	debug "should convert to raw part"; ### DEBUG
    }

    return $res;
}


#######################################################################

=head2 disp

=cut

sub disp
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 description

=cut

sub description
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

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


#######################################################################

=head2 size_human

=cut

sub size_human
{
    my $size = $_[0]->size;
    if( defined $size )
    {
	return format_bytes($size);
    }

    return "";
}


#######################################################################

=head2 body_head_complete

  $part->body_head_complete()

This will return the headers of the rfc822 part.



Returns: a L<Rit::Base::Email::Head> object

=cut

sub body_head_complete
{
    confess "NOT IMPLEMENTED";
}

#######################################################################

=head2 body_head

  $part->body_head()

The returned head object may not contain all the headers. See
L<Rit::Base::Email::IMAP::Head>

See L</body_head_complete>.

Returns: a L<Rit::Base::Email::Head> object

=cut

sub body_head
{
    return shift->body_head_complete(@_);
}


#######################################################################

=head2 head_complete

  $part->head_complete()

This will return the head of the current part.

Returns: a L<Rit::Base::Email::Head> object

Alias: header_obj()

=cut

sub head_complete
{
    confess "NOT IMPLEMENTED";
}

*header_obj = \&head_complete;

#######################################################################

=head2 head

  $part->head()

The returned head object may not contain all the headers. See
L<Rit::Base::Email::IMAP::Head>

See L</head_complete>.

Returns: a L<Rit::Base::Email::Head> object

=cut

sub head
{
    return shift->head_complete(@_);
}

#######################################################################

=head2 header

  $part->header( $name )

Returns in scalar context: The first header of $name

Retuns in list context: A list of all $name headers

=cut

sub header
{
    if( wantarray )
    {
	my( @h ) = $_[0]->head->
	  header($_[1]);

	my @res;

	foreach my $str (@h )
	{
	    $str =~ s/;\s+(.*?)\s*$//;

	    if( $_[2] )
	    {
		my $params = $1;
		foreach my $param (split /\s*;\s*/, $params )
		{
		    if( $param =~ /^(.*?)\s*=\s*(.*)/ )
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
    return undef unless $str;

    $str =~ s/;\s+(.*?)\s*$//;

    if( $_[2] )
    {
#	my %param;
	my $params = $1;
	foreach my $param (split /\s*;\s*/, $params )
	{
	    if( $param =~ /^(.*?)\s*=\s*(.*)/ )
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


#######################################################################

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


#######################################################################

=head2 charset_guess

  $part->charset_guess

  $part->charset_guess(\%args)

Args:

  sample => \$data

=cut

sub charset_guess
{
    my( $part, $args ) = @_;

#    debug "Determining charset";

    my $charset = $part->charset;
    $args ||= {};

    unless( $charset )
    {
	my $type = $args->{'unwind'} ? $part->type :
	  $part->effective_type;
	if( $type =~ /^text\// )
	{
	    my $sample;
	    if( $args->{'sample'} )
	    {
#		debug "Finding charset from provided sample";
		$sample = $args->{'sample'};
#		debug "SAMPLE: $$sample"
	    }
	    else
	    {
#		debug "Finding charset from body";
		$sample = $part->body(2000, {unwind=>1});
#		debug "BODY SAMPLE: $$sample"
	    }

	    require Encode::Detect::Detector;
	    $charset = lc Encode::Detect::Detector::detect($$sample);

	    if( $charset )
	    {
		debug "Got charset from content sample: $charset";
	    }
	    elsif( $part->top ne $part->parent )
	    {
		$charset = $part->top->body_part->charset_guess;
	    }

	    unless( $charset )
	    {
		debug "Should guess charset from language";
		debug "Falling back on Latin-1";
		$charset = "iso-8859-1";
	    }
	}
    }

#    debug "Found charset $charset";
    return $charset;
}


#######################################################################

=head2 url_path

  $part->url_path( $name, $type )

=cut

sub url_path
{
    my( $part, $name, $type_name ) = @_;

    my $email = $part->email;
    my $nid = $email->id;
    my $path = $part->path;
    $path =~ s/\.TEXT$/.1/; # For embedded messages

    if( $name )
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


#######################################################################

=head2 filename_safe

=cut

sub filename_safe
{
    my( $part, $name, $type_name ) = @_;

    $name ||= $part->filename || $part->generate_name;
    $type_name ||= $part->type;

    my $safe = lc $name;
    $safe =~ s/.*[\/\\]//; # Remove path
    $safe =~ s/\..{1,4}\././;  # Remove multiple extenstions
    my $ext;
    if( $safe =~ s/\.([^.]*)$// ) # Extract the extenstion
    {
	$ext = $1;
    }

    $safe =~ tr[àáâäãåæéèêëíìïîóòöôõøúùüûýÿðþß]
               [aaaaaaaeeeeiiiioooooouuuuyydps];

    $safe =~ s/[^a-z0-9_\- ]//g;
    $safe =~ s/  / /g;


#    debug "Safe base name: $safe";
#    debug "type name: $type_name";

    unless( $MIME_TYPES ) # Initialize $MIME_TYPES
    {
	$MIME_TYPES = MIME::Types->new;
	my @types;

	push @types, (
		      MIME::Type->new(
				      encoding => 'quoted-printable',
				      extensions => ['xlsx'],
				      type => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
				     ),
		     );
	$MIME_TYPES->addType(@types);

	# Not in db! :-P
	$MIME_TYPES->type('message/rfc822')->{'MT_extensions'} = ['eml'];
    }




    # Try to figure out octet-streams
    if( $ext and ($type_name eq 'application/octet-stream') )
    {
	debug "Guessing type from ext $ext for octet-stream";
	if( my $type = $MIME_TYPES->mimeTypeOf($ext) )
	{
	    $type_name = $type->type;
	    debug "  Guessed $type_name";
	}
	else
	{
	    debug "  No type associated to ext $ext for application/octet-stream";
	}
    }


    if( $type_name eq 'file/pdf' )
    {
	$type_name = 'application/pdf';
    }

    if( my $type = $MIME_TYPES->type($type_name) )
    {
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

    $ext ||= 'bin'; # default coupled to 'application/octet-stream'

#    debug "  extension $ext";

    return $safe .'.'. $ext;
}


#######################################################################

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

    if( $name ) # decode fields
    {
	$name = decode_mimewords( $name );
	utf8::upgrade( $name );
    }
    elsif( $part->type eq "message/rfc822" )
    {
	$name = $part->body_head->parsed_subject->plain.".eml";
    }

    return lc $name;
}

#######################################################################

=head2 generate_name

  $part->generate_name

Generates a non-unique message name for use for attatchemnts, et al

=cut

sub generate_name
{
    my( $part ) = @_;

    my $name = "email".$part->top->uid;
    $name .= "-part".$part->path;
    return $name;
}


#######################################################################

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
	     [ qr{image/}                => '_render_image'      ],
	     [ qr{message/rfc822}        => '_render_rfc822'     ],
	     [ qr{multipart/parallel}    => '_render_mixed'      ],
	     [ qr{multipart/report}      => '_render_mixed'      ],
	     [ qr{multipart/}            => '_render_mixed'      ],
	     [ qr{text/rfc822-headers}   => '_render_headers'    ],
	     [ qr{text/}                 => '_render_textplain'  ],
	     [ qr{message/delivery-status}=>'_render_delivery_status' ],
	    )
    {
        $type =~ $_->[0]
	  and $renderer = $_->[1]
            and last;
    }

    return $renderer;
}


#######################################################################

sub _render_textplain
{
    my( $part ) = @_;

#    debug "  rendering textplain - ".$part->path;


    my $data_dec = $part->body;
    my $data_enc = CGI->escapeHTML($$data_dec);

    my $charset = $part->charset_guess;
#   my $msg = "| $charset\n<br/>\n";
     my $msg = "<br/>\n";
    $data_enc =~ s/\n/<br>\n/g;
    $msg .= $data_enc;

#    debug "  rendering textplain - done";

    return $msg;
}


#######################################################################

sub _render_texthtml
{
    my( $part ) = @_;


    my $url_path = $part->url_path(undef,'text/html');

    my $msg = qq(| <a href="$url_path">View HTML message</a>\n );

    if( my $other = $part->top->{'other'} )
    {
	foreach my $alt (@$other)
	{
	    my $type = $alt->type;
	    my $url = $alt->url_path;
	    $msg .= " | <a href=\"$url\">View alt in $type</a>\n";
	}
    }

#    debug "  rendering texthtml - ".$part->path." ($url_path)";

$msg .= <<EOT;
<br>
<iframe class="iframe_autoresize" src="$url_path" scrolling="no" marginwidth="0" marginheight="0" frameborder="0" vspace="0" hspace="0" width="100%" style="overflow:visible; display:block; position:static"></iframe>

EOT
;

#    debug "  rendering texthtml - done";

    return $msg;
}


#######################################################################

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


#######################################################################

sub _render_headers
{
    my( $part ) = @_;

#    debug "  rendering headers - ".$part->path;

    my $data_dec = $part->body;
    my $msg;

    my $header = Rit::Base::Email::Head->new($$data_dec );
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


#######################################################################

sub _render_alt
{
    my( $part ) = @_;

#    debug "  rendering alt - ".$part->path;

    my @alts = $part->parts;

    my %prio =
      (
       'multipart/related' => 3,
       'text/html' => 2,
       'text/plain' => 0,
      );

    my $choice = shift @alts;
#   debug sprintf "Considering %s at %s",
#     $choice->type, $choice->path;
    my $score = $prio{ $choice->type } || 1; # prefere first part

    my @other;

    foreach my $alt (@alts)
    {
	my $type = $alt->type;
#	debug "Considering $type at ".$alt->path;

	unless( $type )
	{
	    push @other, $alt;
	    next;
	}

	if( ($prio{$type}||0) > $score )
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

    return $choice->$renderer;
}


#######################################################################

sub _render_mixed
{
    my( $part ) = @_;

#    debug "  rendering mixed - ".$part->path;


    unless( $part->parent->effective_type eq 'message/rfc822' )
    {
	# It is possible that the parent should have been a
	# rfc822, but that the email is malformed

	# Treat this as a rfc822 if it has a subject, from or recieved
	# header

	my $h = $part->head_complete;
	if( $h->header('received') or
	    $h->header('from') or
	    $h->header('subject') )
	{
#	    debug "Interpart a RFC822";
	    my $rfc822 = $part->parent->interpart($part);
	    my $msg = $rfc822->_render_rfc822;
#	    debug "Interpart a RFC822 - done";
	    return $msg;
	}
    }


#    debug $part->desig;

    my @alts = $part->parts;

    my $msg = "";

    $part->top->{'attatchemnts'} ||= {};

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

	if( ($alt->disp||'') eq 'inline' )
	{
	    if( $alt ne $alts[0] )
	    {
		$msg .= "<hr/>\n";
	    }


	    if( $renderer )
	    {
		$msg .= $alt->$renderer;
	    }
	    else
	    {
		debug "No renderer defined for $type";
		$msg .= "<code>No renderer defined for part $apath <strong>$type</strong></code>";
		$part->top->{'attatchemnts'}{$alt->path} = $alt;
	    }
	}
	#
	# Part marked as NOT inline
	# ... but if we know how to render the part,
	# we may want to do it anyway.
	#
	elsif( $renderer )
	{
#	    if( $type eq 'message/rfc822' or
#		$type eq 'multipart/alternative'
#	      )
#	    {
		$msg .= $alt->$renderer;
#	    }
#	    else
#	    {
#		$part->top->{'attatchemnts'}{$alt->path} = $alt;
#	    }
	}
	else # Not requested for inline display
	{
	    $part->top->{'attatchemnts'}{$alt->path} = $alt;
	}
    }

#    debug "  rendering mixed - done";

    return $msg;
}


#######################################################################

sub _render_related
{
    my( $part ) = @_;

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

	if( my $file = $alt->filename )
	{
	    $files{$file} = $apath;
	}

	if( my $cid = $alt->cid )
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

    my $type = $choice->effective_type;
    my $renderer = $part->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }

    my $data = $choice->$renderer;

#"cid:part1.00090900.07060702@avisita.com"

    my $email_path = $part->email->url_path();
    $data =~ s/(=|")\s*cid:(.+?)("|\s|>)/$1$email_path$files{$2}$3/gi;

#    debug "  rendering related - done";

    return $data;
}


#######################################################################

sub _render_image
{
    my( $part ) = @_;

#    debug "  rendering image - ".$part->path;

    my $url_path = $part->url_path;

    my $desig = $part->filename || "image";
    if( my $desc = $part->description )
    {
	$desig .= " - $desc";
    }

    my $desig_out = CGI->escapeHTML($desig);

    $part->top->{'attatchemnts'} ||= {};
    $part->top->{'attatchemnts'}{$part->path} = $part;

#    debug "  rendering image - done";

    return "<img alt=\"$desig_out\" src=\"$url_path\"><br clear=\"all\">\n";
}


#######################################################################

sub _render_rfc822
{
    my( $part ) = @_;

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

    $msg .= $sub->$renderer;

    $msg .= "</td></tr></table>\n";

#    debug "  rendering rfc822 - done";

    return $msg;
}


#######################################################################

=head2 body

=cut

sub body
{
    my( $part, $length, $args ) = @_;

    my $encoding = $part->encoding;
    my $dataref = $part->body_raw( $length );

    unless( $encoding )
    {
	debug "No encoding found for body. Using 8bit";
	$encoding = '8bit';
    }

    if( $encoding eq 'quoted-printable' )
    {
	$dataref = \ decode_qp($$dataref);
    }
    elsif( $encoding eq '8bit' )
    {
	#
    }
    elsif( $encoding eq 'binary' )
    {
	#
    }
    elsif( $encoding eq '7bit' )
    {
	#
    }
    elsif( $encoding eq 'base64' )
    {
	$dataref = \ decode_base64($$dataref);
    }
    else
    {
	die "encoding $encoding not supported";
    }

    $args ||= {};
#    debug "unwinding";
    return $dataref if $args->{'unwind'};

#    debug datadump $args;

    my $charset = $part->charset_guess({%$args,sample=>$dataref});
    if( $charset eq 'iso-8859-1' )
    {
	# No changes
    }
    elsif( $charset eq 'utf-8' )
    {
	utf8::decode( $$dataref );
    }
    else
    {
	debug "Should decode charset $charset";
    }


    return $dataref;
}


#######################################################################

=head2 body_raw

=cut

sub body_raw
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 body_part

=cut

sub body_part
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 desig

=cut

sub desig
{
    my( $part, $ident ) = @_;

    $ident ||= 0;

    my $type = $part->type      || '-';
    my $enc  = $part->encoding  || '-';
    my $size = $part->size      || '-';
    my $disp = $part->disp      || '-';
    my $char = $part->charset   || '-';
    my $file = $part->disp('filename') || '-';
    my $path = $part->path;

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
	$msg .= $subpart->desig($ident);
    }

    if( my $body_part = $part->body_part )
    {
	$msg .= $body_part->desig($ident);
    }

    return $msg;
}


#######################################################################

=head2 tick

=cut

sub tick
{
    my $subn = (caller(1))[3];
    $subn =~ s/.*:://;
    return $_[0]->path.':'.$subn.'>';
}


#######################################################################

1;
