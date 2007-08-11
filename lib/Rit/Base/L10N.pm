#  $Id$  -*-cperl-*-
package Rit::Base::L10N;
#=====================================================================
#
# DESCRIPTION
#   Ritbase L10N class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::L10N - framework for localization

=head1 DESCRIPTION

Using Locale::Maketext

=cut

use strict;
use utf8;

use Carp qw(cluck croak carp confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%01d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );

use Rit::Base::Constants qw( $C_language );


use base qw(Para::Frame::L10N);

our %TRANSLATION;


#######################################################################

=head2 alocpp

  alocpp($name, @args)

Same as L<Para::Frame::L10N::loc>, but looks up the translation from
the database. If in admin mode, prepends a text edit link

=cut

sub alocpp
{
    my( $name ) = shift;

    my $req = $Para::Frame::REQ;

    my $out = "";

    debug "Checking session admin mode";

    if( $req->session->{'admin_mode'} )
    {
	my $home = $req->site->home_url_path;
	$out .= Para::Frame::Widget->jump("E", "$home/pf/cms/admin_loc.tt");
    }

    return $out . $req->{'lang'}->maketext($name, @_);
}


#######################################################################

=head2 get_handle

Replaces Locale::Metatext get_handle

=cut

sub get_handle
{
    my $class = shift;

    my $lh = $class->new();
    $lh->{'fallback'} = Para::Frame::L10N->get_handle(@_);
    $lh->fail_with( 'fallback_maketext' );
    return $lh;
}


#######################################################################

=head2 maketext

=cut

sub maketext
{
    my $lh = shift;
    my $phrase = shift || "";

    my $req = $Para::Frame::REQ;

    return "" unless length($phrase);
#    my $len1 = length($phrase);
#    my $len2 = bytes::length($phrase);
#    debug "  >>$phrase ($len2/$len1)";
#    debug "-------->> Translating $phrase @_";

    if( $phrase =~ /Ã/ )
    {
	confess "Encoded but not marked as encoded ($phrase)";
    }

    # The object to be translated could be one or more value nodes.
    # choose the right value node

    if( ref $phrase )
    {
	if( ref $phrase eq 'Rit::Base::List' )
	{
	    return $phrase->loc;
	}
	elsif( UNIVERSAL::isa $phrase, 'Rit::Base::Literal' )
	{
	    $phrase = $phrase->literal;
	}
	elsif( UNIVERSAL::isa $phrase, 'Rit::Base::Node' )
	{
	    if( my $val = $phrase->value )
	    {
		return $val;
	    }

	    my $val = $phrase->id;

	    debug "----------> During maketext: node $val is not a value resource";
	    return $val;
	}
	else
	{
	    confess "Can't translate value: ". datadump($phrase, 2);
	}
    }

    utf8::upgrade($phrase);


    my @alts = $req->language->alternatives;
    my( $rec, $value );
    foreach my $langcode ( @alts )
    {
#	debug "  ... in $langcode\n";
	unless( $value = $TRANSLATION{$phrase}{$langcode} )
	{
	    if( my $node = Rit::Base::Resource->find({ has_translation => $phrase })->get_first_nos )
	    {
		my $lang = Rit::Base::Resource->get({
						     code => $langcode,
						     is => $C_language,
						     });
		if( my $trans = $node->has_translation({is_of_language=>$lang})->plain )
		{
		    $value = $TRANSLATION{$phrase}{$langcode} = $lh->_compile($trans);
		    last;
		}
	    }
	    next;
	}
	last;
    }

    return $lh->compute($value, \$phrase, @_);
}


#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>

=cut
