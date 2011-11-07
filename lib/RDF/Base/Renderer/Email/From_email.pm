package RDF::Base::Renderer::Email::From_email;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Renderer::Email::From_email - Renders an email for sending

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Renderer::Email );

use Carp qw( croak confess cluck );
use Template::Exception;
use Email::MIME;
use Clone qw(clone);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::L10N qw( loc );
use Scalar::Util qw(weaken);

########
#
# Stores email template email in $rend->{'template_raw'}
#
#########


our %KEEP =
  ( 'mime-version' => 1,
    'content-type' => 1,
  );

##############################################################################

=head2 render_body_from_template

=cut

sub render_body_from_template
{
    my( $rend ) = @_;

    debug "RB render_body_from_template";

    # Important for not retrieving the template over IMAP multiple times
    #
    $rend->{'template_raw'} ||= $rend->{'template'}->raw_part;
    my $em = clone($rend->{'template_raw'}); ### COPY template
    my $burner = $rend->set_burner_by_type('plain');

    unless( $em->parts )
    {
	$rend->render_part($em);
    }

    $rend->render_parts($em);
    $rend->email_clone($em); # TODO: avoid copy

    return 1;
}


##############################################################################

=head2 render_parts

=cut

sub render_parts
{
    my( $rend, $pp, $level ) = @_; # parent part

    $level ||= 1;
#    debug "Render part, level $level";

    foreach my $part ( $pp->parts )
    {
	$rend->render_part($part);
	$rend->render_parts($part, $level+1);
    }
}


##############################################################################

=head2 render_part

=cut

sub render_part
{
    my( $rend, $part ) = @_; # parent part

    my $parser = $rend->burner->parser;

    debug sprintf "%s %s", $part->path, $part->effective_type;
    if( $part->type =~ /^text/ )
    {
	debug "   Burning ".$part->path;
	my $body = $part->body;

	my $out = "";
	my $outref = \$out;
	my $parsedoc = $parser->parse( $$body, {} ) or
	  throw('template', "parse error: ".$parser->error);
	my $doc = Template::Document->new($parsedoc) or
	  throw('template', $Template::Document::ERROR);
	$rend->burn($doc, $outref) or
	  throw('template', $Template::Document::ERROR);

#	    debug "---";
#	    debug $$outref;
#	    debug "Charset: ".$part->charset;
#	    debug "em ct: ".$part->{'em'}->content_type;
#	    use Email::MIME::ContentType;
#	    debug datadump(parse_content_type($part->{'em'}->content_type));
#	    debug datadump($part->{'em'}->header_obj);

	$part->body_set( $outref );

#	    debug ${$part->body};
#	    die "CHECKME";
    }
}


##############################################################################

=head2 render_header

The header depends on the body. The body depends on the header.

=cut

sub render_header
{
    my( $rend, $to_addr ) = @_;

    my $p = $rend->params;
    my $e = $rend->email;
#    my $em = $rend->{'template'}->raw_part;
    $rend->{'header_rendered_to'} = $to_addr;

    my $h = $e->{'em'}->header_obj;
    foreach my $hn ( $h->header_names )
    {
	$h->header_set($hn) unless $KEEP{lc $hn};
    }

#    debug datadump $h;
#    die "CHECK";

    $e->apply_headers_from_params( $p, $to_addr );
    return 1;
}


##############################################################################

=head2 set_burner_by_type

  $p->set_burner_by_type( $type )

Calls L<Para::Frame::Burner/get_by_type> and store it in the page
object.

Returns: the burner

=cut

sub set_burner_by_type
{
    return $_[0]->{'burner'} =
      Para::Frame::Burner->get_by_type($_[1])
	  or die "Burner type $_[1] not found";
}


##############################################################################

=head2 burner

  $p->burner

Returns: the L<Para::Frame::Burner> selected for this page

=cut

sub burner
{
    unless( $_[0]->{'burner'} )
    {
	die "burner not set";
    }

    return $_[0]->{'burner'};
}


##############################################################################

=head2 burn

  $p->burn( $in, $out );

Calls L<Para::Frame::Burner/burn> with C<($in, $params, $out)> there
C<$params> are set by L</set_tt_params>.

Returns: the burner

=cut

sub burn
{
    my( $rend, $in, $out ) = @_;
    return $rend->{'burner'}->burn($rend, $in, $rend->{'params'}, $out );
}

##############################################################################

=head2 template

May not be defined

=cut

sub template
{

#    debug "Returning template ".$_[0]->{'template'}->sysdesig;
    return $_[0]->{'template'};
}


##############################################################################

=head2 set_template

=cut

sub set_template
{
    debug 2, "Template set to ".$_[1]->sysdesig;
    return $_[0]->{'template'} = $_[1];
}


##############################################################################


=head2 paths

  $p->paths( $burner )

Automaticly called by L<Template::Provider>
to get the include paths for building pages from templates.

Returns: L</incpath>

=cut

sub paths
{
    return [];
}


##############################################################################

=head2 sysdesig

=cut

sub sysdesig
{
    my( $rend ) = @_;

    return datadump($rend,2);
}

##############################################################################


1;

=head1 SEE ALSO

L<Para::Frame>

=cut
