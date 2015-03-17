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

use Carp qw( cluck carp confess longmess );
use JSON; # to_json from_json
use Digest::MD5 qw( md5_base64 ); #);

use Para::Frame::Utils qw( throw debug datadump validate_utf8 );
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

    return bless( {sruct=>$struct, value=>$val}, $class );
}

##############################################################################

=head2 new_from_db

  $this->new_from_db( $value, $valtype )

=cut

sub new_from_db
{
    # Should always be in UTF8
    unless( utf8::is_utf8(  $_[1] ) )
    {
        utf8::decode( $_[1] ) or cluck "Failed to utf8-decode string ".$_[1];
    }

#    debug "parsing from db ".$_[1];
#    debug validate_utf8(\ $_[1] );

    my $struct = from_json($_[1]);
    return bless( {struct=>$struct, value=>$_[1]}, $_[0] );
}

##############################################################################

=head2 new

  $this->new( $time, $valtype )

Extension of L<Para::Frame::Time/get>

=cut

sub new
{
    my( $this, $in_value, $valtype ) = @_;
    my $class = ref($this) || $this;

#    debug "Creating a new json literal from ".$in_value;


    unless( defined $in_value )
    {
        return bless
        {
         'arc' => undef,
         'value' => undef,
         'valtype' => $valtype,
         struct => {},
        }, $class;
    }

    my $val;                    # The actual string
    if ( ref $in_value )
    {
        if ( ref $in_value eq 'SCALAR' )
        {
            $val = $$in_value;
        }
        elsif ( ref $in_value eq 'RDF::Base::Literal::String' )
        {
            $val = $in_value;
        }
        else
        {
            confess "Invalid value type '". (ref $in_value) ."': $in_value";
        }
    }
    else
    {
        $val = $in_value;
    }

    if ( utf8::is_utf8($val) )
    {
        if ( utf8::valid($val) )
        {
            if ( $val =~ $Para::Frame::Utils::latin1_as_utf8 )
            {
                confess longmess "Value '$val' DOUBLE ENCODED!!!";

#		$Para::Frame::REQ->result->message("Some text double encoded!");
            }
        }
        else
        {
            confess "Value '$val' marked as INVALID utf8";
        }
    }
    else
    {
        if ( $val =~ $Para::Frame::Utils::latin1_as_utf8 )
        {
            confess "HANDLE THIS (apparent undecoded UTF8: $val)";
            $val = deunicode($val);
        }

#	debug "Upgrading $val";
        utf8::upgrade( $val );
    }

    my $struct = from_json($val);

    my $lit = bless
    {
     'arc' => undef,
     'value' => $val,
     'valtype' => $valtype,
     'struct' => $struct,
    }, $class;

#    debug "Created string $val";
#    debug "Returning new ".$lit->sysdesig." ".refaddr($lit);
#    debug "  of valtype ".$lit->this_valtype->sysdesig;
#    cluck "GOT HERE" if $lit->plain =~ /^1/;

    return $lit;
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

=head2 as_string

=cut

sub as_string
{
    return $_[0]->{value};
}

##############################################################################

=head2 plain

=cut

sub plain
{
    return $_[0]->{value};
}

##############################################################################

=head2 syskey

=cut

sub syskey
{
    # Copy of RDF::Base::Literal::String/syskey

    if ( defined $_[0]->{'value'} )
    {
        # There might not be any wide characters even if the utf8 flag
        # is turned on. Threfore it might be exactly the same string
        # as a non-utf8-flagged string.

        if ( utf8::is_utf8( $_[0]->{'value'} ) )
        {
            my $encoded = $_[0]->{'value'};
            # Convert to bytes
            utf8::encode( $encoded );
            return sprintf("lit:%s", md5_base64($encoded));
        }
        return sprintf("lit:%s", md5_base64(shift->{'value'}));
    }
    else
    {
        return "lit:undef";
    }

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
