package RDF::Base::Literal::String;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2021 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::String

=cut

use 5.014;
use warnings;
no if $] >= 5.018, warnings => "experimental";

use base qw( RDF::Base::Literal );
use overload
  'cmp'  => 'cmp_string',
  '<=>'  => 'cmp_numeric',
  '0+'   => sub{+($_[0]->literal)},
  '+'    => sub{$_[0]->literal + $_[1]},
  fallback => 1,
  ;

use Carp qw( cluck confess longmess );
use Digest::MD5 qw( md5_base64 ); #);
use Scalar::Util qw( looks_like_number refaddr );
use Encode;                     # decode FB_QUIET

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump trim throw deunicode escape_js validate_utf8 );
use Para::Frame::Widget qw( input textarea htmlarea hidden radio input_image );

use RDF::Base::Utils qw( is_undef valclean truncstring query_desig parse_propargs proplim_to_arclim );
use RDF::Base::Widget qw( aloc build_field_key );
use RDF::Base::Constants qw( $C_textbox $C_text_large $C_text_html );

=head1 DESCRIPTION

Represents a String L<RDF::Base::Literal>.

=cut


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

##############################################################################

=head3 new

=cut

sub new
{
	my( $this, $in_value, $valtype ) = @_;
	my $class = ref($this) || $this;

	unless( defined $in_value )
	{
		return bless
		{
		 'arc' => undef,
		 'value' => undef,
		 'valtype' => $valtype,
		}, $class;
	}

	my $val;											# The actual string
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
				debug longmess "Value '$val' DOUBLE ENCODED!!!";
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
			debug "HANDLE THIS (apparent undecoded UTF8: $val)";
			$val = deunicode($val);
		}

#	debug "Upgrading $val";
		utf8::upgrade( $val );
	}


	my $lit = bless
	{
	 'arc' => undef,
	 'value' => $val,
	 'valtype' => $valtype,
	}, $class;

#    debug "Created string $val";
#    debug "Returning new ".$lit->sysdesig." ".refaddr($lit);
#    debug "  of valtype ".$lit->this_valtype->sysdesig;
#    cluck "GOT HERE" if $lit->plain =~ /^1/;

	return $lit;
}


##############################################################################

=head3 new_from_db

Values from valbin those valtype is NOT a subclass of text_large, will
not be treated as text and thus not converted from UTF8 encoding.

=cut

sub new_from_db
{
	my( $class, $val, $valtype ) = @_;

	$valtype or cluck "No valtype";
	if ( $valtype->equals($C_text_large) or
			 $valtype->has_value({ scof => $C_text_large }) )
	{
#        debug "Got a valbin value that IS a TEXT_LARGE";
		unless( utf8::decode( $val ) )
		{
			debug 0, "Failed to convert to UTF8!";
			my $res;
			while ( length $val )
			{
				$res .= Encode::decode("UTF-8", $val, Encode::FB_QUIET);
				$res .= substr($val, 0, 1, "") if length $val;
			}
			$val = $res;
			debug "Conversion result: $val";
		}
#	utf8::decode( $val );
#        debug validate_utf8(\$val);
	}
	elsif ( $valtype->coltype eq 'valbin' )
	{
		# treat as non-text
		debug sprintf "Got a valbin value that is not text_large (%s)", $valtype->sysdesig;
	}
	elsif ( defined $val )
	{
		utf8::upgrade( $val );

		if ( $val =~ $Para::Frame::Utils::latin1_as_utf8 )
		{
#	    cluck "UNDECODED UTF8 in DB: $val)";
			debug "UNDECODED UTF8 in DB: $val)";
#	    unless( utf8::decode( $val ) )
#	    {
#		debug 0, "Failed to convert to UTF8!";
#		my $res;
#		while( length $val )
#		{
#		    $res .= Encode::decode("UTF-8", $val, Encode::FB_QUIET);
#		    $res .= substr($val, 0, 1, "") if length $val;
#		}
#		$val = $res;
#		debug "Conversion result: $val";
#	    }
		}
	}

	return bless
	{
	 'arc' => undef,
	 'value' => $val,
	 'valtype' => $valtype,
	}, $class;
}


##############################################################################

=head3 parse

  $class->parse( \$value, \%args )

For parsing any type of input. Expecially as given by html forms.

Parsing an existing literal object may MODIFY it''s content and valtype


Supported args are:
  valtype
  coltype
  arclim

Will use L<RDF::Base::Resource/get_by_anything> for lists and queries.

The valtype may be given for cases there the class handles several
valtypes.

=cut

sub parse
{
	my( $class, $val_in, $args_in ) = @_;
	my( $val, $coltype, $valtype, $args ) =
		$class->extract_string($val_in, $args_in);

	if ( $coltype eq 'obj' )
	{
		confess "FIXME";
		$coltype = $valtype->coltype;
		debug "Parsing as $coltype: ".query_desig($val_in);
	}

	my $val_mod;
	if ( ref $val eq 'SCALAR' )
	{
		$val_mod = $$val;
	}
	elsif ( UNIVERSAL::isa $val, "RDF::Base::Literal::String" )
	{
		$val_mod = $val->plain;
	}
	else
	{
		confess "Can't parse $val";
	}

	if ( defined $val_mod )
	{
		# Remove invisible characters, other than LF
		$val_mod =~ s/(?!\n)\p{Other}//g;
	}

	if ( $coltype eq 'valtext' )
	{
		unless( length($val_mod||'') )
		{
			debug "returning undef value";
			return $class->new( undef, $valtype );
		}

		# Cleaning up UTF8...
		if ( $val_mod =~ /Ã./ )
		{
			debug "UNDECODED UTF-8 STRING: $val_mod";

			my $res;
			while ( length $val_mod )
			{
				$res .= Encode::decode("UTF-8", $val_mod, Encode::FB_QUIET);
				$res .= substr($val_mod, 0, 1, "") if length $val_mod;
			}
			$val_mod = $res;
		}

		# Repair chars in CP 1252 text,
		# incorrectly imported as ISO 8859-1.
		# For example x96 (SPA) and x97 (EPA)
		# are only used by text termianls.
		$val_mod =~ s/\x{0080}/\x{20AC}/g;		 # Euro sign
		$val_mod =~ s/\x{0085}/\x{2026}/g;		 # Horizontal ellipses
		$val_mod =~ s/\x{0091}/\x{2018}/g; # Left single quotation mark
		$val_mod =~ s/\x{0092}/\x{2019}/g; # Right single quotation mark
		$val_mod =~ s/\x{0093}/\x{201C}/g; # Left double quotation mark
		$val_mod =~ s/\x{0094}/\x{201D}/g; # Right double quotation mark
		$val_mod =~ s/\x{0095}/\x{2022}/g; # bullet
		$val_mod =~ s/\x{0096}/\x{2013}/g; # en dash
		$val_mod =~ s/\x{0097}/\x{2014}/g; # em dash


		# NOT Remove Unicode 'REPLACEMENT CHARACTER'
		#$val_mod =~ s/\x{fffd}//g;

		# Replace Space separator chars
		$val_mod =~ s/\p{Zs}/ /g;

		# Replace Line separator chars
		$val_mod =~ s/\p{Zl}/\n/g;

		# Replace Paragraph separator chars
		$val_mod =~ s/\p{Zp}/\n\n/g;


		$val_mod =~ s/[ \t]*\r?\n/\n/g; # CR and whitespace at end of line
		$val_mod =~ s/^\s*\n//;         # Leading empty lines
		$val_mod =~ s/\n\s+$/\n/;       # Trailing empty lines

	}
	elsif ( $coltype eq 'valfloat' )
	{
		if ( defined $val_mod )
		{
			trim($val_mod);
			$val_mod =~ s/,/./;				# Handling swedish numerical format...

			unless( looks_like_number( $val_mod ) )
			{
				throw 'validation', "String $val_mod is not a number";
			}
		}
	}
	elsif ( $coltype eq 'valbin' )
	{
		unless( length($val_mod||'') )
		{
			return $class->new( undef, $valtype );
		}
	}
	else
	{
		confess "coltype $coltype not handled by this class";
	}

#    debug "Setting value to $val_mod";

	# Always return the incoming object. This may MODIFY the object
	#
	if ( UNIVERSAL::isa $val, "RDF::Base::Literal::String" )
	{
		$val->{'value'} = $val_mod;
		$val->{'valtype'} = $valtype;
		return $val;
	}

	# Implementing class may not take scalarref
	return $class->new( $val_mod, $valtype );
}


#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

##############################################################################

=head2 desig

  $n->desig()

The designation of the literal, meant for human admins

=cut

sub desig             # The designation of obj, meant for human admins
{
	my( $val ) = @_;

	unless ( defined $val->{'value'} )
	{
		return "<undef>";
	}

	return $val->{'value'};
}


##############################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
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
#            my $val = sprintf("lit:utf8:%s", md5_base64($encoded));
#            debug "syskey $val";
#            return $val;
			return sprintf("lit:%s", md5_base64($encoded));
		}
#        my $val = sprintf("lit:%s", md5_base64($_[0]->{'value'}));
#        debug "syskey $val";
#        return $val;
		return sprintf("lit:%s", md5_base64(shift->{'value'}));
	}
	else
	{
		return "lit:undef";
	}
}


##############################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.

=cut

sub literal
{
#    debug "\t\t\t".$_[0]->{'value'};
	return $_[0]->{'value'};
}


##############################################################################

=head2 cmp_string

=cut

sub cmp_string
{
	my $val1 = $_[0]->plain;
	my $val2 = $_[1];

	unless( defined $val1 )
	{
		$val1 = is_undef;
	}

	if ( ref $val2 )
	{
		if ( $val2->defined )
		{
			$val2 = $val2->desig;
		}
	}
	else
	{
		unless( defined $val2 )
		{
			$val2 = is_undef;
		}
	}

	if ( $_[2] )
	{
		return $val2 cmp $val1;
	}
	else
	{
		return $val1 cmp $val2;
	}
}


##############################################################################

=head2 cmp_numeric

=cut

sub cmp_numeric
{
	my $val1 = $_[0]->plain || 0;
	my $val2 = $_[1]        || 0;

	unless( defined $val1 )
	{
		$val1 = is_undef;
	}

	if ( ref $val2 )
	{
		if ( $val2->defined )
		{
			$val2 = $val2->desig;
		}
		else
		{
			$val2 = 0;
		}
	}

	if ( $_[2] )
	{
		return( $val2 <=> $val1 );
	}
	else
	{
		return( $val1 <=> $val2 );
	}
}


##############################################################################

=head3 loc

  $lit->loc

  $lit->loc(@args)

Uses the args in L<Para::Frame::L10N/compute>.

Returns: the value as a plain string

=cut

sub loc
{
	my $lit = shift;

	unless ( defined $lit->{'value'} )
	{
		return "";
	}

	if ( @_ )
	{
		my $str = $lit->{'value'};
		my $lh = $Para::Frame::REQ->language;
		my $mt = $lit->{'maketext'} ||= $lh->_compile($str);
		return $lh->compute($mt, \$str, @_);
	}
	else
	{
		my $str = $lit->{'value'};
		if ( utf8::is_utf8( $str ) )
		{
			# Good...
#	    my $len1 = length($str);
#	    my $len2 = bytes::length($str);
#	    debug sprintf "Returning %s(%d/%d):\n", $str, $len1, $len2;
		}
		else
		{
#	    debug "String '$str' not marked as UTF8; upgrading";
			utf8::upgrade($str);
		}
		return $str;
	}
}


##############################################################################

=head3 value

aka literal

=cut

sub value
{
	warn "About to confess...\n";
	confess "wrong turn";
	return $_[0]->{'value'};
}


##############################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

=cut

sub plain
{
	return $_[0]->{'value'};
}


##############################################################################

=head3 clean

Returns the clean version of the value as a Literal obj

=cut

sub clean
{
	return $_[0]->new( valclean( $_[0]->plain ) );
}


##############################################################################

=head3 clean_plain

Returns the clean version of the value as a plain string

=cut

sub clean_plain
{
	return valclean( $_[0]->plain );
}


##############################################################################

=head3 begins

  $string->begins( $substr )

Returns true if the string begins with $substr.

=cut

sub begins
{
	unless ( defined $_[0]->{'value'} )
	{
		return 0;
	}

	return $_[0]->{'value'} =~ /^$_[1]/;
}

##############################################################################

=head3 this_valtype

=cut

sub this_valtype
{
	if ( ref $_[0] )
	{
		if ( my $valtype = $_[0]->{'valtype'} )
		{
			return $valtype;
		}

		if ( looks_like_number($_[0]->{'value'}) )
		{
			return RDF::Base::Literal::Class->get_by_label('valfloat');
		}
	}

	return RDF::Base::Literal::Class->get_by_label('valtext');
}

##############################################################################

=head2 wuirc

  $class->wuirc( $subj, $pred, \%args )

Display field for updating a string property of a node

Supported args are:

  proplim
  arclim
  default_create
  unique_arcs_prio
  range (valtype)
  range_scof
  rows
  cols
  size
  inputtype
  maxlength
  newsubj
  maxw
  maxh
  label
  tdlabel
  separator
  id
  label_class
  disabled
  image_url
  class
  default_value
  vnode
  multi



document newsubj!

the query param "arc___pred_$pred__subj_$nid" can be used for default new value

the query param "arc___pred_$pred" can be used for default new value

=cut

sub wuirc
{
	my( $class, $node, $pred, $args_in ) = @_;
	my( $args ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(5);
	my $DEBUG = Para::Frame::Logging->at_level(3);
#    my $DEBUG = 0;

	no strict 'refs';							# For &{$inputtype} below
	my $out = "";
	my $R = RDF::Base->Resource;
	my $req = $Para::Frame::REQ;

	unless( $req->user->has_cm_access )
	{											 ### FIXME: Not ready to use for non-admins...
		$args =
			parse_propargs({
											%$args,
											unique_arcs_prio => ['submitted','active'],
											arclim => [['submitted','created_by_me'],'active'],
										 });
	}

	my $divid = $args->{divid};

	# Let range be the target valtype, regardless of if this is a
	# reverse arc or not.
	#
	my $range = $args->{'range'} || $args->{'range_scof'}
		|| $class->this_valtype;
	my $disabled = $args->{'disabled'} ? 1 : 0;

#    debug "Range ".$range->sysdesig;

	my $extra_html = "";					# For adding hidden fields, etc.

	my $onchange = '';
	my $pattern = $range->has_input_pattern;
	if ( $pattern )
	{
		my $pattern_errmsg = escape_js( CGI->escapeHTML(
																										Para::Frame::L10N::loc('Input error') . "\n" .
																										$range->has_input_pattern_errmsg->loc
																									 ));

		# javascript through html escaping...
#	debug "Pattern before escape: ". $pattern;
		$pattern =~ s/\\/\\\\/g;
		$pattern =~ s/\$/\\\$/g;
#	debug "Pattern after escape: ". $pattern;

		# TODO: stop the form from submitting if pattern check failed

		$onchange = 'check_pattern(\''. $pattern .'\', this.value, \''.
			$pattern_errmsg .'\')';
	}

	if ( $args->{'live_update'} )
	{
		$onchange = "RDF.Base.pageparts['$divid'].node_update()";
		$args->{'onchange'} = $onchange;
	}

	my $tb = $C_textbox;
	my $tl = $C_text_large;

	$args->{tag_attr} ||= {};
	$args->{'class'} ||= $args->{tag_attr}{class} ||= '';
	my $size = $args->{'size'} ||"";
	my $wide_class = $size ? '' : ' wide';
	if ( $args->{'class'} =~ /\bwide\b/ )
	{
		$wide_class = ' wide';
		$args->{'class'} =~ s/\s*wide\s*/ /;
	}
	$args->{'class'} .= $wide_class;

	if (	not defined $args->{'class'} and
				( $range->equals($C_text_html) or
					$range->scof($C_text_html) ))
	{
		$args->{'class'} = 'html_editable';
	}

	if ( ($args->{'rows'}||0) > 1 or
			 $range->equals($tb) or
			 $range->scof($tb)   or
			 $range->equals($tl) or
			 $range->scof($tl) )
	{
		unless ( ($args->{'class'}||'') =~ /\bwide\b/ )
		{
			$args->{'size'} = $args->{'cols'};
			# also remove size?
		}
		$args->{'inputtype'} = 'textarea';
		$args->{'rows'} ||= 3;
	}

	unless( $range->coltype eq 'valbin' )
	{
		$args->{'maxlength'} ||= 2800;
	}

	my $rev = $args->{'rev'} || 0;
	# Subj is used also for reverse arcs in the input key
	my $src = $rev ? 'obj' : 'subj';


	my $inputtype = $args->{'inputtype'} || 'input';

	my $predname;
	if ( ref $pred )
	{
		$predname = $pred->label;

		if ( $DEBUG )
		{
			debug "String wuirc for $predname";
			if ( $rev )
			{
				debug "rev $predname class is ". $pred->domain->instance_class;
			}
			else
			{
				debug "$predname class is ". $pred->range->instance_class;
			}
		}
	}
	else
	{
		$predname = $pred;
		# Only handles pred nodes
		$pred = RDF::Base::Pred->get_by_label($predname);
	}

	debug "wub $inputtype $predname ($rev) for ".$node->sysdesig if $DEBUG;

	my $newsubj = $args->{'newsubj'};
	my $rows = $args->{'rows'};
	my $maxw = $args->{'maxw'};
	my $maxh = $args->{'maxh'};

	my $field_key = build_field_key({
																	 ($rev?'rev':'').pred => $predname,
																	 subj => $node,
																	});
	$args->{'id'} ||= $field_key;
	$args->{'fields'}{$field_key} ++;

#    debug "Fieldkey ".$args->{'id'};

	my $proplim = $args->{'proplim'} || undef;
	my $arclim = $args->{'arclim'} || ['active','submitted'];

#    debug 2, "Using proplim ".query_desig($proplim); # DEBUG
#    debug 2, "Using arclim ".query_desig($arclim); # DEBUG


	# Previous versions used arg multi. Migrate to use
	# range_card_max. Use arc_type for backward compatability.
	#
	my $multi = $args->{'multi'};
	unless ( defined $args->{'arc_type'} )
	{
		if ( $pred->first_prop('range_card_max')->equals(1) )
		{
			$args->{'arc_type'} = 'singular';
		}
	}
	my $arc_type = $args->{'arc_type'};
	my $singular = (($arc_type||'') eq 'singular') ? 1 : undef;

#    $multi //= $singular ? 0 : 1; # Default to singular...


	my $no_arc = 0;								# for adding a second input field

	my $columns = $args->{'columns'} ||
		$range->instance_class->table_columns( $pred, $args );
	push @$columns, '-edit_link';
	$args->{'columns'} = $columns;
	$args->{'source'} = $node;

	debug "Columns set to @$columns" if $DEBUG;



	######### BEGIN arc loop ########################
	#

	if ( $disabled )
	{
#        debug "disabled";
		$out .= "<table class=\"wuirc$wide_class\">\n";

		my $arclist = $node->arc_list($predname, $proplim, $args);

		while ( my $arc = $arclist->get_next_nos )
		{
			$out .= $arc->table_row( $args );
		}
	}
	elsif ( $rev ?
					$node->revlist($predname,$proplim,$arclim)->is_true :
					$node->list($predname,$proplim,$arclim)->is_true )
	{
#        debug "previous values";
		$out .= "<table class=\"wuirc text_input$wide_class\">\n";

		my $node_id = $node->id;

		my $arcversions =  $node->arcversions($predname, proplim_to_arclim($proplim), {rev=>$rev});
		my @arcs = map RDF::Base::Arc->get($_), keys %$arcversions;

		debug "Arcs list: @arcs" if $DEBUG;
		my $list_weight = 0;

#        debug "Args: ".query_desig($args);

		foreach my $arc ( RDF::Base::List->new(\@arcs)->
											sorted(['obj.is_of_language.code',
															{
															 on=>'weight', dir=>'desc'},
															{
															 on=>'obj.weight', dir=>'desc'}])->
											as_array )
		{
			$out .= $arc->table_row( $args );
		}



#        if( 0 ) ####### OLD LOOP
#        {
#            my $arc; ### Just for syntax check now...
#
#            my $arc_id = $arc->id;
#            #debug $arc_id;
#
#            if ( my $lang = $arc->value_node->list('is_of_language', undef,'auto') )
#            {
#                $out .= "(".$lang->desig."): ";
#            }
#
#            if ( my $weight = $arc->weight )
#            {
#                $out .= $weight. " ";
#                $list_weight = 1;
#            }
#            elsif ( $weight = $arc->value_node->prop('weight',undef,'auto') )
#            {
#                $out .= $weight->desig . " ";
#                $list_weight = 1;
#            }
#            elsif ( $list_weight )
#            {
#                $out .= "0 ";
#            }
#
#            if ( $Para::Frame::U->has_root_access and ( (@{$arcversions->{$arc_id}} > 1) or
#                                                        $arcversions->{$arc_id}[0]->submitted ) )
#            {
#                debug "  multiple";
#
#                $out .=
#                  (
#                   "<table class=\"wide suggestion nopad\">".
#                   "<tr><th colspan=\"2\">".
#                   aloc("Choose one").
#                   "</th></tr>"
#                  );
#
#                foreach my $version (@{$arcversions->{$arc_id}})
#                {
#                    # TODO: Handle mixxed infered / noninfered arcs
#                    debug "  version $version";
#                    $out .=
#                      (
#                       "<tr><td>".
#                       &hidden("version_${arc_id}", $version->id).
#                       &radio("arc_${arc_id}__select_version",
#                              $version->id,
#                              0,
#                              {
#                               id => $version->id,
#                              }).
#                       "</td>"
#                      );
#
#                    $out .= "<td style=\"border-bottom: 1px solid black\">";
#
#                    if ( $version->is_removal )
#                    {
#                        $out .= "<span style=\"font-weight: bold\">REMOVAL</span>";
#                    }
#                    else
#                    {
#                        $out .= &{$inputtype}("undef",
#                                              $version->value->plain,
#                                              {
#                                               disabled => "disabled",
#                                               tag_attr =>
#                                               {
#                                                class => "suggestion_field",
#                                                size => $size,
#                                                rows => $rows,
#                                                maxlength => $args->{'maxlength'},
#                                                id => $args->{'id'},
#                                                onchange => $onchange,
#                                               },
#                                               version => $version,
#                                               image_url => $args->{'image_url'},
#                                              });
#                    }
#
#                    $out .= $version->edit_link_html;
#                    $out .= "</td></tr>";
#                }
#
#                $out .=
#                  (
#                   "<tr><td>".
#                   &radio("arc_${arc_id}__select_version",
#                          'deactivate',
#                          0,
#                          {
#                           id => "arc_${arc_id}__activate_version--undef",
#                          }).
#                   "</td><td>".
#                   "<label for=\"arc_${arc_id}__activate_version--undef\">".
#                   Para::Frame::L10N::loc("Deactivate group").
#                   "</label>".
#                   "</td></tr>".
#                   "</table><br/>"
#                  );
#            }
#            else                ### LIST OF ACTIVE VALUES
#            {
#                my $field = build_field_key({arc => $arc});
#                $args->{id} = $field;
#
#                my $tag_attr = $args->{tag_attr} || {};
#                $tag_attr->{class}= $args->{'class'};
#                $tag_attr->{size} = $size;
#                $tag_attr->{rows} = $rows;
#                $tag_attr->{maxlength} = $args->{'maxlength'};
#                $tag_attr->{onchange} = $onchange;
#
#                my $fargs =
#                {
#                 image_url => $args->{'image_url'},
#                 arc => $arc->id,
#                 tag_attr => $tag_attr,
#                };
#                if ( $arc->indirect )
#                {
#                    $tag_attr->{'disabled'} = 'disabled';
#                    $field = '-'.$field; # Don't read content
#                }
#
#
##		debug "Creating an input with value ".$arc->value->plain;
#
#                $out .= &{$inputtype}($field, $arc->value->plain, $fargs);
#                unless( $arc->indirect )
#                {
#                    $out .= $arc->edit_link_html;
#                }
#
#                $out .= '<br/>'
#                  if ( scalar(keys %$arcversions) > 1 or $multi );
#            }
#
#        }
	}
	else
	{
#        debug "empty";
		$out .= "<table class=\"wuirc text_input$wide_class\">\n";

		$no_arc = 1;
		debug 2, "No arc?";
	}

	if ( $no_arc or $multi and not $disabled )
	{
#        debug "Drawing inputfield for new value";

		my $default = is_undef;

		my $props =
		{
		 ($rev?'rev':'').pred => $predname,
		 subj => $node,
		};

		my $dc = $args->{'default_create'} || {};
		my $vnode;
		if ( keys %$dc )
		{
			my $def_value = $args->{'default_value'};
			if ( UNIVERSAL::can($def_value, 'plain') )
			{
				$def_value = $def_value->plain;
			}
			$default = $class->new($def_value, $range);

			$vnode = $default->node || $args->{'vnode'};
			if (  not $vnode )
			{
				$vnode = $default->node_set;
				$props->{'vnode'} = $vnode;
				$args->{'id'} = build_field_key({
																				 ($rev?'rev':'').pred => $predname,
																				 subj => $node,
																				 vnode => $vnode,
																				});
			}
		}

#	debug 1, "Default value is ".$default->sysdesig; ### DEBUG

		my $row = "<tr>";
		foreach my $col ( @{$args->{'columns'}} )
		{
			my( $meta ) = $col =~ /^-\.?(.*)/;
			if ( $meta )
			{
				$row .= "<td class='col_$meta col_new'>";
			}
			else
			{
				$meta = '';
				$row .= "<td>";
			}

			given( $meta )
			{
				when( 'input' )
				{
					$row .= &{$inputtype}
						(build_field_key($props),
						 $default->plain,
						 {
							tag_attr =>
							{
							 class => $args->{'class'},
							 size => $size,
							 rows => $rows,
							 maxlength => $args->{'maxlength'},
							 id => $args->{'id'},
							 onchange => $onchange,
							},
							id => $args->{'id'},
							maxw => $maxw,
							maxh => $maxh,
							image_url => $args->{'image_url'},
						 });
				}

				when($col =~ /^-\./)		# Method for both class and node
				{
					$row .= $class->$meta() // '';
				}

				when(/^string_/)
				{
#                    debug "Adding $meta = ".$args->{$meta};
					$row .= $args->{$meta};
				}
			}


			$row .= "</td>";
		}

			### OLDER CODE:
			#
			foreach my $key ( keys %$dc )
			{
				my $pred = RDF::Base::Pred->get($key);
				#	    debug "  default cerate: $key";
				my $vallist = $R->find_by_anything($dc->{$key},
																					 {
																						valtype=>$pred->valtype});
				#debug "    looking up ".$dc->{$key};
				foreach my $val ( $vallist->as_array )
				{
					#debug "    $val";
					if ( UNIVERSAL::isa( $val, "RDF::Base::Resource" ) )
					{
						my $field = build_field_key({
																				 ($rev?'rev':'').pred => $pred,
																				 subj => $vnode,
																				 if => $src,
																				 parse => 'id',
																				});
						$extra_html .= &hidden($field,$val->id);
					}
					else
					{
						my $field = build_field_key({
																				 ($rev?'rev':'').pred => $pred,
																				 subj => $vnode,
																				 if => $src,
																				});
						$extra_html .= &hidden($field,$val->plain);
					}
				}
			}
			#
			### /older code


		# Remove empty elements at the end of row
		$row =~ s/(<td[^>]*><\/td>)+$//;

		$out .= $row . "</tr>";

	}

	$out .= "</table>\n";
	$out .= $extra_html;


#    debug 2, "returning: $out" ;
	return $out;
}


##############################################################################

=head2 wul

Display field for updating a string property of a node

var node must be defined

the query param "arc___pred_$pred__subj_$nid" can be used for default new value

the query param "arc___pred_$pred" can be used for default new value

=cut

sub wul
{
	die "FIXME";
}


##############################################################################

=head3 action_icon

=cut

sub action_icon
{
#    confess "who called me";
	return "";										# Maby called for undef value
}


##############################################################################

=head3 as_html

=cut

sub as_html
{
	my $vt = $_[0]->this_valtype;

	return $_[0] if $vt->equals($C_text_html );
	return $_[0] if $vt->has_value({scof=>$C_text_html});
	return shift->SUPER::as_html(@_);
}


##############################################################################

=head3 default_valtype

=cut

sub default_valtype
{
	return RDF::Base::Literal::Class->get_by_label('valtext');
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
