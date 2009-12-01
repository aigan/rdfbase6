package Rit::Base::Renderer::Email::From_email;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

=head1 NAME

Rit::Base::Renderer::Email::From_email - Renders an email for sending

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Renderer::Email );

use Carp qw( croak confess cluck );
use Template::Exception;
use Email::MIME;

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch );
use Para::Frame::L10N qw( loc );
use Scalar::Util qw(weaken);


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

    my $em = $rend->{'template'}->raw_part;

    my $burner = $rend->set_burner_by_type('plain');
    my $parser = $burner->parser;
    $rend->set_tt_params;

   foreach my $part ( $em->parts )
    {
	debug " * ".$part->effective_type;
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
	    $rend->burn($doc, $outref) or return 0;

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

    $rend->email_clone($em);

    return 1;
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

=head2 set_tt_params

The standard functions availible in templates. This is called before
the page is rendered. You should not call it by yourself.

=over

=item browser

The L<HTTP::BrowserDetect> object.  Not in StandAlone mode.

=item ENV

$req->env: The Environment hash (L<http://hoohoo.ncsa.uiuc.edu/cgi/env.html>).  Only in client mode.

=item home

$req->site->home : L<Para::Frame::Site/home>

=item lang

The L<Para::Frame::Request/preffered_language> value.

=item me

Holds the L<Para::Frame::File/url_path_slash> for the page, except if
an L<Para::Frame::Request/error_page_selected> in which case we set it
to L<Para::Frame::Request/original_response> C<page>
C<url_path_slash>.  (For making it easier to link back to the intended
page)

=item page

Holds the L<Para::Frame::Request/page>

=item q

The L<CGI> object.  You will probably mostly use
[% q.param() %] method. Only in client mode.

=item req

The C<req> object.

=item site

The <Para;;Frame::Site> object.

=item u

$req->{'user'} : The L<Para::Frame::User> object.

=back

=cut

sub set_tt_params
{
    my( $rend ) = @_;

    my $req = $Para::Frame::REQ;

    # Keep alredy defined params  # Static within a request
    $rend->add_params({
	'u'               => $Para::Frame::U,
	'lang'            => $req->language->preferred, # calculate once
	'req'             => $req,
    });
}


##############################################################################

=head2 add_params

  $resp->add_params( \%params )

  $resp->add_params( \%params, $keep_old_flag )

Adds template params. This can be variabls, objects, functions.

If C<$keep_old_flag> is true, we will not replace existing params with
the same name.

=cut

sub add_params
{
    my( $resp, $extra, $keep_old ) = @_;

    my $param = $resp->{'params'} ||= {};

    if( $keep_old )
    {
	while( my($key, $val) = each %$extra )
	{
	    next if $param->{$key};
	    unless( defined $val )
	    {
		debug "The TT param $key has no defined value";
		next;
	    }
	    $param->{$key} = $val;
	    debug(4,"Add TT param $key: $val") if $val;
	}
    }
    else
    {
	while( my($key, $val) = each %$extra )
	{
	    unless( defined $val )
	    {
		debug "The TT param $key has no defined value";
		next;
	    }
	    $param->{$key} = $val;
	    debug(3, "Add TT param $key: $val");
	}
     }
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
