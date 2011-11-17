package RDF::Base::L10N;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::L10N - framework for localization

=head1 DESCRIPTION

Using Locale::Maketext

=cut

use 5.010;
use strict;
use warnings;
use utf8;

use Carp qw(cluck croak carp confess );

use base qw(Para::Frame::L10N);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );

use RDF::Base::Constants qw( $C_language );
use RDF::Base::Utils qw( is_undef );

our %TRANSLATION;


##############################################################################

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


##############################################################################

=head2 maketext

  $lh->maketext( $phrase, @args )

Usually called from Para::Frame::L10N::loc( $phrase, @args )

C<$phrase> may be a translatable node


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

    my $DEBUG = Para::Frame::Logging->at_level(2);

    if( $phrase =~ /Ã/ )
    {
	#cluck "Encoded but not marked as encoded ($phrase)";
	debug "Encoded but not marked as encoded ($phrase)";
    }

    my $node;
    if( ref $phrase )
    {
	if( ref $phrase eq 'RDF::Base::List' )
	{
	    return $phrase->loc;
	}
	elsif( UNIVERSAL::isa $phrase, 'RDF::Base::Literal' )
	{
	    $phrase = $phrase->literal;
	}
	elsif( UNIVERSAL::isa $phrase, 'RDF::Base::Object' )
	{
	    if( $phrase->is_value_node )
	    {
#                debug "Returning value node ".ref($phrase->plain);

		return $phrase->plain;
	    }

	    if( my $label = $phrase->first_prop('translation_label')->plain )
	    {
		$node = $phrase;
		$phrase = $label;
	    }
	    else
	    {
		confess "Can't translate: ".$phrase->sysdesig;
	    }
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
	$value = $TRANSLATION{$phrase}{$langcode};

	unless( exists $TRANSLATION{$phrase}{$langcode} )
	{
	    debug "Looking up phrase '$phrase' in DB" if $DEBUG;
	    $node ||= RDF::Base::Resource->
	      find({ translation_label => $phrase })->get_first_nos;
	    if( $node )
	    {
                debug "Found a node: " . $node->sysdesig if $DEBUG;
		my $lang = $C_language->first_revprop('is',{code => $langcode});

#		RDF::Base::Resource->get({
#						     code => $langcode,
#						     is => $C_language,
#						     });
                debug "Found a lang: " . $lang->sysdesig if $DEBUG;
		if( my $trans = $node->first_prop('has_translation',
						  {is_of_language=>$lang}
						 )->plain )
		{
                    debug "Found a trans: $trans" if $DEBUG;
		    $value = $TRANSLATION{$phrase}{$langcode} =
		      $lh->_compile($trans);
		    last;
		}
	    }
	    $TRANSLATION{$phrase}{$langcode} = undef;
	    next;
	}
	last;
    }

    return $lh->compute($value, \$phrase, @_);
}


##############################################################################

sub find_translation_node_id
{
    my( $phrase ) = @_;
#    debug "find_translation_node_id $phrase";

    unless( exists $TRANSLATION{$phrase}{'node_id'} )
    {
#	debug "  looking for translation_label in DB";
        if( my $node = RDF::Base::Resource->
	    find({ translation_label => $phrase })->get_first_nos )
	{
#	    debug "    found ".$node->sysdesig;
            $TRANSLATION{$phrase}{'node_id'} = $node->id;
        }
	else
	{
#	    debug "    non found";
	    $TRANSLATION{$phrase}{'node_id'} = 0;
	}
    }

    return $TRANSLATION{$phrase}{'node_id'};
}


##############################################################################

sub find_translation_node
{
    my( $phrase ) = @_;
#    debug "find_translation_node $phrase";

    unless( exists $TRANSLATION{$phrase}{'node_id'} )
    {
	find_translation_node_id( $phrase );
    }

    if( my $id = $TRANSLATION{$phrase}{'node_id'} )
    {
	return RDF::Base::Resource->get($id);
    }

    return is_undef;
}



##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base>

=cut
