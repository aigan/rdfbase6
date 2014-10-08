package RDF::Base::Email::Raw::Part;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::Raw::Part

=head1 DESCRIPTION

=cut

use 5.014;
no if $] >= 5.018, warnings => "experimental";
use utf8;
use base qw( RDF::Base::Email::Part Para::Frame::Email );

use Carp qw( croak confess cluck );
use Scalar::Util qw( weaken reftype );
use Email::MIME;
#use MIME::Words qw( decode_mimewords );
use MIME::WordDecoder qw( mime_to_perl_string );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use RDF::Base::Email::Raw::Head;


##############################################################################

=head2 new

=cut

sub new
{
    my( $part, $dataref ) = @_;
#    my $class = ref($part) or die "Must be called by parent";


    my $sub = bless
    {
     redraw => 0,
    }, 'RDF::Base::Email::Raw::Part';

    if( ref $part )
    {
	$sub->{'email'}   = $part->email;
	$sub->{'top'}     = $part->top;
	$sub->{'parent'}  = $part;
	$sub->{'part_id'} = $part->path .'.TEXT';
	weaken( $sub->{'email'} );
	weaken( $sub->{'parent'} );
    }
    else
    {
	$sub->{'part_id'} = '';
	$sub->{'top'}     = $sub;
	weaken( $sub->{'top'} );
    }

#    debug "New raw part based on dataref:\n".$$dataref;


    $sub->{'em'} = Email::MIME->new($dataref);

    return $sub;
}


##############################################################################

=head2 new_by_em_obj

=cut

sub new_by_em_obj
{
    my( $part, $emo, $pos ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     parent => $part,
     redraw => 0,
    }, 'RDF::Base::Email::Raw::Part';

    $sub->{'em'} = $emo;

    my $path = $part->path;
    $path =~ s/\.TEXT$//;
    $sub->{'part_id'} = $path .'.'. $pos;

    weaken( $sub->{'email'} );
    weaken( $sub->{'parent'} );
#    weaken( $sub->{'top'} );

#    debug "new raw part from emo ".$sub->{'part_id'};

    return $sub;
}


##############################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    my( $part, $path ) = @_;

#    debug "Getting raw part $path";

    if( $path =~ s/^([0-9]+)\.// )
    {
	my $i = $1 - 1;
	my @parts = $part->parts;
	return $parts[$i]->new_by_path( $path );
    }
    elsif( $path =~ /^([0-9]+)$/ )
    {
	my $i = $1 - 1;
	my @parts = $part->parts;
	return $parts[$i];
    }

    confess "Can't get part $path";
}


##############################################################################

=head2 envelope

For compatibility with Email::IMAP. Returns self.

=cut

sub envelope
{
    return $_[0];
}


##############################################################################

=head2 path

=cut

sub path
{
    return $_[0]->{'part_id'};
}


##############################################################################

=head2 generate_name

See L<RDF::Base::Email::Part/generate_name>

=cut

sub generate_name
{
    my( $part ) = @_;

    return "raw-part".$part->path;
}


##############################################################################

=head2 charset

See L<RDF::Base::Email::Part/charset>


=cut

sub charset
{
    return lc($_[0]->type('charset')||'');
}


##############################################################################

=head2 type

See L<RDF::Base::Email::Part/type>

=cut

sub type
{
    my $ct = $_[0]->{'em'}->content_type;
    return undef unless $ct;

    $ct =~ s/;\s+(.*?)\s*$//;

    if( $_[1] )
    {
	my %param;
	my $params = $1;
	foreach my $param (split /\s*;\s*/, $params )
	{
	    if( $param =~ /^(.*?)\s*=\s*(.*)/ )
	    {
		my $key = lc $1;
		my $val = $2;
		$val =~ s/^"(.*)"$/$1/; # non-standard variant
		$param{ $key } = $val;
	    }
	}

	return $param{$_[1]};
    }

    return $ct;
}


##############################################################################

=head2 disp

See L<RDF::Base::Email::Part/disp>

=cut

sub disp
{
    # scalar context
    my $disp = $_[0]->head->
      header('content-disposition');
    return undef unless $disp;

    $disp =~ s/;\s+(.*?)\s*$//;

    if( $_[1] )
    {
	my %param;
	my $params = $1;
	foreach my $param (split /\s*;\s*/, $params )
	{
	    if( $param =~ /^(.*?)\s*=\s*(.*)/ )
	    {
		my $key = lc $1;
		my $val = $2;
		$val =~ s/^"(.*)"$/$1/; # non-standard variant
		$param{ $key } = $val;
	    }
	}

	return $param{$_[1]};
    }

    return $disp;
}


##############################################################################

=head2 encoding

See L<RDF::Base::Email::Part/encoding>

=cut

sub encoding
{
    # scalar context
    my $enc = $_[0]->head->
      header('content-transfer-encoding');

    return $enc;
}


##############################################################################

=head2 description

See L<RDF::Base::Email::Part/description>

=cut

sub description
{
    return scalar mime_to_perl_string( scalar $_[0]->head->
                                       header('content-description')||'' );
}


##############################################################################

=head2 body_raw

=cut

sub body_raw
{
    my( $part, $length ) = @_;
    $part->redraw;

    return \ $part->{'em'}->body_raw;
}


##############################################################################

=head2 redraw

=cut

sub redraw
{
    my( $part ) = @_;

    my $em = $part->{'em'};

    if( $part->{'redraw'} )
    {
	debug "BODY-RAW redraw";
	$part->{'redraw'} = 0;

#	debug $part->desig;
#	debug $part->viewtree;
#	debug datadump($em->{'body_raw'},1);
#	warn $part->explain($em);
#	die "CHECKME";

	$part->redraw_subpart( $em );

#	debug datadump $part;
#	debug $part->viewtree;
#	debug datadump($em->{'body_raw'},1);
#	warn $part->explain($em);
#	die "CHECKME";
    }

    return 1;
}

sub explain
{
    my( $part, $n, $l ) = @_;

    $l ||= 0;

    my $out = ""; #"  "x$l . ref($n)."\n";
    $l++;

    given( reftype $n )
    {
	when('SCALAR')
	{
	    my $str = $$n;
	    my $len = length($str);
	    $str =~ s/\r?\n/\\n/g;
	    if( $len > 20 )
	    {
		$str =~ s/.*\[%/[%/ or
		  $str =~ s/.*mailto:webb/mailto:webb/;
		$out .= "  "x$l.$len.") ".substr($str,0,20)."...\n";
	    }
	    else
	    {
		$out .= "  "x$l.$len.") ".$str."\n";
	    }
	}
	when('HASH')
	{
	    foreach my $key ( keys %$n )
	    {
		next if $key eq 'header';
		next if $key eq 'ct';
		next if $key eq 'mycrlf';
		my $val = $n->{$key};
		my $type = ref($val) || 'str';
		$out .= "  "x$l.$key." = ".$type."\n";
		$out .= $part->explain($val,$l);
	    }
	}
	when('ARRAY')
	{
	    my $cnt = 0;
	    foreach my $val ( @$n )
	    {
		$out .= "  "x$l.sprintf "#%3d\n",$cnt;
		$out .= $part->explain($val,$l, $cnt);
		$cnt++;
		last if $cnt > 1;
	    }
	}
	when(undef)
	{
	    my $str = $n;
	    my $len = length($str);
	    $str =~ s/\r?\n/\\n/g;
	    if( $len > 20 )
	    {
		$str =~ s/.*\[%/[%/ or
		  $str =~ s/.*mailto:webb/mailto:webb/;
		$out .= "  "x$l.$len.") ".substr($str,0,20)."...\n";
	    }
	    else
	    {
		$out .= "  "x$l.$len.") ".$str."\n";
	    }
	}
	default
	{
	    $out .= "  "x$l.ref($n)."\n";
	}
    }

    return $out;
}


##############################################################################

=head2 redraw_subpart

=cut

sub redraw_subpart
{
    my( $part, $emp ) = @_;

    foreach my $ems ( $emp->subparts )
    {
	$part->redraw_subpart( $ems );
    }

    $emp->parts_set([$emp->subparts]) if $emp->subparts;
}


##############################################################################

=head2 size

See L<RDF::Base::Email::Part/size>

=cut

sub size
{
    my $em = $_[0]->{'em'};
    $_[0]->redraw;
    return bytes::length( $em->{'body_raw'} || ${$em->{'body'}} );
}


##############################################################################

=head2 head_complete

See L<RDF::Base::Email::Part/head_complete>

=cut

sub head_complete
{
#    confess "FIXME";
    return $_[0]->{'head_complete'} ||=
      RDF::Base::Email::Raw::Head->
	  new_by_part( $_[0] );
}


##############################################################################

=head2 parts

See L<RDF::Base::Email::Part/parts>

=cut

sub parts
{
    my( $part ) = @_;
    my $class = ref($part);

    my @parts;
    my $cnt = 0;
    foreach my $emo ( $part->{'em'}->subparts )
    {
	$cnt++;
	push @parts, $part->new_by_em_obj($emo, $cnt);
    }

    return @parts;
}


##############################################################################

=head2 body_part

See L<RDF::Base::Email::IMAP/body_part>

=cut

sub body_part
{
    return undef; # FIXME
    confess "NOT IMPLEMENTED";
}


##############################################################################

=head2 body_set

  $part->body_set( \$body )

Calls L<Email::MIME/body_str_set>

=cut

sub body_set
{
    my( $part, $body ) = @_;

    my $charset = $part->charset;
    my $body_octets = Encode::encode($charset, $$body, 1);
    $part->{'em'}->body_set($body_octets);

    if( my $parent = $part->{'parent'} )
    {
	$parent->{'redraw'} = 1;
    }

    return 1;
}


##############################################################################

1;
