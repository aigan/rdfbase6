package RDF::Base::Literal::Time;
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

RDF::Base::Literal::Time

=cut

use 5.010;
use strict;
use warnings;
use base qw( Para::Frame::Time RDF::Base::Literal );

use Carp qw( cluck carp confess );
use DateTime::Incomplete;

use Para::Frame::Utils qw( throw debug datadump );
use Para::Frame::Widget qw( label_from_params calendar );
use Para::Frame::L10N qw( loc );
#use Para::Frame::Reload;

use RDF::Base::Utils qw( parse_propargs query_desig );


=head1 DESCRIPTION

Subclass of L<Para::Frame::Time> and L<RDF::Base::Literal>.

=cut

# use overload
#     '0+'   => sub{+($_[0]->{'value'})},
#     '+'    => sub{$_[0]->{'value'} + $_[1]},
#   ;


##############################################################################

=head2 parse

  $class->parse( \$value, \%args )

For dates between 1900 - 2020

For dates beyond this, use RB::Literal::Time::Historic

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

#    debug "parsing time ".$val;

    my $date;

    if( ref $val eq 'SCALAR' )
    {
	$date = $class->new($$val, $valtype);
    }
    elsif( UNIVERSAL::isa $val, "RDF::Base::Literal::Time" )
    {
	if( $valtype->equals( $val->this_valtype ) )
	{
	    $date = $val;
	}
	else
	{
	    $date = $class->new($val->plain, $valtype);
	}
    }
    elsif( UNIVERSAL::isa $val, "RDF::Base::Literal::String" )
    {
	$date = $class->new($val->plain, $valtype);
    }
    elsif( UNIVERSAL::isa $val, "RDF::Base::Undef" )
    {
	$date = $class->new(undef, $valtype);
    }
    else
    {
	confess "Can't parse $val";
    }

#    debug "Returning date ".$date->sysdesig;


    # For dates beyond this, use RB::Literal::Time::Historic
    #
    if( $date->year > 2020 or $date->year < 1900 )
    {
	throw 'validation', loc "Date [_1] out of range", $date;
    }

    return $date;
}

##############################################################################

=head2 new_from_db

  $this->new_from_db( $value, $valtype )

=cut

sub new_from_db
{
    # Should parse faster since we know this is a PostgreSQL type
    # timestamp with time zone...

#    debug "new_from_db Time $_[1]";
    my $time = $RDF::dbix->parse_datetime($_[1], $_[0]);
#    debug "  got ".$time->sysdesig;

    my $tz = undef;
    if( $time->year > 2100 or $time->year < 1900 )
    {
	debug "Using floating for historical ".$time->sysdesig;
	$tz = 'floating';
    }

    $time->init($tz);
#    debug " after init: ".$time->sysdesig;

    $time->{'valtype'} = $_[2];
    return $time;
}

##############################################################################

=head2 new

  $this->new( $time, $valtype )

Extension of L<Para::Frame::Time/get>

=cut

sub new
{
    my $this = shift;

    my( $time, $valtype);
    if( scalar @_ > 2 )
    {
	$time = $this->SUPER::new(@_);
    }
    else
    {
	$time = $this->SUPER::get($_[0]);
	$valtype = $_[1];
    }

    unless( defined $time )
    {
#	$time = DateTime::Incomplete->new();
#	my $class = ref $this || $this;
#	bless($time, $class)->init;
	use RDF::Base::Undef;
	return RDF::Base::Undef->new(); ### FIXME!
    }

    $time->{'valtype'} = $valtype;

    return $time;
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
    my $str = $_[0]->format_datetime;
    return $str;
}

##############################################################################


=head2 now

NOTE: Exported via Para::Frame::Time

=cut

sub now
{
#    carp "RDF::Base::Literal::Time::now called";
    return bless(DateTime->now,'RDF::Base::Literal::Time')->init;
}

##############################################################################

=head2 date

=cut

sub date
{
    my $time = Para::Frame::Time->get(@_);
    if( $time )
    {
	return bless($time,'RDF::Base::Literal::Time');
    }
    else
    {
	return RDF::Base::Literal::Time->new(undef);
    }
}

##############################################################################

=head2 wuirc

Display field for updating a date property of a node

var node must be defined

prop pred is required

the query param "arc___pred_$pred__subj_$subjvarname" can be used for
default new value

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = RDF::Base->Resource;
    my $q = $Para::Frame::REQ->q;

    my $newsubj = $args->{'newsubj'};
    my $tdlabel = $args->{'tdlabel'};
    my $label = $args->{'label'};
    my $arc = $args->{'arc'};
    my $arc_type = $args->{'arc_type'} || 'singular';

    my $id = $args->{'id'};

    $args->{'size'} ||= 18;

    my %cal_args;
    foreach my $key qw(( size class onUpdate showsTime style ))
    {
	next unless defined $args->{$key};
	next unless length $args->{$key};

	$cal_args{$key} = $args->{$key};
    }


#    debug "TIME WUIRC";
#    debug query_desig($args);


    my $subj_id = $subj->id;

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = RDF::Base::Pred->get_by_label($predname);
    }
    debug 2, "Predname in date wuirc: $predname";

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $id,
			       label_class => $args->{'label_class'},
			      });


    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($pred, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= ( $arc->value->desig($args) || $args->{'default_value'} ).'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
    }
    elsif( $subj->empty )
    {
#	# TODO: Make the default date work
#	# Setting a default date and time to the calendar
#	my $date = now();
#	$date->add( days => 1 );
#	$date->set(
#		   hour => 9,
#		   minute => 0,
#		   second => 0,
#		   nanosecond => 0,
#		  );
#	$cal_args{'date'} = $date;

	my $fieldname = "arc___pred_${predname}__subj_${subj_id}";
	$id ||= $fieldname;
	$out .= &calendar($fieldname,  $args->{'default_value'} || '',
			  {
			   %cal_args,
			   id => $id,
			  });
	$out .= $arc->edit_link_html
	  if( $arc );
    }
    elsif( $subj->list($pred)->size > 1 )
    {
	$out .= "<ul>";

	foreach my $arc ( $subj->arc_list($pred) )
	{
	    if( $arc->objtype )
	    {
		$out .= "<li><em>This is not a date!!</em> ".
		  $arc->edit_link_html ."</li>";
	    }
	    else
	    {
		$out .= "<li>";

		my $arc_id = $arc->id;
		my $fieldname = "arc_${arc_id}__pred_${predname}__subj_${$subj_id}";
		$id ||= $fieldname;
		my $value_new = $q->param("arc___pred_${predname}__subj_${$subj_id}") ||
		  $arc->value->desig($args) || $args->{'default_value'};
		$out .= &calendar($fieldname, $value_new,
				  {
				   %cal_args,
				   id => $fieldname,
				  });
		$out .= $arc->edit_link_html
		  if( $arc );
		$out .= "</li>";
	    }
	}

	$out .= "</ul>";
    }
    else
    {
	my $arc = $subj->first_arc($pred);
	if( $arc->objtype )
	{
	    $out .= "<em>This is not a date!</em>";
	}
	else
	{
	    my $arc_id = ( $arc_type eq 'singular' ?
			   'singular' : $arc ? $arc->id : '' );
	    my $fieldname = "arc_${arc_id}__pred_${predname}__subj_${subj_id}";
	    $id ||= $fieldname;
	    my $value_new = $q->param("arc___pred_${predname}__subj_${subj_id}")
	      || $subj->prop($pred)->desig($args) || $args->{'default_value'};

	    $out .= &calendar($fieldname, $value_new,
			      {
			       %cal_args,
			       id => $id,
			      });
	    $out .= $arc->edit_link_html
	      if( $arc );
	}
    }

    return $out;
}


##############################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return RDF::Base::Literal::Class->get_by_label('valdate');
}

##############################################################################
#
#=head3 defined
#
#=cut
#
#sub defined
#{
#    if( UNIVERSAL::isa $_[0], 'DateTime::Incomplete' )
#    {
#	if( $_[0]->is_undef )
#	{
#	    return 0;
#	}
#    }
#
#    return 1;
#}
#
##############################################################################
#
#=head2 format_datetime
#
#  $t->format_datetime()
#
#Returns a string using the format given by L<Para::Frame/configure>.
#
#=cut
#
#sub format_datetime
#{
#    if( UNIVERSAL::isa $_[0], 'DateTime::Incomplete' )
#    {
#	if( $_[0]->is_undef )
#	{
#	    return "";
#	}
#	else
#	{
#	    return $_[0]->iso8601;
#	}
#    }
#
#    return $Para::Frame::Time::FORMAT->format_datetime($_[0]);
#}
#
#
##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Literal>,
L<Para::Frame::Time>

=cut
