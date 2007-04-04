#  $Id$  -*-cperl-*-
package Rit::Base::Utils;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Utils class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Utils - Utility functions for RitBase

=cut

use strict;
use Carp qw( cluck confess carp croak );
use UNIVERSAL;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw trim chmod_file debug datadump deunicode );
use Para::Frame::Reload;

use base qw( Exporter );
BEGIN
{
    @Rit::Base::Utils::EXPORT_OK
	= qw( translate cache_sync cache_clear cache_update valclean
	      format_phone format_zip getnode getarc getpred
	      parse_query_props parse_form_field_prop
	      parse_arc_add_box is_undef arc_lock arc_unlock
	      truncstring string parse_query_pred
	      parse_query_prop convert_query_prop_for_creation
	      name2url send_cache_update );

}

use Rit::Base::Undef;
use Rit::Base::Time qw( now );
use Rit::Base::String;



=head1 FUNCTIONS

Exportable.

TODO: Move most if not all of these functions to another place...

Please think about _not_ using these...

=cut


#######################################################################

=head2 getnode

  getnode( $arg )

Calls L<Rit::Base::Resource/get> with C<$arg>.

Returns: See L<Rit::Base::Resource/get>

=cut

sub getnode
{
    return Rit::Base::Resource->get(@_);
}

#######################################################################

=head2 getarc

  getarc( $arg )

Calls L<Rit::Base::Arc/get> with C<$arg>.

Returns: See L<Rit::Base::Resource/get>

=cut

sub getarc
{
    return Rit::Base::Arc->get(@_);
}


#######################################################################

=head2 getpred

  getpred( $arg )

Calls L<Rit::Base::Pred/get> with C<$arg>.

Returns: See L<Rit::Base::Resource/get>

=cut

sub getpred
{
    return Rit::Base::Pred->get(@_);
}


#######################################################################

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

    $Rit::Base::Cache::Created = $time || time;

    %Rit::Base::Cache::Label = ();
    %Rit::Base::Cache::Resource = ();
    %Rit::Base::Cache::find_simple = ();

    # TODO: Clear %Rit::Guides::Organization::STATS_CHANGE

    Rit::Base::Arc->clear_queue;
}


#######################################################################

=head2 cache_update

TODO: Broken. FIXME

=cut

sub cache_update
{
    $Rit::Base::Cache::Changed = time;

    ### TODO: let the caller modify find_simple cache, so that we
    ### doesn't have to reset it every time anything changed

    %Rit::Base::Cache::find_simple = ();
}


#######################################################################

=head2 cache_sync

TODO: Broken. FIXME

=cut

sub cache_sync
{
    my $dir_var = $Para::Frame::CFG->{'dir_var'};

    # Should only be called at the end of the request

    # Commit changes and discard cache if DB has been updated from
    # another process

    ## Export changes
    if( $Rit::Base::Cache::Changed )
    {
	my $time = time;
	$Rit::dbix->dbh->commit;
	### TODO: Place cache in common dir for ritframe.  Use hgv2 as prefix
	### .. because hg and tg uses the same db
	my $filename = "$dir_var/cache";
	open FILE, ">$filename" or die "Can't write to $filename: $!";
	print FILE $time;
	close FILE;
	chmod_file( $filename );	## Chmod file
	$Rit::Base::Cache::Changed = undef;
	$Rit::Base::Cache::Created = $time;

	debug ">>> Commit cache\n";

	if( 1 ) ### DEBUG
	{
	    my($package, $filename, $line) = caller;
	    debug "    called from $package, row $line\n";
	}
    }

    ## Import changes
    $Rit::Base::Cache::Created ||= time;
    if( my $time = (stat("$dir_var/cache"))[9] )
    {
	if( $time > $Rit::Base::Cache::Created )
	{
	    # DB changed.  cache old
	    cache_clear($time);
	}
    }


    ## Report size
    my $cache_size = scalar( keys %Rit::Base::Cache::Resource );
    debug "--- Cache size: $cache_size\n";
}


#######################################################################

=head2 valclean

  valclean( $value )

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

    if( ref $value )
    {
	$value = $value->plain;
    }

    return undef unless defined $value;

    debug "  Normalizing $value to\n" if $DEBUG;

    # Don't change valclean algoritm wihout recleaning the whole DB!
    use locale;
    use POSIX qw(locale_h);
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
    return $value
}


#######################################################################

=head2 name2url

  name2url( $name )

Converts a name to a reasonable string to use in an url

=cut

sub name2url
{
    my( $name ) = @_;

    deunicode( $name );

    use locale;
    use POSIX qw(locale_h);
    setlocale(LC_ALL, "sv_SE");
    my $url = lc($name);

    $url =~ tr[àáâäãåæéèêëíìïîóòöôõøúùüûýÿðþß]
	      [aaaaaaaeeeeiiiioooooouuuuyydps];
    $url =~ s/[^\w\s\-~]//g;
    $url =~ s/\s+/_/g;
    $url =~ s/( ^_+ | _+$ )//gx;

    return $url;
}


#######################################################################

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


#######################################################################

=head2 format_zip

Deprecated

=cut

sub format_zip
{
    my( $text ) = @_;
    $text =~ s/(^\s+|\s+$)//g;
    return $text;
}


#######################################################################

=head2 parse_query_props

  parse_query_props( $string )

Splits the string to a list of values if separated by ','.

The first part of each element should be a predicate and the rest,
after the first space, should be the value.

Returns:

a props hash with pred/value pairs.

Example:

  name Jonas Liljegren, age 33

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
    foreach my $pair ( split /\s*,\s*/, $prop_text )
    {
	my($prop_name, $value) = split(/\s+/, $pair, 2);
	trim(\$prop_name);
	trim(\$value);
	$props->{$prop_name} = $value;
    }
    return $props;
}


#######################################################################

=head2 parse_form_field_prop

  parse_form_field_prop( $string )

Splits the string into an arg list.

The format is name1_val1__name2_val2__name3_val3...

Vals can be empty: name1___name2_val2...

Vals can contain underscore: pred_in_region...

The string can begin with C<check_>.

Returns:

a props hash with pred/value pairs.

Example:

  arc___revpred_has_member__type_marketing_group

  becomes:

  {
    arc     => undef,
    revpred => 'has_member',
    type    => 'marketing_group',
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

	$arg{$key} = $val;
    }
    return \%arg;
}


#######################################################################

=head2 parse_arc_add_box

  parse_arc_add_box( $string )

Splits the string up with one property for each row.

The first part of each element should be a predicate and the rest,
after the first space, should be the value.

Value nodes can be created by giving adding the value props after an
C<-E<gt>>. Those props are parsed using L</parse_query_props>.

NB! This function ads value arcs so that the returning props list can
be used for creating arcs.

Returns:

a props hash with pred/value pairs.

Example:

  name Sverige -> is_of_language sv (code)
  is country

This would create a node with the properties

  $valnode1 =
  {
    is_of_language => 'sv (code)',
    value    => 'Sverige',
    datatype => $text,
  }

And then return the hashref

  {
    name => $valnode1,
    is   => 'country',
  }

Note that the value node is created even if you don't use the returned
hashref for creating the arcs using that value node.

The C<sv (code)> part will be parsed by
L<Rit::Base::Resource/find_by_label>, as will all the values.

=cut

sub parse_arc_add_box
{
    my( $query ) = @_;

    my $DEBUG = 0;
    my $changed = 0;  # How to use?
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
	    my $sprops = parse_query_props( $2 );
	    my $svalue = $1;
	    my $pred = Rit::Base::Pred->get_by_label( $pred_name );
	    $value = Rit::Base::Resource->create( $sprops );
	    Rit::Base::Arc->create({
				    subj    => $value,
				    pred    => 'value',
				    value   => $svalue,
				    valtype => $pred->valtype,
				   });
	    $changed ++;
	}

	unless( ref $value )
	{
	    my $coltype = Rit::Base::Pred->get($pred_name)->coltype;
	    $value = Rit::Base::Resource->get_by_label( $value, $coltype );
	}

	debug "  $pred_name: ".$value->sysdesig."\n" if $DEBUG;
	push @{ $props->{$pred_name} }, $value;
    }

    return $props;
}


#######################################################################

=head2 parse_query_pred

  parse_query_pred( $predstring )

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

	if( $pred =~ s/^predor_// )
	{
	    my( @prednames ) = split /_-_/, $pred;
	    my( @preds ) = map Rit::Base::Pred->get($_), @prednames;
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

	    $pred = Rit::Base::Pred->get( $pred );
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

#######################################################################

=head2 parse_query_prop

  parse_query_preds( \%props )

  parse_query_preds( \%props, \%args )

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
	elsif( ref $valref eq 'Rit::Base::List' )
	{
	    @values = $valref->nodes;
	}
	else
	{
	    @values = ($valref);
	}

	foreach( @values )
	{
	    if( ref $_ and UNIVERSAL::isa($_, 'Rit::Base::Resource::Compatible') )
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
		    $_ = Rit::Base::Resource->get_id( $_ );
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
		if( ref $val and UNIVERSAL::isa( $val, 'Rit::Base::Object::Compatible' ) )
		{
		    unless( $val->defined )
		    {
			$val = undef;
		    }
		}

		if( defined $val and length $val )
		{
		    push @new, Rit::Base::Resource->resolve_obj_id( $val );
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


#######################################################################

=head2 convert_query_prop_for_creation

  convert_query_prop_for_creation( \%props )

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
	unless( UNIVERSAL::isa($pred, 'Rit::Base::Pred') )
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

	$props{$pred_name} = $rec->{'values'};
    }

    return \%props;
}


#######################################################################

=head2 is_undef

  is_undef()

Returns:

An L<Rit::Base::Undef> object.

=cut


sub is_undef ()
{
#    carp "got <UNDEF> value";
#    warn "\t\t\t<undef>\n";
    return Rit::Base::Undef->new();
}


#######################################################################

=head2 arc_lock

  arc_lock()

Calls L<Rit::Base::Arc/lock>

=cut

sub arc_lock
{
    Rit::Base::Arc->lock;
}


#######################################################################

=head2 arc_unlock

  arc_unlock()

Calls L<Rit::Base::Arc/unlock>

=cut

sub arc_unlock
{
    Rit::Base::Arc->unlock;
}


#######################################################################

=head2 truncstring

  truncstring( $string, $length )

The string may be a string ref or an L<Rit::Base::Object>. It doesnt
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
	if( ref $str eq 'Rit::Base::List' )
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

#######################################################################

=head2 string

  string($string)

Calls L<Rit::Base::String/new> with C<$string>.

=cut

sub string
{
    return Rit::Base::String->new(@_);
}


#######################################################################

=head2 query_desig

  query_desig($query)

=cut

sub query_desig
{
    my( $query, $ident ) = @_;

    $ident ||= 0;
    my $out = "";

    if( ref $query )
    {
	if( ref $query eq 'HASH' )
	{
	    foreach my $key ( keys %$query )
	    {
		my $val = query_desig($query->{$key}, $ident+1);
		if( $val =~ /\n.*?\n/s )
		{
		    $out .= '  'x$ident . "$key:\n";
		    $out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
		}
		else
		{
		    $val =~ s/\n*$/\n/;
		    $out .= '  'x$ident . "$key: $val";
		}
	    }
	}
	elsif( ref $query eq 'ARRAY' )
	{
	    foreach my $val ( @$query )
	    {
		my $val = query_desig($val, $ident+1);
		if( $val =~ /\n.*?\n/s )
		{
		    $out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
		}
		else
		{
		    $val =~ s/\n*$/\n/;
		    $out .= '  'x$ident . $val;
		}
	    }
	}
	else
	{
	    my $val = $query->sysdesig;
	    debug "Got val $val\n";
	    if( $val =~ /\n.*?\n/s )
	    {
		$out .= join "\n", map '  'x$ident.$_, split /\n/, $val;
	    }
	    else
	    {
		$val =~ s/\n*$/\n/;
		$out .= '  'x$ident . $val;
	    }
	}
    }
    else
    {
	debug "Query is plain $query\n";
	if( $query =~ /\n.*?\n/s )
	{
	    $out .= join "\n", map '  'x$ident.$_, split /\n/, $query;
	}
	else
	{
	    $out =~ s/\n*$/\n/;
	    $out .= '  'x$ident . $query;
	}
    }

    return $out;
}


#######################################################################

=head2 send_cache_update

  

=cut

sub send_cache_update
{
    my( $params ) = @_;

    my @params;

    foreach my $key ( keys %$params )
    {
	push @params, $key ."=". $params->{$key};
    }

    my $request = "update_cache?" . join('&', @params);

    my @daemons = @{$Para::Frame::CFG->{'daemons'}};

    my $send_cache = sub
    {
	my( $req ) = @_;

	foreach my $site (@daemons)
	{
	    my $daemon = $site->{'daemon'};
	    next
	      if( grep( /$site->{'site'}/, keys %Para::Frame::Site::DATA ));
	    debug(0,"Sending update_cache to $daemon");

	    eval {
		$req->send_to_daemon( $daemon, 'RUN_ACTION',
				      \$request );
	    }
	      or do
	      {
		  debug(0,"Couldn't send cache_update to $daemon");
	      }
	  }
	return "remove_hook";
    };

    $Para::Frame::REQ->add_background_job( $send_cache );

}


###############################################################################



1;
