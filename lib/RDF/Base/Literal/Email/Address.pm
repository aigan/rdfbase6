package RDF::Base::Literal::Email::Address;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::Email::Address

=cut

use 5.010;
use strict;
use warnings;
use base qw( RDF::Base::Literal::String Para::Frame::Email::Address );

use Carp qw( cluck confess longmess );
use Mail::Address;
#use CGI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );
use Para::Frame::Widget;

use RDF::Base::Utils qw( parse_propargs );
use RDF::Base::Constants qw( $C_intelligent_agent );


=head1 DESCRIPTION

Represents an Email Address

=cut


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

##############################################################################

=head3 new

  $this->new( $value, $valtype )

Calls L<Para::Frame::Email::Address/new>

Will B<not> throw an exception if email address is faulty

=cut

sub new
{
    my( $class, $in_value, $valtype ) = @_;

    my $a = $class->Para::Frame::Email::Address::new($in_value);

    $a->{'valtype'} = $valtype;

    return $a;
}


##############################################################################

=head3 parse

Wrapper for L<Para::Frame::Email::Address/parse> that reimplements
L<RDF::Base::Literal::String/parse>. (Avoid recursion)

Will NOT throw exception if not a correct email address

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;

    my $parse_val;

    if( UNIVERSAL::isa $val_in, "RDF::Base::Literal::Email::Address" )
    {
	return $val_in;
    }
    elsif( UNIVERSAL::isa $val_in, "Para::Frame::Email::Address" )
    {
        $parse_val = $val_in->original;
    }
    elsif( UNIVERSAL::isa $val_in, "Mail::Address" )
    {
        $parse_val = $val_in->format;
    }
    elsif( UNIVERSAL::isa $val_in, "RDF::Base::Undef" )
    {
	$parse_val = undef;
    }
    else
    {
        $parse_val = $val_in;
    }

#    debug "Parse val ".datadump($parse_val,1);

    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($parse_val, $args_in);

    my $val_mod;

    if( UNIVERSAL::isa $val, "RDF::Base::Literal" )
    {
	$val_mod = $val->plain;
    }
    elsif( ref $val_in eq 'SCALAR' )
    {
        $val_mod = $$val;
    }

#    debug "Parse email address $val_mod";

    my $a = $class->Para::Frame::Email::Address::parse_tolerant($val_mod);
    $a->{'valtype'} = $valtype;
    return $a;
}


##############################################################################

=head3 new_from_db

Assumes that the value from DB is correct

=cut

sub new_from_db
{
#    cluck "empty address" unless $_[1]; ### DEBUG

    my $a = $_[0]->Para::Frame::Email::Address::new($_[1]);
    $a->{'valtype'} = $_[2];
    return $a;
}


#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

##############################################################################

=head2 as_html

  $a->as_html( \%args )

Supported args are:

  method
  tag_*

C<method> defaults to C<format>

=cut

sub as_html
{
    my( $a, $args_in ) = @_;

    if( $a->broken )
    {
	my $str = $a->original;
	return "<span class=\"broken\">$str</span>";
    }

    my( $args ) = parse_propargs($args_in);
    my $method = $args->{'method'} || 'format';

    my $label;
    if( $method and $a->can($method) )
    {
	$label = $a->$method();
    }
    $label ||= $a->format;

    my $adr = $a->address;
#    my $full = CGI->escapeHTML($label);

    my %attr;
    foreach my $key ( keys %$args )
    {
	# DEPRECATED
	if( $key =~ /^href_/ )
	{
	    $attr{ $key } = $args->{$key};
	}

	if( $key =~ /^tag_/ )
	{
	    $attr{ $key } = $args->{$key};
	}
    }
    if( $args->{'id'} )
    {
	$attr{ id } = $args->{'id'};
    }

    return Para::Frame::Widget::jump($label, "mailto:$adr", \%attr);
#    return "<a href=\"mailto:$adr\">$full</a>";
}


##############################################################################

=head2 sysdesig

  $a->sysdesig()

The designation of an object, to be used for node administration or
debugging.

=cut

sub sysdesig
{
    my $value  = $_[0]->plain || 'undef';
    return "email_address:$value";
}


##############################################################################

=head2 desig

  $a->desig()

The designation of an object, to be used for node administration or
debugging. Uses L<Para::Frame::Email::Address/desig>

=cut

sub desig
{
    return $_[0]->Para::Frame::Email::Address::desig();
}


##############################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    return "email_address:".$_[0]->plain;
}


##############################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.

=cut

sub literal
{
    return $_[0]->format;
}


##############################################################################

=head3 loc

  $lit->loc

Just returns the plain string

=cut

sub loc
{
    return shift->format;
}


##############################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

Returns: The address part L<Para::Frame::Email::Address/address>

NB! Only store the address part in the DB. For broken email addresses,
it will be the original string.

=cut

sub plain
{
    return $_[0]->address;
}


##############################################################################

=head3 as_string

Used in L<Para::Frame::Email::Address>. Overrides
L<RDF::Base::Object/as_string>.

=cut

sub as_string
{
    return $_[0]->format;
}


##############################################################################

=head3 name

Overrides L<Para::Frame::Email::Address/name>. Using the name of the
node pointing to this literal, if existing and if no name is found in
the email itself.

=cut

sub name
{
    my( $a ) = @_;

    return undef unless $a->address;
#    debug "Finding a name for ".$a->address;

    if( my $name = $a->SUPER::name )
    {
	return $name;
    }
    elsif( my $subj = $a->subj )
    {
#	debug "  subj ".$subj->sysdesig;
	return $subj->name->loc;
    }

    return undef;
}


##############################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return RDF::Base::Literal::Class->get_by_label('email_address');
}


##############################################################################

=head3 vacuum_facet

=cut

sub vacuum_facet
{
    my( $a, $args ) = @_;

    my $class = ref $a;
    my $orig = $a->original || '';
    my $addr  = lc($a->address||'');

    debug 2, "vaccuum $orig";

    if( $orig ne $addr )
    {
	debug "  Cleaning to $addr";

	my $a_new = $class->new($addr, $a->this_valtype);

	if( my $arc = $a->lit_revarc )
	{
	    $arc->set_value( $a_new, $args );

	    if( my $name = $a->name )
	    {
		my $subj = $arc->subj;
		if( $subj->has_value({'is'=>$C_intelligent_agent }, $args) )
		{
		    unless( $subj->prop('name',undef,$args) )
		    {
			$subj->add({name=>$name},
				   { %$args,
				     'activate_new_arcs' => 1,
				   });
		    }
		}
	    }
	}
    }
}


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Literal>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
