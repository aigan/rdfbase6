#  $Id$  -*-cperl-*-
package Rit::Base::Literal::String;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Literal::String

=cut

use strict;
use utf8;

use Carp qw( cluck confess longmess );
use Digest::MD5 qw( md5_base64 ); #);
use Scalar::Util qw( looks_like_number refaddr );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump trim throw deunicode );
use Para::Frame::Widget qw( input textarea hidden radio label_from_params input_image );

use Rit::Base::Utils qw( is_undef valclean truncstring query_desig parse_propargs );
use Rit::Base::Widget qw( aloc build_field_key );
use Rit::Base::Constants qw( );

use base qw( Rit::Base::Literal );


use overload
  'cmp'  => 'cmp_string',
  '<=>'  => 'cmp_numeric',
  '0+'   => sub{+($_[0]->literal)},
  '+'    => sub{$_[0]->literal + $_[1]},
  fallback => 1,
  ;

=head1 DESCRIPTION

Represents a String L<Rit::Base::Literal>.

=cut


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

#######################################################################

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

    my $val; # The actual string
    if( ref $in_value )
    {
	if( ref $in_value eq 'SCALAR' )
	{
	    $val = $$in_value;
	}
	else
	{
	    confess "Invalid value: $in_value";
	}
    }
    else
    {
	$val = $in_value;
    }

    if( utf8::is_utf8($val) )
    {
	if( utf8::valid($val) )
	{
	    if( $val =~ /Ã./ )
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
	if( $val =~ /Ã./ )
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


#######################################################################

=head3 new_from_db

=cut

sub new_from_db
{
    my( $class, $val, $valtype ) = @_;

    if( defined $val )
    {
	if( $val =~ /Ã./ )
	{
	    debug "UNDECODED UTF8 in DB: $val)";
	    unless( utf8::decode( $val ) )
	    {
		debug 0, "Failed to convert to UTF8!";
#		$Para::Frame::REQ->result->message("Failed to convert to UTF8!");
	    }
	}
	else
	{
	    utf8::upgrade( $val );
	}
    }

    return bless
    {
     'arc' => undef,
     'value' => $val,
     'valtype' => $valtype,
    }, $class;
}


#######################################################################

=head3 parse

  $class->parse( \$value, \%args )

For parsing any type of input. Expecially as given by html forms.

Parsing an existing literal object may MODIFY it''s content and valtype


Supported args are:
  valtype
  coltype
  arclim

Will use L<Rit::Base::Resource/get_by_anything> for lists and queries.

The valtype may be given for cases there the class handles several
valtypes.

=cut

sub parse
{
    my( $class, $val_in, $args_in ) = @_;
    my( $val, $coltype, $valtype, $args ) =
      $class->extract_string($val_in, $args_in);

    if( $coltype eq 'obj' )
    {
	confess "FIXME";
	$coltype = $valtype->coltype;
	debug "Parsing as $coltype: ".query_desig($val_in);
    }

    my $val_mod;
    if( ref $val eq 'SCALAR' )
    {
	$val_mod = $$val;
    }
    elsif( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
    {
	$val_mod = $val->plain;
    }
    else
    {
	confess "Can't parse $val";
    }

    if( defined $val_mod )
    {
	# Remove invisible characters, other than LF
	$val_mod =~ s/(?!\n)\p{Other}//g;
    }

    if( $coltype eq 'valtext' )
    {
	unless( length($val_mod||'') )
	{
	    return $class->new( undef, $valtype );
	}

	# Cleaning up UTF8...
	if( $val_mod =~ /Ã./ )
	{
	    my $res;
	    while( length $val_mod )
	    {
		$res .= decode("UTF-8", $val_mod, Encode::FB_QUIET);
		$res .= substr($val_mod, 0, 1, "") if length $val_mod;
	    }
	    $val_mod = $res;
	}

	# Repair chars in CP 1252 text,
	# incorrectly imported as ISO 8859-1.
	# For example x96 (SPA) and x97 (EPA)
	# are only used by text termianls.
	$val_mod =~ s/\x{0080}/\x{20AC}/g; # Euro sign
	$val_mod =~ s/\x{0085}/\x{2026}/g; # Horizontal ellipses
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
	$val_mod =~ s/^\s*\n//; # Leading empty lines
	$val_mod =~ s/\n\s+$/\n/; # Trailing empty lines

    }
    elsif( $coltype eq 'valfloat' )
    {
	if( $val_mod )
	{
	    trim($val_mod);
	    $val_mod =~ s/,/./; # Handling swedish numerical format...

	    unless( looks_like_number( $val_mod ) )
	    {
		throw 'validation', "String $val_mod is not a number";
	    }
	}
    }
    else
    {
	confess "coltype $coltype not handled by this class";
    }

    # Always return the incoming object. This may MODIFY the object
    #
    if( UNIVERSAL::isa $val, "Rit::Base::Literal::String" )
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

#######################################################################

=head2 desig

  $n->desig()

The designation of the literal

=cut

sub desig  # The designation of obj, meant for human admins
{
    my( $val ) = @_;

    #if( $val->arc('value')->realy_objtype )
    #{
    #	return $val->{'value'}->desig;
    #}
    #else
    {
	return $val->{'value'};
    }
}


#######################################################################

=head3 syskey

Returns a unique predictable id representing this object

=cut

sub syskey
{
    if( defined $_[0]->{'value'} )
    {
	if( utf8::is_utf8( $_[0]->{'value'} ) )
	{
	    my $encoded = $_[0]->{'value'};
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


#######################################################################

=head2 literal

  $n->literal()

The literal value that this object represents.

=cut

sub literal
{
#    warn "\t\t\t${$_[0]}\n";
    return $_[0]->{'value'};
}


#######################################################################

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

    if( ref $val2 )
    {
	if( $val2->defined )
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

    if( $_[2] )
    {
	return $val2 cmp $val1;
    }
    else
    {
	return $val1 cmp $val2;
    }
}


#######################################################################

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

    if( ref $val2 )
    {
	if( $val2->defined )
	{
	    $val2 = $val2->desig;
	}
	else
	{
	    $val2 = 0;
	}
    }

    if( $_[2] )
    {
	return( $val2 <=> $val1 );
    }
    else
    {
	return( $val1 <=> $val2 );
    }
}


#######################################################################

=head3 loc

  $lit->loc

  $lit->loc(@args)

Uses the args in L<Para::Frame::L10N/compile>.

Returns: the value as a plain string

=cut

sub loc
{
    my $lit = shift;

    unless( defined $lit->{'value'} )
    {
	return "";
    }

    if( @_ )
    {
	my $str = $lit->{'value'};
	my $lh = $Para::Frame::REQ->language;
	my $mt = $lit->{'maketext'} ||= $lh->_compile($str);
	return $lh->compute($mt, \$str, @_);
    }
    else
    {
	my $str = $lit->{'value'};
	if( utf8::is_utf8( $str ) )
	{
	    # Good...
#	    my $len1 = length($str);
#	    my $len2 = bytes::length($str);
#	    debug sprintf "Returning %s(%d/%d):\n", $str, $len1, $len2;
	}
	else
	{
	    debug "String '$str' not marked as UTF8; upgrading";
	    utf8::upgrade($str);
	}
	return $str;
    }
}


#######################################################################

=head3 value

aka literal

=cut

sub value
{
    warn "About to confess...\n";
    confess "wrong turn";
    return $_[0]->{'value'};
}


#######################################################################

=head3 plain

Make it a plain value.  Safer than using ->literal, since it also
works for Undef objects.

=cut

sub plain
{
    return $_[0]->{'value'};
}


#######################################################################

=head3 clean

Returns the clean version of the value as a Literal obj

=cut

sub clean
{
    return $_[0]->new( valclean( $_[0]->plain ) );
}


#######################################################################

=head3 clean_plain

Returns the clean version of the value as a plain string

=cut

sub clean_plain
{
    return valclean( $_[0]->plain );
}


#######################################################################

=head3 begins

  $string->begins( $substr )

Returns true if the string begins with $substr.

=cut

sub begins
{
    unless( defined $_[0]->{'value'} )
    {
	return 0;
    }

    return $_[0]->{'value'} =~ /^$_[1]/;
}

#######################################################################

=head3 this_valtype

=cut

sub this_valtype
{
    if( ref $_[0] )
    {
	if( my $valtype = $_[0]->{'valtype'} )
	{
	    return $valtype;
	}

	if( looks_like_number($_[0]->{'value'}) )
	{
	    return Rit::Base::Literal::Class->get_by_label('valfloat');
	}
    }

    return Rit::Base::Literal::Class->get_by_label('valtext');
}

#######################################################################

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



document newsubj!

the query param "arc___pred_$pred__subj_$nid" can be used for default new value

the query param "arc___pred_$pred" can be used for default new value

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

#    Para::Frame::Logging->this_level(5);

    no strict 'refs'; # For &{$inputtype} below
    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;
    my $root_access = $req->user->has_root_access; # BOOL

    unless( $req->user->has_root_access )
    { ### FIXME: Not ready to use for non-admins...
	$args =
	  parse_propargs({
			  %$args,
			  unique_arcs_prio => ['submitted','active'],
			  arclim => [['submitted','created_by_me'],'active'],
			 });
    }

    my $range = $args->{'range'} || $args->{'range_scof'}
      || $class->this_valtype;
    my $tb = $R->get({name=>'textbox', scof=>'text'});
    if( ($args->{'rows'}||0) > 1 or
	$range->equals($tb) or
	$range->scof($tb) )
    {
	$args->{'cols'} ||= 57;
	$args->{'size'} = $args->{'cols'};
	$args->{'inputtype'} = 'textarea';
	$args->{'rows'} ||= 3;
    }
    $args->{'maxlength'} ||= 2800;


    my $size = $args->{'size'} || 30;
    my $smallestsize = $size - 10;
    if( $smallestsize < 3 )
    {
	$smallestsize = 3;
    }

    my $inputtype = $args->{'inputtype'} || 'input';

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;

	debug 2, "String wuirc for $predname";
	debug 2, "$predname class is ". $pred->range->instance_class;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = Rit::Base::Pred->get_by_label($predname);
    }


    debug 2, "wub $inputtype $predname for ".$subj->sysdesig;

    my $newsubj = $args->{'newsubj'};
    my $rows = $args->{'rows'};
    my $maxw = $args->{'maxw'};
    my $maxh = $args->{'maxh'};

    $args->{'id'} ||= build_field_key({
				       pred => $predname,
				       subj => $subj,
				      });

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    my $proplim = $args->{'proplim'} || undef;
    my $arclim = $args->{'arclim'} || ['active','submitted'];


    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($predname, $proplim, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
    }
    elsif( $subj->list($predname,$proplim,$arclim)->is_true )
    {
	my $subj_id = $subj->id;

	my $arcversions =  $subj->arcversions($predname);
	if( scalar(keys %$arcversions) > 1 )
	{
	    $out .= '<ul style="list-style-type: none" class="nopad">';
	}

	foreach my $arc_id (keys %$arcversions)
	{
	    my $arc = Rit::Base::Arc->get($arc_id);
	    if( my $lang = $arc->value_node->is_of_language(undef,'auto') )
	    {
		$out .= "(".$lang->desig."): ";
	    }

	    if( (@{$arcversions->{$arc_id}} > 1) or
		$arcversions->{$arc_id}[0]->submitted )
	    {
		debug "  multiple";

		$out .=
		  (
		   "<li><table class=\"wide suggestion nopad\">".
		   "<tr><th colspan=\"2\">".
		   aloc("Choose one").
		   "</th></tr>"
		  );

		foreach my $version (@{$arcversions->{$arc_id}})
		{
		    debug "  version $version";
		    $out .=
		      (
		       "<tr><td>".
		       &hidden("version_${arc_id}", $version->id).
		       &radio("arc_${arc_id}__select_version",
			      $version->id,
			      0,
			      {
			       id => $version->id,
			      }).
		       "</td>"
		      );

		    $out .= "<td style=\"border-bottom: 1px solid black\">";

		    if( $version->is_removal )
		    {
			$out .= "<span style=\"font-weight: bold\">REMOVAL</span>";
		    }
		    else
		    {
			$out .= &{$inputtype}("undef",
					      $version->value,
					      {
					       disabled => "disabled",
					       class => "suggestion_field",
					       size => $smallestsize,
					       rows => $rows,
					       maxlength => $args->{'maxlength'},
					       version => $version,
					       image_url => $args->{'image_url'},
					       id => $args->{'id'},
					      });
		    }

		    $out .= $version->edit_link_html;
		    $out .= "</td></tr>";
		}

		$out .=
		  (
		   "<tr><td>".
		   &radio("arc_${arc_id}__select_version",
			  'deactivate',
			  0,
			  {
			   id => "arc_${arc_id}__activate_version--undef",
			  }).
		   "</td><td>".
		   "<label for=\"arc_${arc_id}__activate_version--undef\">".
		   Para::Frame::L10N::loc("Deactivate group").
		   "</label>".
		   "</td></tr>".
		   "</table></li>"
		  );
	    }
	    else
	    {
		$out .= '<li>'
		  if( scalar(keys %$arcversions) > 1 );

		my $field = build_field_key({
					     arc => $arc_id,
					     pred => $arc->pred,
					     subj => $arc->subj,
					    });
		$out .= &{$inputtype}($field,
				      $arc->value,
				      {
				       class => $args->{'class'},
#				       arc => $arc_id,
				       size => $size,
				       rows => $rows,
				       maxlength => $args->{'maxlength'},
				       id => $args->{'id'},
				       image_url => $args->{'image_url'}
				      });

		$out .= $arc->edit_link_html;

		$out .= '</li>'
		  if( scalar(keys %$arcversions) > 1 );
	    }
	}

	$out .= '</ul>'
	  if( scalar(keys %$arcversions) > 1 );
    }
    else # no arc
    {
	my $default = $class->new($args->{'default_value'}, $range);

	my $props =
	{
	 pred => $predname,
	 subj => $subj,
	};

	my $dc = $args->{'default_create'} || {};
	my $vnode = $default->node || $args->{'vnode'};
	if( keys %$dc and not $vnode )
	{
	    $vnode = $default->node_set;
	    $props->{'vnode'} = $vnode;
	}

	$out .= &{$inputtype}(build_field_key($props),
			      $default,
			      {
			       class => $args->{'class'},
			       size => $size,
			       rows => $rows,
			       maxlength => $args->{'maxlength'},
			       maxw => $maxw,
			       maxh => $maxh,
			       id => $args->{'id'},
			       image_url => $args->{'image_url'},
			      });

	foreach my $key ( keys %$dc )
	{
	    my $vallist = $R->find_by_anything($dc->{$key});
	    foreach my $val ( $vallist->as_array )
	    {
		if( UNIVERSAL::isa( $val, "Rit::Base::Resource" ) )
		{
		    my $field = build_field_key({
						 pred => $key,
						 subj => $vnode,
						 if => 'subj',
						 parse => 'id',
						});
		    $out .= &hidden($field,$val->id);
		}
		else
		{
		    my $field = build_field_key({
						 pred => $key,
						 subj => $vnode,
						 if => 'subj',
						});
		    $out .= &hidden($field,$val->plain);
		}
	    }
	}
    }

    return $out;
}


#######################################################################

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


#######################################################################

#sub wdirc
#{
#    my( $class, $subj, $pred, $args_in ) = @_;
#    my( $args ) = parse_propargs($args_in);
#
#    my $out = "";
#
#    my $predname;
#    if( ref $pred )
#    {
#	$predname = $pred->label;
#
#	debug 2, "String wuirc for $predname";
#	debug 2, "$predname class is ". $pred->range->instance_class;
#    }
#    else
#    {
#	$predname = $pred;
#	# Only handles pred nodes
#	$pred = Rit::Base::Pred->get_by_label($predname);
#    }
#
#    $out .= label_from_params({
#			       label       => $args->{'label'},
#			       tdlabel     => $args->{'tdlabel'},
#			       separator   => $args->{'separator'},
#			       id          => $args->{'id'},
#			       label_class => $args->{'label_class'},
#			      });
#
#    my $arclist = $subj->arc_list($predname, undef, $args);
#
#    while( my $arc = $arclist->get_next_nos )
#    {
#	$out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
#    }
#
#    return $out;
#}


#######################################################################

=head3 default_valtype

=cut

sub default_valtype
{
    return Rit::Base::Literal::Class->get_by_label('valtext');
}

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
