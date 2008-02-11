#  $Id$  -*-cperl-*-
package Rit::Base::Email::Part;
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

Rit::Base::Email::Part

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
use MIME::Words qw( decode_mimewords );
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
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs alfanum_to_id is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::Head;

use constant EA => 'Rit::Base::Literal::Email::Address';

#######################################################################

=head2 new

=cut

sub new
{
    confess "NOT IMPLEMENTED";
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
    return $_[0]->{'struct'} or die "Struct not given";
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

=head2 parts

=cut

sub parts
{
    my( $part ) = @_;
    my $class = ref($part);

    my @parts;
    foreach my $struct ( $part->struct->parts )
    {
	push @parts, $part->new($struct);
    }

    return \@parts;
}


#######################################################################

=head2 path

=cut

sub path
{
    return $_[0]->struct->part_path;
}


#######################################################################

=head2 charset

=cut

sub charset
{
    return lc $_[0]->struct->charset;
}


#######################################################################

=head2 type

=cut

sub type
{
    return lc $_[0]->struct->type;
}


#######################################################################

=head2 disp

=cut

sub disp
{
    return lc $_[0]->struct->disp;
}


#######################################################################

=head2 charset_guess

=cut

sub charset_guess
{
    my( $part ) = @_;

#    debug "Determining charset";

    my $struct = $part->struct;
    my $charset = lc $struct->charset;

    unless( $charset )
    {
	my $params = $struct->{'params'};
	foreach my $key (keys %$params )
	{
	    if( lc($key) eq 'charset' )
	    {
		$charset = lc( $params->{$key} );
		last;
	    }
	}
    }

    unless( $charset )
    {
	my $type = lc $struct->type;
	if( $type =~ /^text\// )
	{
	    my $sample = $part->bodypart_decoded(2000);
	    require Encode::Detect::Detector;
	    $charset = lc Encode::Detect::Detector::detect($sample);

	    if( $charset )
	    {
		debug "Got charset from content sample: $charset";
	    }
	    else
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

    return $charset;
}


#######################################################################

=head2 url_path

TODO: Make path base a config

=cut

sub url_path
{
    my( $part, $name ) = @_;

    my $home = $Para::Frame::REQ->site->home_url_path;
    my $nid = $part->email->id;
    my $path = $part->path;
    $path =~ s/\.TEXT$/.1/; # For embedded messages

    if( $name )
    {
	my $safe = $part->filename_safe($name);

	my $s = $Para::Frame::REQ->session
	  or die "Session not found";
	$s->{'email_imap'}{$nid}{$safe} = $path;
	$path = $safe;
    }

    return "$home/admin/email/files/$nid/$path";
}


#######################################################################

=head2 filename_safe

=cut

sub filename_safe
{
    my( $part, $name ) = @_;

    $name ||= $part->filename || $part->generate_name;

    my $type_name = $part->type;

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

=head2 filename

=cut

sub filename
{
    my( $part ) = @_;

    my $struct = $part->struct;
    my $name = $struct->filename;

    unless( $name )
    {
	my $display_raw = $struct->{'disp'};
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
	if( my $params = $struct->{'params'} )
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
	my $type = lc $struct->type;
	if( $type eq "message/rfc822" )
	{
	    $name = $struct->{'envelope'}{'subject'} .".eml";
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

=head2 generate_name

  $part->generate_name

Generates a non-unique message name for use for attatchemnts, et al

=cut

sub generate_name
{
    my( $part ) = @_;

    my $name = "email".$part->top->uid_plain;
    $name .= "-part".$part->path;
    return $name;
}


#######################################################################

=head2 select_renderer

=cut

sub select_renderer
{
    my( $part, $type ) = @_;

    debug "Selecting renderer for $type";

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

    debug "  rendering textplain";

    my $charset = $part->charset_guess;
#    my $charset = $email->charset_plain($part);

    my $data_dec = $part->bodypart_decoded;
#    my $data_dec = $email->bodypart_decoded($part);
    my $data_enc = CGI->escapeHTML($data_dec);

    my $msg = "<p>Charset: $charset</p>\n";
    $data_enc =~ s/\n/<br>\n/g;
    $msg .= $data_enc;

    return $msg;
}


#######################################################################

sub _render_texthtml
{
    my( $part ) = @_;

    debug "  rendering texthtml";

    my $url_path = $part->url_path;

    my $msg = qq(<a href="$url_path">Download HTML message</a>\n );

    if( my $other = $part->top->{'other'} )
    {
	foreach my $alt (@$other)
	{
	    my $type = $alt->type;
	    my $url = $alt->url_path;
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
    my( $part ) = @_;

    debug "  rendering delivery_status";

    my $data_dec = $part->bodypart_decoded;
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
    my( $part ) = @_;

    debug "  rendering headers";

    my $data_dec = $part->bodypart_decoded;
    my $msg;

    my $header = Rit::Base::Email::Head->new(\$data_dec );
    unless( $header )
    {
	$msg = "<h3>Malformed header</h3>\n";
	$msg .= $part->_render_textplain;
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
    my( $part ) = @_;

    debug "  rendering alt";

    my $alts = $part->parts;

    my %prio =
      (
       'text/html' => 3,
       'text/plain' => 2,
      );

    my $choice = shift @$alts;
    my $score = $prio{ $choice->type } || 1; # prefere first part

    my @other;

    foreach my $alt (@$alts)
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

    $part->top->{'other'} = \@other;

    my $type = $choice->type;
    my $path = $part->path;

    my $renderer = $part->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }

    return $choice->$renderer;
}


#######################################################################

sub _render_mixed
{
    my( $part ) = @_;

    debug "  rendering mixed";

#    debug $email->part_desig;

    my $alts = $part->parts;

    my $msg = "";

    $part->top->{'attatchemnts'} ||= {};

    foreach my $alt (@$alts)
    {
	my $apath = $alt->path;

	my $type = $alt->type;
	my $renderer = $part->select_renderer($type);

	if( $alt->disp eq 'inline' )
	{
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
	elsif( $renderer ) # Display some things anyway...
	{
	    if( $type eq 'message/rfc822' )
	    {
		$msg .= $alt->$renderer;
	    }
	    else
	    {
		$part->top->{'attatchemnts'}{$alt->path} = $alt;
	    }
	}
	else # Not requested for inline display
	{
	    $part->top->{'attatchemnts'}{$alt->path} = $alt;
	}
    }

    return $msg;
}


#######################################################################

sub _render_related
{
    my( $part ) = @_;

    debug "  rendering related";

    my $path = $part->path;

    my $req = $Para::Frame::REQ;

    my $alts = $part->parts;

    my %prio =
      (
       'text/html' => 3,
       'text/plain' => 2,
      );

    my %files = ();

    foreach my $alt (@$alts)
    {
	my $apath = $alt->path;

	if( my $file = $alt->struct->filename )
	{
	    $files{$file} = $apath;
	}

	if( my $cid = $alt->struct->{'cid'} )
	{
	    $cid =~ s/^<//;
	    $cid =~ s/>$//;
	    $files{$cid} = $apath;
	    debug "Path $apath -> $cid";
	}
    }

    my $s = $req->session
      or die "Session not found";
    my $id = $part->email->id;
    $s->{'email_imap'}{$id} = \%files;

    my $choice = shift @$alts;
    my $score = $prio{ $choice->type } || 1; # prefere first part

    foreach my $alt (@$alts)
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
    my $renderer = $part->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for <strong>$type</strong></code>";
    }

    my $data = $choice->$renderer;

#"cid:part1.00090900.07060702@avisita.com"

    my $url_path = $part->top->url_path();
    $data =~ s/(=|")\s*cid:(.+?)("|\s|>)/$1$url_path$files{$2}$3/gi;
    return $data;
}


#######################################################################

sub _render_image
{
    my( $part ) = @_;

    debug "  rendering image";

    my $url_path = $part->url_path;

    my $desig = $part->filename || "image";
    if( my $desc = $part->struct->description )
    {
	$desig .= " - $desc";
    }

    my $desig_out = CGI->escapeHTML($desig);

    $part->top->{'attatchemnts'} ||= {};
    $part->top->{'attatchemnts'}{$part->path} = $part;

    return "<img alt=\"$desig_out\" src=\"$url_path\"><br clear=\"all\">\n";
}


#######################################################################

sub _render_rfc822
{
    my( $part ) = @_;

    debug "  rendering rfc822";

    my $struct = $part->struct;
    my $env = $struct->{'envelope'};

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

    my $filename = $part->filename;
    my $url_path = $part->url_path;
    $msg .= "<tr><td colspan=\"2\"><a href=\"$url_path\">Download as email</a></td></tr>\n";




    $msg .= "<tr><td colspan=\"2\" style=\"background:#FFFFE5\">";

    my $sub = $part->new( $struct->{'bodystructure'} );
    my $path = $sub->path;
    my $type = $sub->type;


    my $renderer = $sub->select_renderer($type);
    unless( $renderer )
    {
	debug "No renderer defined for $type";
	return "<code>No renderer defined for part $path <strong>$type</strong></code>";
    }

    $msg .= $sub->$renderer;

    $msg .= "</td></tr></table>\n";

    return $msg;
}


#######################################################################

sub bodypart_decoded
{
    my( $part, $length ) = @_;

    my $struct = $part->struct;

    my $encoding = lc $struct->encoding or die;

    my $folder = $part->top->folder;
    my $uid = $part->top->uid_plain;
    my $path = $struct->part_path;
    debug "Getting bodypart $uid $path";

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

=head2 desig

=cut

sub desig
{
    my( $part ) = @_;

    my $struct = $part->struct;

    my $type = $struct->type     || '-';
    my $enc = $struct->encoding  || '-';
    my $size = $struct->size     || '-';
    my $disp = $struct->disp     || '-';
    my $char = $struct->charset  || '-';
    my $file = $struct->filename || '-';
    my $lang = $struct->{lang}   || '-';
    my $loc = $struct->{loc}     || '-';
    my $cid = $struct->{cid}     || '-';
    my $desc = $struct->description || '-';

    my $path = $struct->part_path;

    my $msg = "$path $type $enc $size $disp $char $file $lang $loc $cid $desc\n";
#    debug $msg;
    foreach my $subpart ( @{$part->parts} )
    {
#	debug "  subpart $subpart";
	$msg .= $subpart->desig;
    }

    return $msg;
}


#######################################################################

1;
