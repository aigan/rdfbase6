#  $Id$  -*-cperl-*-
package Rit::Base::Utils;

use strict;
use Carp qw( cluck confess carp croak );
use Data::Dumper;
use UNIVERSAL;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw trim chmod_file debug );
use Para::Frame::Reload;

use base qw( Exporter );
BEGIN
{
    @Rit::Base::Utils::EXPORT_OK
	= qw( translate cache_sync cache_clear cache_update valclean
	      format_phone format_zip getnode getarc getpred
	      parse_query_props parse_form_field_prop
	      parse_arc_add_box is_undef arc_lock arc_unlock
	      log_stats_commit truncstring string );

}

use Rit::Base::Undef;
use Rit::Base::Time qw( now );
use Rit::Base::String;

#use POSIX qw(locale_h strftime);
#use locale;

sub translate
{
    confess "deprecated";

    my $req = $Para::Frame::REQ;

    # The object to be translated could be one or more value nodes.
    # choose the right value node

    if( ref $_[0] )
    {
	if( ref $_[0] eq 'Rit::Base::List' )
	{
	    return $_[0]->loc;
	}
	elsif( ref $_[0] eq 'Rit::Base::Literal' )
	{
	    $_[0] = $_[0]->literal;
	}
	elsif( ref $_[0] eq 'Rit::Base::Resource' )
	{
	    if( my $val = $_[0]->value )
	    {
		return $val;
	    }
	    croak "Can't translate value: ". Dumper($_[0]);
	}
	elsif( ref $_[0] eq 'Rit::Base::Undef' )
	{
	    return '';
	}
	else
	{
	    croak "Can't translate value: ". Dumper($_[0]);
	}
    }

    my $rec = $Rit::dbix->select_possible_record('from tr where c=?',$_[0]);
    foreach my $lang ( $req->language->alternatives )
    {
	return $rec->{$lang} if defined $rec->{$lang} and length $rec->{$lang};
    }

    return $_[0];
}


sub getnode
{
    return Rit::Base::Resource->get(@_);
}

sub getarc
{
    return Rit::Base::Arc->get(@_);
}

sub getpred
{
    return Rit::Base::Pred->get(@_);
}

sub cache_clear
{
    my( $time ) = @_;

    debug "<<< Expunge cache\n";

    $Rit::Base::Cache::Created = $time || time;
    %Rit::Base::Cache::Resource = ();
    %Rit::Base::Cache::Id = ();
    %Rit::Base::Cache::User = ();
    %Rit::Base::Cache::find_simple = ();
    %Rit::Base::Cache::stats_change = ();
    Rit::Base::Arc->clear_queue;
}

sub cache_update
{
    $Rit::Base::Cache::Changed = time;

    ### TODO: let the caller modify find_simple cache, so that we
    ### doesn't have to reset it every time anything changed

    %Rit::Base::Cache::find_simple = ();
}

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
    $value =~ tr/àáâäãåéèêëíìïîóòöôõúùüûýÿðþ/aaaaaaeeeeiiiiooooouuuuyydp/;
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

sub format_phone
{
    my( $text ) = @_;
    $text =~ s/(^\s+|\s+$)//g;
    $text =~ s/^0//;
    $text =~ s/^\+\d+\D+//;
    return $text;
}

sub format_zip
{
    my( $text ) = @_;
    $text =~ s/(^\s+|\s+$)//g;
    return $text;
}


sub parse_query_props
{
    my( $prop_text ) = @_;

    # TODO: Handle things like:  val (p1 val1, p2 val2 (ps1 vals1, ps2, vals2), p3 val3)

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

sub parse_form_field_prop
{
    my( $string ) = @_;

    $string =~ s/^check_//;

    my %arg;
    ## The format is name1_val1__name2_val2__name3_val3...
    ## Vals can be empty: name1___name2_val2...
    ## Vals can contain underscore: pred_in_region...
    foreach my $part ( split /___?/, $string )
    {
	my( $key, $val ) = $part =~ /^([^_]+)_?(.*)/
	    or die "Malformed part: $part\n";

	$arg{$key} = $val;
    }
    return \%arg;
}

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
	    $sprops->{'value'} = $1;
	    my $pred = Rit::Base::Pred->get_by_label( $pred_name );
	    $sprops->{'datatype'} = $pred->valtype;
	    $value = Rit::Base::Resource->create( $sprops );
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


sub is_undef ()
{
#    carp "got <UNDEF> value";
#    warn "\t\t\t<undef>\n";
    return Rit::Base::Undef->new();
}

sub arc_lock
{
    Rit::Base::Arc->lock;
}

sub arc_unlock
{
    Rit::Base::Arc->unlock;
}

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

=head2 log_stats_commit

Comit all the stats changes

=cut

sub log_stats_commit
{
    my $req = $Para::Frame::REQ;
    my $dbix = $Rit::dbix;
    my $dbh = $dbix->dbh;
    my $now = now();
    my $now_db = $dbix->format_datetime($now);

    my $sth_find = $dbh->prepare
      ("select node from stats where node=? and day=? for update");

    $dbh->commit; # this function should be calld last

    foreach my $type ( keys %Rit::Base::Cache::stats_change )
    {
	my $sth_update = $dbh->prepare
	  ("update stats set $type = $type + ? where node=? and day=?");
	my $sth_create = $dbh->prepare
	  ("insert into stats (node, $type) values (?, ?)");

	my %stats;
	foreach my $node (@{$Rit::Base::Cache::stats_change{$type}})
	{
	    $stats{$node->id} ++;
	}

	foreach my $nid ( keys %stats )
	{
	    my $success = 0;
	    my $fail = 0;
	    do
	    {
		eval
		{
		    $sth_find->execute($nid, $now_db);
		    if( $sth_find->rows )
		    {
			$sth_update->execute($stats{$nid}, $nid, $now_db);
		    }
		    else
		    {
			$sth_create->execute($nid, $stats{$nid});
		    }
		    $sth_find->finish;
		    $success = 1;
		} or do
		{
		    $fail ++;
		    $dbh->rollback;
		};
	    } until( $success or $fail > 10 );
	    $dbh->commit;
	}
    }

    %Rit::Base::Cache::stats_change = ();

    return '';
}

sub string
{
    return Rit::Base::String->new(@_);
}


#######################################################################


1;
