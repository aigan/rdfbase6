package RDF::Base::Email::IMAP::Part;
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

RDF::Base::Email::IMAP::Part

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;
use base qw( RDF::Base::Email::Part );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
#use MIME::Words qw( decode_mimewords );
use MIME::WordDecoder qw( mime_to_perl_string );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::List;


##############################################################################

=head2 new

=cut

sub new
{
    my( $part, $struct ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     parent => $part,
     struct => $struct,
    }, 'RDF::Base::Email::IMAP::Part';

    weaken( $sub->{'email'} );
    weaken( $sub->{'parent'} );
#    weaken( $sub->{'top'} );

#    debug datadump($struct);

    return $sub;
}


##############################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    my( $part, $path ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    unless( $path )
    {
	return $part;
    }

#    debug "Part ".$part->path." looking up ".$path;
#    cluck "HERE";

    my $base = $part->top;
    my $struct = $base->struct->part_at($path);

    unless( $struct )
    {
	my $spath = $path;
	while( $spath =~ s/\.[^\.]+$// ) # look back
	{
	    if( $struct = $base->struct->part_at($spath) )
	    {
		debug "Found part $spath instead";
		my $ssub = $part->new( $struct );
#		debug "That is    ".$ssub->path;
		next if $spath ne $ssub->path;

#		debug $ssub->desig;
		$ssub->{'parent'} = undef;
		my $ssr = RDF::Base::Email::Raw::Part::new($ssub, $ssub->body);
		my $rest = $path;
		$rest =~ s/^$spath\.//;
		debug "Looking up $rest";
		my $sub = $ssr->new_by_path( $rest );
                unless( $sub )
                {
                    debug "Part $path not found";
                    return $sub;
                }
		debug "Got ".$sub->desig;
#		debug "-----------------------------------";
#		debug datadump $sub;
#		debug "-----------------------------------";

		return $sub;
	    }
	}
    }





    unless( $struct )
    {
	debug "Failed to get struct at $path";
	debug "Top: ".$part->top;
#	debug "Top struct: ". $part->top->struct;
	debug $part->top->desig;
	confess datadump($part,1);
    }

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
#     parent => $part,
     struct => $struct,
    }, 'RDF::Base::Email::IMAP::Part';
    weaken( $sub->{'email'} );
#    weaken( $sub->{'parent'} );
#    weaken( $sub->{'top'} );

#    debug datadump($struct);

    return $sub;
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

See L<RDF::Base::Email::Part/path>

=cut

sub path
{
    confess "No struct" unless $_[0]->struct;
    return $_[0]->struct->part_path;
}


##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $part ) = @_;

    return $part->SUPER::sysdesig() unless $part->folder;
    return sprintf "(%d) %s (%s)", $part->uid,
      ($part->body_head->parsed_subject->plain || '<no subject>'),
        $part->path;
}

##############################################################################

=head2 charset

See L<RDF::Base::Email::Part/charset>


=cut

sub charset
{
    # BodyStructure.pm buggy. Reimplement here

    my $s = $_[0]->struct;

    my $c = ($s->{params} && $s->{params}{charset})
      || ($s->{parts} && @{$s->{parts}} && $s->{parts}[0] && $s->{parts}[0]->charset)
        || undef;   # please oh please, no '' or '0' charsets

    # IMAP uses us-ascii as the default charset. Take that as "don't
    # know" and let other parts decide.
    $c = ''  if lc($c) eq 'us-ascii';

#    debug "IMAP::Part charset returns $c";

    return lc( $c||'');
}


##############################################################################

=head2 cid

See L<RDF::Base::Email::Part/cid>

=cut

sub cid
{
    return $_[0]->struct->{'cid'};
}


##############################################################################

=head2 type

See L<RDF::Base::Email::Part/type>

=cut

sub type
{
    my $struct = $_[0]->struct;
    confess "No struct" unless $struct;

    if( $_[1] )
    {
	return $struct->{'params'}{$_[1]};
    }

    my $type = lc $struct->type;

    if( $type =~ / / )
    {
        debug "Got a strange type: $type";
        debug datadump($struct);
    }


    return lc $struct->type;
}


##############################################################################

=head2 disp

See L<RDF::Base::Email::Part/disp>

=cut

sub disp
{
    my $struct = $_[0]->struct;

    if( $_[1] and ref $struct->{'disp'} )
    {
         return undef unless $struct->{'disp'}[1];
	return $struct->{'disp'}[1]{$_[1]};
    }

    return lc $struct->disp;
}


##############################################################################

=head2 encoding

See L<RDF::Base::Email::Part/encoding>

=cut

sub encoding
{
    confess "No struct" unless $_[0]->struct;

    my $enc = lc( $_[0]->struct->encoding||'');

    # Found a case where the encoding returned was actually the
    # boundary. Use complete head if encoding found not common

    unless( $enc =~ /^(quoted-printable|8bit|binary|7bit|base64)$/ )
    {
        my $h = $_[0]->head_complete;
#        debug "getting encoding from header";
        $enc = lc($h->header('content-transfer-encoding')||'');
#        debug "  got $enc";
    }

    return $enc;
}


##############################################################################

=head2 description

See L<RDF::Base::Email::Part/description>

=cut

sub description
{
    return scalar mime_to_perl_string($_[0]->struct->description||'');
}


##############################################################################

=head2 body_raw

Returns a scalar ref

=cut

sub body_raw
{
    my( $part, $length ) = @_;

    my $uid = $part->top->uid;
    my $path = $part->path;
    my $folder = $part->top->folder;

#    debug "Getting bodypart $uid $path ".($length||'all');
    return \ $folder->imap_cmd('bodypart_string', $uid, $path, $length);
}


##############################################################################

=head2 size

See L<RDF::Base::Email::Part/size>

=cut

sub size
{
    my( $size ) = $_[0]->struct->size;
    # Keep first number
    if( $size and $size =~ m/^(\d+)/ )
    {
        return $1;
    }

#    debug "Size of part not found";
    return undef;
}


##############################################################################

=head2 body_head_complete

See L<RDF::Base::Email::Part/body_head_complete>

=cut

sub body_head_complete
{
    return $_[0]->{'body_head'} ||=
      RDF::Base::Email::IMAP::Head->
	  new_body_head_by_part( $_[0] );
}


##############################################################################

=head2 head_complete

See L<RDF::Base::Email::Part/head_complete>

=cut

sub head_complete
{
    return $_[0]->{'head'} ||=
      RDF::Base::Email::IMAP::Head->
	  new_by_part( $_[0] );
}


##############################################################################

=head2 body_head

See L<RDF::Base::Email::Part/body_head>

=cut

sub body_head
{
    unless( $_[0]->{'body_head_partial'} )
    {
	if( my $env = $_[0]->struct->{'envelope'} )
	{
	    $_[0]->{'body_head_partial'} =
	      RDF::Base::Email::IMAP::Head->
		  new_body_head_by_part_env( $env );
	}
    }

    unless( $_[0]->{'body_head_partial'} )
    {
#	    debug "***********";

#	    debug "/---------------------------";
#	    debug $_[0]->path;
#	    debug datadump $_[0]->struct;
#	    debug substr ${$_[0]->body}, 0, 2000; ### DEBUG

        my $part = RDF::Base::Email::Raw::Part::new($_[0], $_[0]->body(5000));
        $_[0]->{'body_head_partial'} = $_[0]->{'body_head'} = $part->head;
    }

    return $_[0]->{'body_head_partial'};
}


##############################################################################

=head2 struct

=cut

sub struct
{
    return $_[0]->{'struct'} || die "Struct not given";
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
#    debug "Getting parts via struct";
    foreach my $struct ( $part->struct->parts )
    {
#        debug "  adding $struct";
	push @parts, $part->new($struct);
    }

    return @parts;
}


##############################################################################

=head2 body_part

This treats the body as a part in the structure hiearchy with it's own
subparts. This is the case if tha part is a message/rfc822.


=cut

sub body_part
{
    if( my $bstruct = $_[0]->struct->{'bodystructure'} )
    {
#        debug "Getting body_part from IMAP bodystructure";
#        debug "  bstruct: ".datadump($bstruct);

	return $_[0]->new( $bstruct );
    }

    return RDF::Base::Email::Raw::Part::new($_[0], $_[0]->body_raw);
}


##############################################################################

=head2 generate_name

See L<RDF::Base::Email::Part/generate_name>

=cut

sub generate_name
{
    my( $part ) = @_;

    my $name = "email".$part->top->uid;
    $name .= "-part".$part->path;
    return $name;
}


##############################################################################

=head2 convert_to

=cut

sub convert_to
{
    my( $part1, $part2 ) = @_;
    my $class = ref($part2);

    foreach my $key ( keys %$part1 )
    {
	delete $part1->{$key};
    }

    foreach my $key ( keys %$part2 )
    {
	$part1->{$key} = $part2->{$key};
    }

    return bless $part1, $class;
}


##############################################################################

1;
