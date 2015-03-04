package RDF::Base::Literal::JSON;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2015 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::JSON

=cut

use 5.010;
use strict;
use warnings;
use base qw(  RDF::Base::Literal );

use Carp qw( cluck carp confess );
use JSON; # to_json from_json

use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Reload;

#use RDF::Base::Utils qw( parse_propargs query_desig );
#use RDF::Base::Widget qw( build_field_key );


=head1 DESCRIPTION

Subclass of L<RDF::Base::Literal>. Returns data as nested perl structure.

=cut

# use overload
#     '0+'   => sub{+($_[0]->{'value'})},
#     '+'    => sub{$_[0]->{'value'} + $_[1]},
#   ;


##############################################################################

=head2 parse

  $class->parse( \$value, \%args )


Supported args are:
  valtype
  coltype
  arclim

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    debug "parsing ".$val;

    my $struct;

    if ( ref $val eq 'SCALAR' )
    {
        $struct = from_json($$val);
    }
    else
    {
        confess "Can't parse $val";
    }

    return bless( {sruct=>$struct}, $class );
}

##############################################################################

=head2 new_from_db

  $this->new_from_db( $value, $valtype )

=cut

sub new_from_db
{
    debug "parsing from db ".$_[1];

    my $struct = from_json($_[1]);
    return bless( {struct=>$struct}, $_[0] );
}

##############################################################################

=head2 new

  $this->new( $time, $valtype )

Extension of L<Para::Frame::Time/get>

=cut

sub new
{
    my $this = shift;

    die "FIXME";
}

##############################################################################

=head2 get

  $this->get( $time, $valtype )

Extension of L<Para::Frame::Time/get>

=cut

sub get
{
    return shift->new(@_);
}

##############################################################################

=head2 literal

=cut

sub literal
{
    return $_[0];
}

##############################################################################

=head3 json

=cut

sub json
{
    return $_[0]->{struct};
}

##############################################################################

=head2 wuirc

Display field for updating a date property of a node

var node must be defined

prop pred is required

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    die "FIXME";

}


##############################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return RDF::Base::Literal::Class->get_by_label('json_data');
}

##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Literal>

=cut
