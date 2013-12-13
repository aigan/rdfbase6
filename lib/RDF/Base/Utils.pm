package RDF::Base::Utils;
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

RDF::Base::Utils - Utility functions for RDFBase

=cut

use 5.010;
use strict;
use warnings;
use utf8; # This module has utf8 chars!

use Carp qw( cluck confess carp croak );
use UNIVERSAL;

use base qw( Exporter );
our @EXPORT_OK
  = qw( cache_clear valclean format_phone format_zip parse_query_props
	parse_form_field_prop parse_arc_add_box is_undef arc_lock
	arc_unlock truncstring string html parse_query_pred
	parse_query_value parse_query_prop
	convert_query_prop_for_creation name2url query_desig
	send_cache_update parse_propargs aais alphanum_to_id
	proplim_to_arclim range_pred );


use Para::Frame::Utils qw( throw trim chmod_file debug datadump deunicode validate_utf8 );
use Para::Frame::Reload;

### Those modules loaded by RDF::Base later...
#use RDF::Base::Undef;
#use RDF::Base::Arc;
#use RDF::Base::Literal::String;
#


=head1 FUNCTIONS

Exportable.

TODO: Move most if not all of these functions to another place...

Please think about _not_ using these...

=cut


##############################################################################

=head2 cache_clear

  cache_clear()

  cache_clear( $time )

Sats the time of the cache clearing to $time that defaults to now().

Clears caches with nodes.

TODO: Broken. FIXME

Returns:

=cut

sub cache_clear
{
    my( $time ) = @_;

    debug "<<< Expunge cache\n";

    $RDF::Base::Cache::Created = $time || time;

    %RDF::Base::Cache::Resource = ();
    %RDF::Base::Cache::find_simple = ();

    # TODO: Clear %RDF::Guides::Organization::STATS_CHANGE

    RDF::Base::Arc->clear_queue;
}


##############################################################################

=head2 valclean

  valclean( $value )

Exceptions:
  Will die if encountered a "Malformed UTF-8 character (fatal)"

Returns: The new value after a lot of transformation

    $value = lc($value);
    $value =~ s/(aa)/å/g;
    $value =~ s/(æ|ae)/ä/g;
    $value =~ s/(ø|oe)/ö/g;
    $value =~ tr[àáâäãåéèêëíìïîóòöôõúùüûýÿðþß]
                [aaaaaaeeeeiiiiooooouuuuyydps];
    $value =~ tr/`'/'/;
    $value =~ tr/qwz/kvs/;
    $value =~ s/\b(och|and|o|o\.|og)\b/&/g;
    $value =~ s/\s\'n\b/&/g;
    $value =~ s/hote(ls|ller|lli|llin|llit|ll|l)/hotel/g;

    $value =~ s/[^\w&]//g;

=cut

sub valclean
{
    my( $origvalue ) = @_;
    my $value = $origvalue;

    my $DEBUG = 0;

    $value = $$origvalue if ref $origvalue eq 'SCALAR';

    # Make sure that $value is an object and not a class name
    if( ref($value) and UNIVERSAL::can $value, 'plain' )
    {
	$value = $value->plain;
    }

    return undef unless defined $value;

    debug "  Normalizing $value to\n" if $DEBUG;

    # Don't change valclean algoritm wihout recleaning the whole DB!
    use locale;
    use POSIX qw(locale_h);
    my $oldlocale = setlocale(LC_ALL);
    setlocale(LC_ALL, "sv_SE");

    $value = lc($value);
    $value =~ s/(aa)/å/g;
    $value =~ s/(æ|ae)/ä/g;
    $value =~ s/(ø|oe)/ö/g;
#    $value =~ s/_/ /g;  ############### FIXME
    $value =~ tr[àáâäãåéèêëíìïîóòöôõúùüûýÿðþß]
                [aaaaaaeeeeiiiiooooouuuuyydps];
    $value =~ tr/`'/'/;
    $value =~ tr/qwz/kvs/;
    $value =~ s/\b(och|and|o|o\.|og)\b/&/g;
    $value =~ s/\s\'n\b/&/g;
    $value =~ s/hote(ls|ller|lli|llin|llit|ll|l)/hotel/g;

    $value =~ s/[^\w&]//g;

    debug "    $value\n" if $DEBUG;

    $$origvalue = $value if ref $origvalue eq 'SCALAR';

    setlocale(LC_ALL, $oldlocale);
    return $value
}


##############################################################################

=head2 name2url

  name2url( $name )

Converts a name to a reasonable string to use in an url

=cut

sub name2url
{
    my( $name ) = deunicode( @_ );
    utf8::upgrade($name); # As utf8 but only with Latin1 chars

    use locale;
    use POSIX qw(locale_h);
    my $oldlocale = setlocale(LC_ALL);
    setlocale(LC_ALL, "sv_SE");
    my $url = lc($name);

    $url =~ tr[àáâäãåæéèêëíìïîóòöôõøúùüûýÿðþß]
	      [aaaaaaaeeeeiiiioooooouuuuyydps];
    $url =~ s/[^\w\s\-~]//g;
    $url =~ s/\s+/_/g;
    $url =~ s/( ^_+ | _+$ )//gx;

    setlocale(LC_ALL, $oldlocale);

    return $url;
}


##############################################################################

=head2 format_phone

Deprecated

=cut

sub format_phone
{
    my( $text ) = @_;
    $text =~ s/(^\s+|\s+$)//g;
    $text =~ s/^0//;
    $text =~ s/^\+\d+\D+//;
    return $text;
}


##############################################################################

=head2 format_zip

Deprecated

=cut

sub format_zip
{
    my( $text ) = @_;
    $text =~ s/(^\s+|\s+$)//g;
    return $text;
}


##############################################################################

=head2 parse_query_props

  parse_query_props( $string )

Splits the string to a list of values if separated by C<LF>.

The first part of each element should be a predicate and the rest,
after the first space, should be the value.

Returns:

a props hash with pred/value pairs.

NB! Previously also split on C<,>.

Example:

  name Jonas Liljegren
  age 33

  becomes:

  {
    name => 'Jonas Liljegren',
    age  => '33',
  }


TODO: Handle things like: val (p1 val1, p2 val2 (ps1 vals1, ps2,
vals2), p3 val3)

=cut


sub parse_query_props
{
    my( $prop_text ) = @_;

#    warn "Parsing props '$prop_text'\n";
    my $props = {};

    trim(\$prop_text);
    foreach my $pair ( split /\s*\r?\n\s*/, $prop_text )
    {
	my($prop_name, $value) = split(/\s+/, $pair, 2);
	trim(\$prop_name);
	$props->{$prop_name} = parse_query_value($value);
    }
    return $props;
}


##############################################################################

=head2 parse_query_value

used by parse_query_props

=cut


sub parse_query_value
{
    my( $val_in ) = @_;

    my $val = $val_in;
    my $arclim;
    if( $val_in =~ /^\s*(?:\{\s*(.+?)\s*\})?\s*(?:\[(.+?)\])?\s*$/ )
    {
#        debug "Creating subcriterion from $val_in";
        my $pairs = $1;
        my $alim_in = $2;
        my %sub;

#        debug "query proplims $pairs" if $pairs;
#        debug "query arclims $alim_in" if $alim_in;

        if( $pairs )
        {
            foreach my $part ( split /\s*,\s*/, $pairs )
            {
#            debug "  Processing $part";
                my( $skey, $svalue ) = split(/\s+/, $part, 2);
#            debug "  $skey = $svalue";
                $sub{ $skey } = parse_query_value($svalue);
            }
        }
        $val = \%sub;

        if( $alim_in )
        {
#            debug "Parsing alim $alim_in";
            $arclim = RDF::Base::Arc::Lim->parse_string("[$alim_in]");
        }

#        debug "Got ".query_desig($val);
    }
#    elsif( length $val )
#    {
#        confess "Failed to parse query value $val";
#    }


    if( wantarray )
    {
        return( $val, $arclim );
    }
    elsif( $arclim and keys %$val )
    {
        throw("Both subquery and arclim: $val_in");
    }
    elsif( $arclim )
    {
        return $arclim;
    }
    else
    {
        return $val;
    }
}


##############################################################################

=head2 parse_form_field_prop

  parse_form_field_prop( $string )

Splits the string into an arg list.

The format is name1_val1__name2_val2__name3_val3...

Vals can be empty: name1___name2_val2...

Vals can contain underscore: pred_in_region...

The string can begin with C<check_>.

If a second property with the same name is encountered, it will return
the values as an arrayref.

Returns:

a props hash with pred/value pairs.

Example:

  arc___revpred_has_member__type_marketing_group__if_a__if_b

  becomes:

  {
    arc     => undef,
    revpred => 'has_member',
    type    => 'marketing_group',
    if      => ['a','b'],
  }

=cut

sub parse_form_field_prop
{
    my( $string ) = @_;

    $string =~ s/^check_//;

    my %arg;
    foreach my $part ( split /___?/, $string )
    {
	my( $key, $val ) = $part =~ /^([^_]+)_?(.*)/
	    or die "Malformed part: $part\n";

	if( exists $arg{$key} )
	{
	    if( (defined $arg{$key}) and (ref $arg{$key} eq 'ARRAY') )
	    {
		push @{$arg{$key}}, $val;
	    }
	    else
	    {
		$arg{$key} = [ $arg{$key}, $val ];
	    }
	}
	else
	{
	    $arg{$key} = $val;
	}
    }
    return \%arg;
}


##############################################################################

=head2 parse_arc_add_box

  parse_arc_add_box( $string, \%args )

Splits the string up with one property for each row.

The first part of each element should be a predicate and the rest,
after the first space, should be the value.

Value nodes can be created by giving adding the value props after an
C<-E<gt>>. Those props are parsed using L</parse_query_props>.

Returns:

a props hash with pred/value pairs.

Example:

  name Sverige -> is_of_language sv (code)
  is country

This would create a node with the properties

  $sverige =
  {
    is_of_language => 'sv (code)',
  }

And then return the hashref

  {
    name => $sverige,
    is   => 'country',
  }

Note that the value node is created even if you don't use the returned
hashref for creating the arcs using that value node.

The C<sv (code)> part will be parsed by
L<RDF::Base::Resource/find_by_anything>, as will all the values.

=cut

sub parse_arc_add_box
{
    my( $query, $args ) = @_;

    $args ||= {};
    $query ||= '';

    my $DEBUG = 0;
    my $props = {};

    foreach my $row ( split /\r?\n/, $query )
    {
	trim( \$row );
	next unless length $row;

	debug "Row: $row\n" if $DEBUG;

	my( $pred_name, $value ) = split(/\s+/, $row, 2);

	## Support adding value nodes "$name -> $props"
	if( $value =~ /^\s*(.*?)\s*->\s*(.*)$/ )
	{
	    my $sprops = parse_query_props( $2, $args );
	    my $pred = RDF::Base::Pred->get_by_anything( $pred_name, $args );
	    my $value = $pred->valtype->instance_class->parse($1, $args);
	    $value->add($sprops, $args);
	}

	unless( ref $value )
	{
	    my $valtype = RDF::Base::Pred->get($pred_name)->valtype;
	    $value = RDF::Base::Resource->
	      get_by_anything( $value,
			       {
				%$args,
				valtype => $valtype,
			       });
	}

	debug "  $pred_name: ".$value->sysdesig."\n" if $DEBUG;
	push @{ $props->{$pred_name} }, $value;
    }

    return $props;
}


##############################################################################

=head2 parse_query_pred

  parse_query_pred( $predstring, \%args )

Internal use...

=cut

sub parse_query_pred
{
    my( $val, $args ) = @_;

    $args ||= {};

    my $private = $args->{'private'} || 0;
    my $subj = $args->{'subj'};

    if( $val =~ m/^(rev_)?(.*?)(?:_(direct|indirect|explicit|implicit))?(?:_(clean))?(?:_(eq|like|begins|gt|lt|ne|exist)(?:_(\d+))?)?$/x )
    {
	my $rev    = $1;
	my $pred   = $2;
	my $type;
	my $arclim = $3;
	my $clean  = $4 || $args->{'clean'} || 0;
	my $match  = $5 || 'eq';
	my $prio   = $6; #Low prio first (default later)
	my $find   = undef;

	if( $pred =~ m/^(subj|pred|obj|coltype|label)$/ )
	{
	    # Special case !!!!!!!

	    # TODO: Resolce conflict between pred obj and other
	    # resource obj

	    $type = 2;  # valfloat
	}
	elsif( $pred =~ s/^predor_// )
	{
	    my( @prednames ) = split /_-_/, $pred;
	    my( @preds ) = map RDF::Base::Pred->get($_), @prednames;
	    $pred = \@preds;

	    # Assume no type mismatch between alternative preds
	    $type = $preds[0]->coltype;
	}
	else
	{
	    if( $pred =~ /^count_pred_(.*)/ )
	    {
		$find = 'count_pred';
		$pred = $1;
	    }

#	    debug "pred is $pred";
	    $pred = RDF::Base::Pred->get( $pred );
#	    debug "now pred is $pred";
	    $type = $pred->coltype;
	}

	if( $type eq 'valtext' )
	{
	    if( $clean )
	    {
		$type = 'valclean';
	    }
	}
	elsif( $type eq 'obj' )
	{
	    if( $rev )
	    {
		$type = 'subj';
	    }
	}

	return
	{
	 rev => $rev,
	 pred => $pred,
	 type => $type,
	 arclim => $arclim,
	 clean => $clean,
	 match => $match,
	 prio => $prio,
	 find => $find,
	 private => $private,
	};
    }
    return undef;
}

##############################################################################

=head2 parse_query_prop

  parse_query_prop( \%props, \%args )

Internal use...

=cut

sub parse_query_prop
{
    my( $props, $args ) = @_;

    my %res;
    foreach my $predpart ( keys %$props )
    {
	my $valref = $props->{$predpart};
	my @values;
	if( ref $valref eq 'ARRAY' )
	{
	    @values = @$valref;
	}
	elsif( ref $valref eq 'RDF::Base::List' )
	{
	    @values = $valref->nodes;
	}
	else
	{
	    @values = ($valref);
	}

	foreach( @values )
	{
	    if( ref $_ and UNIVERSAL::isa($_, 'RDF::Base::Resource') )
	    {
		# Getting node id
		$_ = $_->id;
	    }
	    elsif( ref $_ eq 'HASH' )
	    {
		if( $_->{'id'} )
		{
		    $_ = $_->{'id'};
		}
		else
		{
		    # Sub-request
		    $_ = RDF::Base::Resource->get_id( $_ );
		}
	    }
	}


	my $rec =  parse_query_pred( $predpart, $args );

	if( $values[0] eq '*' )
	{
	    $rec->{'match'} = 'exist';
	}
	elsif( $rec->{'type'} eq 'obj' )
	{
	    # The obj part can be specified in several ways
	    #
	    my @new;
	    foreach my $val ( @values )
	    {
		if( ref $val and UNIVERSAL::isa( $val, 'RDF::Base::Object' ) )
		{
		    unless( $val->defined )
		    {
			$val = undef;
		    }
		}

		if( defined $val and length $val )
		{
		    push @new, RDF::Base::Resource->get( $val )->id;
		}
		else
		{
		    push @new, undef;
		}
	    }
	    @values = @new;
	}

	if( $rec->{'match'} eq 'exist' )
	{
	    @values = ();
	}
	elsif( not @values )
	{
	    throw('incomplete', longmess("Values missing: ".datadump $rec->{'value'}));
	}

	$rec->{'values'} = \@values;

	$res{$predpart} = $rec;
    }

    return \%res;
}


##############################################################################

=head2 convert_query_prop_for_creation

  convert_query_prop_for_creation( \%props, \%args )

Accepts C<_clean> part.

Internal use...

=cut

sub convert_query_prop_for_creation
{
    my( $props_in, $args ) = @_;

    my $proprec = parse_query_prop( $props_in, $args );

    my %props;

    foreach my $predpart (keys %$proprec)
    {
	my $rec = $proprec->{$predpart};

	if( $rec->{'arclim'} )
	{
	    confess "arclim not valid here";
	}

	if( $rec->{'match'} ne 'eq' )
	{
	    confess "Only matchtype eq valid here";
	}

	my $pred_name;
	my $pred = $rec->{'pred'};

	unless( ref $pred ) ### SPECIAL CASE - TEMP SOLUTION
	{
	    if( $pred =~ /^(subj|pred|obj|value|coltype|label)$/ )
	    {
		$pred_name = $pred;
	    }
	    else
	    {
		confess "Invalid pred: $pred";
	    }
	}
	else
	{
	    unless( UNIVERSAL::isa($pred, 'RDF::Base::Pred') )
	    {
		confess "No predor valid here: ".datadump($pred);
	    }

	    if( $rec->{'rev'} )
	    {
		$pred_name = 'rev_' . $pred->plain;
	    }
	    else
	    {
		$pred_name = $pred->plain;
	    }
	}

	$props{$pred_name} = $rec->{'values'};
    }

    return \%props;
}


##############################################################################

=head2 is_undef

  is_undef()

Returns:

An L<RDF::Base::Undef> object.

=cut


sub is_undef ()
{
#    carp "got <UNDEF> value";
#    warn "\t\t\t<undef>\n";
    return RDF::Base::Undef->new();
}


##############################################################################

=head2 arc_lock

  arc_lock()

Calls L<RDF::Base::Arc/lock>

=cut

sub arc_lock
{
    RDF::Base::Arc->lock;
}


##############################################################################

=head2 arc_unlock

  arc_unlock()

Calls L<RDF::Base::Arc/unlock>

=cut

sub arc_unlock
{
    RDF::Base::Arc->unlock;
}


##############################################################################

=head2 truncstring

  truncstring( $string, $length )

The string may be a string ref or an L<RDF::Base::Object>. It doesnt
touch the string, but returns a string with a maximum of C<$length>
chars. If shortened, ends with '...'.

Returns:

The shortened string.

=cut

sub truncstring
{
    my( $str, $len ) = @_;

    $len ||= 35;

#    warn "1 str = $str\n";

    $str = $$str if ref $str eq 'REF';

    if( ref $str )
    {
	if( ref $str eq 'RDF::Base::List' )
	{
	    $str = $str->literal;
	}

	if( UNIVERSAL::can $str, "plain" )
	{
	    $str = $str->plain;
	}
	elsif( ref $str eq 'SCALAR' )
	{
	    if( length $$str > $len )
	    {
		return substr($$str, 0, ($len - 3)) . '...';
	    }
	    return $$str;
	}
	else
	{
	    #	warn "2 str = $str and of type ".ref($str)."\n";
	    confess "Wrong format of string: $str\n";
	}
    }

    if( length $str > $len )
    {
	return substr($str, 0, ($len - 3)) . '...';
    }
    return $str;
}

##############################################################################

=head2 string

  string($string)

Calls L<RDF::Base::Literal::String/new> with C<$string>.

=cut

sub string
{
    return RDF::Base::Literal::String->new(@_);
}


##############################################################################

=head2 html

  html($string)

Calls L<RDF::Base::Literal::String/new> with C<$string> and valtype
C<text_html>.

=cut

sub html
{
    state $text_html = RDF::Base::Constants->get('text_html');
    return RDF::Base::Literal::String->new(@_,$text_html);
}


##############################################################################

=head2 query_desig

  query_desig($query, \%args, $ident)

=cut

sub query_desig
{
    my $out = query_desig_block(@_);
    $out =~ s/^\s*\n*//;
    $out =~ s/\n\s*$//;
    return $out;
}

sub query_desig_block
{
    my( $query, $args, $ident ) = @_;

    my $DEBUG = 0;

    $ident ||= 0;
    $query //= '<undef>';
    unless( length $query ){ $query='<empty>' }
    my $out = "";
#    warn "query_desig on level $ident for ".datadump($query,1);

    if( ref $query )
    {
	if( UNIVERSAL::can($query, 'sysdesig') )
	{
	    warn "  sysdesig $query\n" if $DEBUG > 1;
	    my $val = $query->sysdesig( $args, $ident );
	    warn "  sysdesig gave '$val'\n" if $DEBUG > 1;
	    if( $val =~ /\n.*?\n/s )
	    {
		warn "g\n" if $DEBUG;
		$out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
	    }
	    else
	    {
		warn "h\n" if $DEBUG;
		$val =~ s/\n*$/\n/;
		$val =~ s/\s+/ /g;
		$val =~ s/^\s+//g;
		$out .= '  'x$ident . $val."\n";
	    }
	}
	elsif( UNIVERSAL::isa($query,'HASH') )
	{
	    foreach my $key ( keys %$query )
	    {
		warn "  hash elem $key\n" if $DEBUG > 1;
		my $val = query_desig_block($query->{$key}, $args, $ident+1);
		warn "  hash elem gave '$val'\n" if $DEBUG > 1;
		$val =~ s/^\n//;
		$val =~ s/\n$//;
		if( $val =~ /\n.*?\n/s )
		{
		    warn "a\n" if $DEBUG;
		    $out .= '  'x$ident . "$key:\n";
		    $out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
		    $out .= "\n";
		}
		else
		{
		    warn "b\n" if $DEBUG;
		    $val =~ s/\n*$/\n/;
		    $val =~ s/\s+/ /g;
		    $val =~ s/^\s+//g;
		    $out .= '  'x$ident . "$key: $val\n";
		}
	    }
	}
	elsif( UNIVERSAL::isa($query,'ARRAY') )
	{
	    foreach my $val ( @$query )
	    {
		warn "  array elem $val\n" if $DEBUG > 1;
		my $val = query_desig_block($val, $args, $ident+1);
		warn "  array elem gave '$val'\n" if $DEBUG > 1;
		$val =~ s/^\n//;
		$val =~ s/\n$//;
		if( $val =~ /\n.*?\n/s )
		{
		    warn "c\n" if $DEBUG;
		    $out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
		    $out .= "\n";
		}
		else
		{
		    warn "d\n" if $DEBUG;
		    $val =~ s/\n*$/\n/;
		    $val =~ s/\s+/ /g;
		    $val =~ s/^\s+//g;
		    $out .= '  'x$ident . $val."\n";
		}
	    }
	}
	elsif( UNIVERSAL::isa($query, 'SCALAR') )
	{
	    warn "  scalar $query\n" if $DEBUG > 1;
	    my $val = query_desig_block($$query, $args, $ident+1);
	    warn "  gave   '$val'\n" if $DEBUG > 1;
	    if( $val =~ /\n.*?\n/s )
	    {
		warn "e\n" if $DEBUG;
		$out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
	    }
	    else
	    {
		warn "f\n" if $DEBUG;
		$val =~ s/\n*$/\n/;
		$val =~ s/\s+/ /g;
		$val =~ s/^\s+//g;
		$out .= '  'x$ident . $val."\n";
	    }
	}
	else
	{
	    warn "i\n" if $DEBUG;
	    $out .= '  'x$ident . $query;
	}
    }
    else
    {
	warn "  plain '$query'\n" if $DEBUG > 1;
	if( $query =~ /\n.*?\n/s )
	{
	    warn "j\n" if $DEBUG;
	    $out .= join "\n", map '  'x$ident.$_, split /\n/, $query;
	}
	else
	{
	    warn "k\n" if $DEBUG;
	    $out =~ s/\n*$/\n/;
	    $query =~ s/\s+/ /g;
	    $query =~ s/^\s+//g;
	    $out .= '  'x$ident . $query."\n";
	}
    }

    warn "Returning:$out<-\n" if $DEBUG;
    return $out;
}


#########################################################################

=head2 parse_propargs

  parse_propargs()

  parse_propargs( \%args )

  parse_propargs( $special )

  parse_propargs( $arclim )


C<\%args> holds any extra arguments to the method as name/value
pairs. The C<arclim> argument is always parsed and converted to a
L<RDF::Base::Arc::Lim> object. This will modify the args variable in
cases when arclim isn't already a valid object.

C<$arclim> is given, in the right position, as anything other than a
hashref.  It will be given to L<RDF::Base::Arc::Lim/parse>, that takes
many alternative forms, including arrayrefs and scalar strings.
C<$arclim> may instead be given as a named parameter in C<\%args>.
The given C<$arclim> will be placed in a constructed C<$args> and
returned.

C<0> represents here a false argument, including undef or no
argument. This will generate an empty C<\%props>.

C<$special> can be a couple of standard configurations:

auto: If user has root access, sets arclim to ['not_old'] and
unique_arcs_prio to ['new', 'submitted', 'active']. Otherwise, sets
special to 'relative'.

relative: Sets arclim to ['active', ['not_old', 'created_by_me']] and
unique_arcs_prio to ['new', 'submitted', 'active'].

solid: Sets arclim to ['active] and unique_arcs_prio to ['active'].

all: Sets arclim to [['active'], ['inactive']] and
unique_arcs_prio to ['active'].

Arguments from L<RDF::Base::User/default_propargs> are used for any
UNEXISTING argument given. You can for example override the use of a
default unique_arcs_prio by explicitly setting unique_arcs_prio to
undef.

Returns in array context: (C<$arg>, C<$arclim>, C<$res>)

Returns in scalar context: C<$arg>

The returned C<arclim> is also found as the arclim named parameter in
C<arg>, so that's just syntactic sugar. With no input, the return will
be the two values C<{}, []>, there C<[]> is an empty
L<RDF::Base::Arc::Lim> object (that can be generated by parsing
C<[]>).

=cut

sub parse_propargs
{
    my( $arg ) = @_;

    my $def_args;
    if( $Para::Frame::U and
	UNIVERSAL::can($Para::Frame::U, 'default_propargs') )
    {
	if( $def_args = $Para::Frame::U->default_propargs )
	{
	    unless( $arg )
	    {
		$arg = $def_args;
		$def_args = undef;
	    }
	}
    }

    my $arclim;

    if( ref $arg and ref $arg eq 'HASH' )
    {
	$arclim = $arg->{'arclim'};
    }
    elsif( ref $arg )
    {
	$arclim = $arg;
	$arg = { arclim => $arclim };
#	debug "parse_propargs ".datadump(\@_,3);
    }
    elsif( defined $arg )
    {
	my $unique;
	if( $arg eq 'auto' )
	{
	    if( $Para::Frame::U and $Para::Frame::U->has_root_access )
	    {
		$arclim = [8192]; # not_old
		$unique = [1024, 256, 1]; # new, submitted, active
	    }
	    else # relative
	    {
		# active or (not_old and created_by_me)
		$arclim = [1, 8192+16384];
		$unique = [1024, 256, 1]; # new, submitted, active
	    }
	}
	elsif( $arg eq 'relative' )
	{
	    # active or (not_old and created_by_me)
	    $arclim = [1, 8192+16384];
	    $unique = [1024, 256, 1]; # new, submitted, active
	}
	elsif( $arg eq 'solid' )
	{
	    $arclim = [1+128]; # active, not_disregarded
	    $unique = [1]; # active
	}
	elsif( $arg eq 'all' )
	{
	    # active or inactive
	    $arclim = [1, 2];
	    $unique = [1]; # active
	}
	else
	{
	    $arclim = [$arg]
	}

	$arg = { arclim => $arclim };

	if( $unique )
	{
	    $arg->{unique_arcs_prio} = $unique;
	}
    }
    else
    {
	$arclim = RDF::Base::Arc::Lim->parse([]);
	$arg = { arclim => $arclim };
    }

    unless( UNIVERSAL::isa( $arclim, 'RDF::Base::Arc::Lim') )
    {
	$arg->{'arclim'} = $arclim =
	  RDF::Base::Arc::Lim->parse( $arclim );
    }

    my $res = $arg->{'res'} ||= RDF::Base::Resource::Change->new;

    if( $def_args )
    {
	foreach my $key (keys %$def_args)
	{
	    unless( exists $arg->{$key} )
	    {
		$arg->{$key} = $def_args->{$key};
	    }
	}
    }

    if( $arg->{arc_active_on_date} )
    {
	$arg->{'arclim'} = $arclim =
	  RDF::Base::Arc::Lim->parse([1,4096]); # active or old
	delete $arg->{unique_arcs_prio};
    }


    if( wantarray )
    {
	return( $arg, $arclim, $res );
    }
    else
    {
	return $arg;
    }
}

#########################################################################

=head2 proplim_to_arclim

  proplim_to_arclim( \%proplim, $is_rev )

Converts a proplim for use in arclist by adding obj top criterions.


=cut

sub proplim_to_arclim
{
    my( $proplim, $is_rev ) = @_;
    $is_rev ||= 0;
    return undef unless $proplim;

    my $prefix = 'obj';
    if( $is_rev )
    {
	$prefix = 'subj';
    }

    my %new;
    foreach my $crit ( keys %$proplim )
    {
	$new{ $prefix .'.'. $crit } = $proplim->{$crit};
    }

    return \%new;
}

#########################################################################

=head2 aais

  aais( \%args, $limit )

Stands for C<args_arclim_intersect>.

Returns: A new clone of args hashref, with a clone of the arclim
modified with L<RDF::Base::Arc::Lim/add_intersect>

=cut

sub aais
{
    my( $args, $arclim ) = parse_propargs(shift);
    my $lim = shift;

    my $arclim_new = $arclim->clone->add_intersect($lim);

    return({%$args, arclim=>$arclim_new});
}

#########################################################################

=head2 alphanum_to_id

  alphanum_to_id( $alphanum )

=cut

sub alphanum_to_id
{
    my( $alphanum_in ) = @_;

    my $alphanum = uc($alphanum_in);

    my @map = ((0..9),('A'..'Z'));
    my $pow = scalar(@map);
    my %num;
    for(my$i=0;$i<=$#map;$i++)
    {
	$num{$map[$i]}=$i;
    }

    my $chkchar = substr $alphanum,-1,1,'';

    my $chksum = 0;
    my $id = 0;
    my $len = length($alphanum)-1;

    for(my $i=$len;$i>=0;$i--)
    {
	my $val = $num{substr($alphanum, $i, 1)};
	$chksum += $val;
	my $pos = $len-$i;
#	print "  Pos $pos, pow $pow, val $val\n";
	my $inc = $val * ($pow ** $pos);
#	print "  --> $inc\n";
	$id += $inc;
    }

    if( $id > 2147483647 ) # Max int size in DB
    {
	return undef;
    }

    if( $map[$chksum%$pow] eq $chkchar )
    {
	return $id;
    }
    else
    {
	debug "Checksum mismatch for alphanum $alphanum; id=$id; checksum = ".$map[$chksum%$pow];

	return undef;
    }
}

##############################################################################

=head2 range_pred

  my( $range, $range_pred ) = range_pred(\%args)

=cut

sub range_pred
{
    if( my $range = $_[0]->{'range'} )
    {
#        debug "Found range in args: ".$range->sysdesig;
        return( $range, 'is' );
    }

    while( my($key,$val) = each %{$_[0]} )
    {
#        debug "Looking for range in $key -> $val";
        if( $key =~ /^range_(.*)/ )
        {
            keys %{$_[0]}; # reset 'each' iterator
            return( $val, $1 );
        }
    }

    return;
}

##############################################################################



1;
