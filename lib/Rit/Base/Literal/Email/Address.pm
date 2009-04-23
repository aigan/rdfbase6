package Rit::Base::Literal::Email::Address;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

=head1 NAME

Rit::Base::Literal::Email::Address

=cut

use 5.010;
use strict;
use warnings;
use base qw( Rit::Base::Literal::String Para::Frame::Email::Address );

use Carp qw( cluck confess longmess );
use Mail::Address;
use CGI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Widget;

use Rit::Base::Utils qw( parse_propargs );
use Rit::Base::Constants qw( $C_intelligent_agent );


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
L<Rit::Base::Literal::String/parse>. (Avoid recursion)

Will throw exception if not a correct email address

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    if( ref $val eq 'SCALAR' )
    {
	$val = $$val;
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::Email::Address" )
    {
	return $val;
    }
    elsif( UNIVERSAL::isa $val, "Para::Frame::Email::Address" )
    {
	# Good
    }
    elsif( UNIVERSAL::isa $val, "Mail::Address" )
    {
	# Good
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Undef" )
    {
	$val = undef;
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal" )
    {
	$val = $val->plain;
    }
    else
    {
	confess "Can't parse $val";
    }

    my $a = $class->Para::Frame::Email::Address::parse($val);
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

C<method> defaults to C<format>

=cut

sub as_html
{
    my( $a, $args_in ) = @_;

    if( $a->broken )
    {
	my $str = $a->original;
	return "<span class=\"broken\">$str</a>";
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
	if( $key =~ /^href_/ )
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
    my $value  = $_[0]->plain;
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
L<Rit::Base::Object/as_string>.

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
    return Rit::Base::Literal::Class->get_by_label('email_address');
}


##############################################################################

=head3 vacuum

=cut

sub vacuum
{
    my( $a, $args ) = @_;

    my $class = ref $a;
    my $orig = $a->original;
    my $addr  = lc($a->address);

    debug "vaccuum $orig";

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

L<Rit::Base::Literal>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
