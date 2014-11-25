package RDF::Base::Domain;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Domain

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Resource );
use constant R => 'RDF::Base::Resource';

use Carp qw( cluck confess carp croak );

use Para::Frame::Utils qw( throw catch debug datadump );
use Para::Frame::Reload;

use RDF::Base::Utils qw( is_undef solid_propargs );

our %DOMAIN_CACHE = ();

our @CLASS_METHODS = qw( test );


##############################################################################

sub test
{
    my $cn = shift;

#    my $list = RDF::Base::Pred->get('has_email_address_holder')->active_arcs;
    my $list = R->find({is => 1107})->arc_list('has_email_address_holder')->flatten->sorted('obj.address');


#    return $list->size;

    my( $a, $error ) = $list->get_first;
    while(! $error )
    {
        my $url = $a->value;
#        next unless $url->path eq '/';
#        my $host = $url->host;
#        next if $host =~ /^\d/; # Probably ip
#        $host =~ s/^www\.//;

        my $n = $a->subj;

        my $web = $n->url_main;
        next if $web;


        debug $n->id ." : ".$url->address;# ." : ". $web;
    }
    continue
    {
        $Para::Frame::REQ->may_yield unless $list->count % 100;
        last if $list->count > 1000;
        ( $a, $error ) = $list->get_next;
    }

    return $list->size;
}

##############################################################################

sub domains_from_url_main
{
    my $cn = shift;

    my $list = RDF::Base::Pred->get('url_main')->active_arcs;

    my( $a, $error ) = $list->get_first;
    while(! $error )
    {
        my $url = $a->value;
        next unless $url->path eq '/';
        my $host = $url->host;
        next if $host =~ /^\d/; # Probably ip
        $host =~ s/^www\.//;

#        debug $host;
    }
    continue
    {
        $Para::Frame::REQ->may_yield unless $list->count % 100;
        last if $list->count > 100;
        ( $a, $error ) = $list->get_next;
    }

    return $list->size;
}

##############################################################################

=head2 find_by_string

used by RDF::Base::Widget::Handler

=cut

sub find_by_string
{
    my( $node, $value, $props_in, $args) = @_;

    return RDF::Base::Domain->parse( $value, $args );
}

##############################################################################

=head2 parse_to_list

=cut

sub parse_to_list
{
    if( my $domain = shift->parse(@_) )
    {
        return RDF::Base::List->new([$domain]);
    }

    return RDF::Base::List->new_empty();
}

##############################################################################

=head2 parse

=cut

sub parse
{
    my( $this, $value_in, $args ) = @_;

    my $u = RDF::Base::Literal::URL->parse($value_in, {with_host=>1});

    my $host = lc $u->host || '';

    if( $host =~ /^\d/ ) # Probably ip
    {
        $host = '';
    }

    $host =~ s/^www\.//;

    unless( $host )
    {
        cluck "empty domain host";
        return is_undef;
    }

#    debug "Parsed to host $host";


    # The search will not find domains not yet comitted. Since they are
    # supposed to be unique, we can cache the keys here, in order to
    # avoid duplicates.
    #
    # But that cache must be purged in case of rollbacks. That is done
    # in /rollback
    #
    my $domain = $DOMAIN_CACHE{$host};

    $domain ||= R->set_one({
                            code => $host,
                            is   => R->get('internet_domain'),
                           }, solid_propargs );


#    cluck "Found domain ".$domain->sysdesig;

    return $DOMAIN_CACHE{$host} = $domain;

}


##############################################################################

=head2 new

Called by L<RDF::Base::Literal::String/wuirc>

=cut

sub new
{
    return shift->parse(@_);
}


##############################################################################

=head2 wuirc

=cut

sub wuirc
{
#    debug "Domain wuirc with @_";

    return RDF::Base::Literal::String::wuirc(@_);
}

##############################################################################

=head2 plain

=cut

sub plain
{
    return shift->first_prop('code')->plain;
}

##############################################################################

=head2 table_columns

  $n->table_columns()

=cut

sub table_columns
{
    return ['arc_weight','-input'];
}


##############################################################################

=head2 rollback

Hooked by RDF::Base/init

=cut

sub rollback
{
    %DOMAIN_CACHE = ();
}


##############################################################################


1;

=head1 SEE ALSO

L<RDF::Base>,

=cut
