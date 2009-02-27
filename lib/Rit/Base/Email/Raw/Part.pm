#  $Id$  -*-cperl-*-
package Rit::Base::Email::Raw::Part;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email::Raw::Part

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
use Email::MIME;
use MIME::Words qw( decode_mimewords );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;

use Rit::Base::Email::Raw::Head;

use base qw( Rit::Base::Email::Part );


#######################################################################

=head2 new

=cut

sub new
{
    my( $part, $dataref ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
#     data   => $dataref,
    }, 'Rit::Base::Email::Raw::Part';

    $sub->{'em'} = Email::MIME->new($dataref);

    $sub->{'part_id'} = $part->path .'.TEXT';

    weaken( $sub->{'email'} );
#    weaken( $sub->{'top'} );

    return $sub;
}


#######################################################################

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
    }, 'Rit::Base::Email::Raw::Part';

    $sub->{'em'} = $emo;

    my $path = $part->path;
    $path =~ s/\.TEXT$//;
    $sub->{'part_id'} = $path .'.'. $pos;

    weaken( $sub->{'email'} );
#    weaken( $sub->{'top'} );

    return $sub;
}


#######################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    confess "NOT IMPLEMENTED";
}


#######################################################################

=head2 envelope

For compatibility with Email::IMAP. Returns self.

=cut

sub envelope
{
    return $_[0];
}


#######################################################################

=head2 path

=cut

sub path
{
    return $_[0]->{'part_id'};
}


#######################################################################

=head2 type

See L<Rit::Base::Email::Part/type>

=cut

sub type
{
    my $ct = $_[0]->{'em'}->content_type;

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
		$param{ $key } = $val;
	    }
	}

	return $param{$_[1]};
    }

    return $ct;
}


#######################################################################

=head2 disp

See L<Rit::Base::Email::Part/disp>

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
		$param{ $key } = $val;
	    }
	}

	return $param{$_[1]};
    }

    return $disp;
}


#######################################################################

=head2 encoding

See L<Rit::Base::Email::Part/encoding>

=cut

sub encoding
{
    # scalar context
    my $enc = $_[0]->head->
      header('content-transfer-encoding');

    debug "Got raw part encoding '$enc'";

    return $enc;
}


#######################################################################

=head2 description

See L<Rit::Base::Email::Part/description>

=cut

sub description
{
    return scalar decode_mimewords( scalar $_[0]->head->
				    header('content-description')||'' );
}


#######################################################################

=head2 body_raw

=cut

sub body_raw
{
    my( $part, $length ) = @_;

    return \ $part->{'em'}->body_raw;
}


#######################################################################

=head2 size

See L<Rit::Base::Email::Part/size>

=cut

sub size
{
    my $em = $_[0]->{'em'};
    return bytes::length( $em->{'body_raw'} || ${$em->{'body'}} );
}


#######################################################################

=head2 complete_head

See L<Rit::Base::Email::Part/complete_head>

=cut

sub complete_head
{
    return $_[0]->{'complete_head'} ||=
      Rit::Base::Email::Raw::Head->
	  new_by_part( $_[0] );
}


#######################################################################

=head2 parts

See L<Rit::Base::Email::Part/parts>

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


#######################################################################

1;
