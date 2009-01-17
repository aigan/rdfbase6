#  $Id$  -*-cperl-*-
package Rit::Base::Setup;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Setup

=head2 DESCRIPTION

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use utf8;
use DBI;
use Carp qw( croak );
use DateTime::Format::Pg;
use Encode; # encode decode

use Para::Frame::Utils qw( debug datadump throw );
use Para::Frame::Time qw( now );

use Rit::Base;
use Rit::Base::Utils qw( valclean );
use Rit::Base::Constants;
use Rit::Base::Literal::Class;

our %NODE;
our @NODES;
our @ARC;
our %VALTYPE;
our %NOLABEL;
our %LITERAL;
our @LITERALS;

sub setup_db
{
    my $dbix = $Rit::dbix;
    my $dbh = $dbix->dbh;
    my $now = DateTime::Format::Pg->format_datetime(now);


    my $old_debug = $Para::Frame::DEBUG;
    $Para::Frame::DEBUG = 0;

#    my $cnt = $dbix->get_lastval('node_seq');
#    debug "First node will have number $cnt";


    my $rb_root = $Para::Frame::CFG->{'rb_root'}
      or die "rb_root not given in CFG";



    unless( $dbix->table('arc') )
    {
	my $sql = "";
	open RBSCHEMA, "$rb_root/data/schema.sql" or die $!;
	while(<RBSCHEMA>)
	{
	    $sql .= $_;
	    if( /;.*$/ )
	    {
		$dbh->do($sql) or die "sql error";
		$sql = "";
	    }
	}
    }






    open RBDATA, "$rb_root/data/base.data" or die $!;
    while(<RBDATA>)
    {
	chomp;
	last if $_ eq 'NODES';
    }

    $dbh->do("delete from arc") or die;
    $dbh->do("delete from node") or die;
    $dbh->do("select setval('node_seq',1,false)");


    debug "Reading Nodes";
    while(<RBDATA>)
    {
	chomp;
	next unless $_;
	last if $_ eq 'ARCS';

	my( $label, $pred_coltype ) = split /\t/, $_;

	my $id = $dbix->get_nextval('node_seq');

	push @NODES, $label;
	$NODE{$label} =
	{
	 label => $label,
	 pred_coltype => $pred_coltype,
	 node => $id,
	};

	debug "$id = $label";
    }

    debug "Reading Arcs";
    my $is_literal = 0;
    while(<RBDATA>)
    {
	chomp;
	next unless $_;
	last if $_ eq 'EOF';

	if( /^LITERALS/ )
	{
	    $is_literal = 1;
	    next;
	}

	my( $subj, $pred, $obj, $value ) = split /\t/, $_;

	push @ARC,
	{
	 subj => $subj,
	 pred => $pred,
	 obj => $obj,
	 value => $value,
	};

	my $valdbg = $obj || $value;
	debug "Planning $subj --$pred--> $valdbg";

	if( $is_literal )
	{
	    $LITERAL{$subj} = [$obj];
	    push @LITERALS, $subj;

	    if( $LITERAL{$obj} )
	    {
		foreach my $obj2 ( @{$LITERAL{$obj}} )
		{
		    push @{$LITERAL{$subj}}, $obj2;
		}
	    }

	}

	foreach my $label ($subj, $pred, $obj)
	{
	    next unless $label;
	    next if $label =~ /^\d+$/;

	    unless( $NODE{$label} )
	    {
		my $id = $dbix->get_nextval('node_seq');
		push @NODES, $label;
		$NODE{$label} =
		{
		 label => $label,
		 node => $id,
		};

		debug "$id = $label";
	    }
	}

    }

    close RBDATA;

    debug "Bootstrapping literals";

#    debug datadump(\@LITERALS);
#    debug datadump(\%LITERAL);
#    exit;


    foreach my $lit (@LITERALS)
    {
	my $scofs = $LITERAL{$lit};
	debug "Literal $lit is a scof ".$scofs->[0];

	for( my $i=1; $i<= $#$scofs; $i++ )
	{
	    push @ARC,
	    {
	     subj => $lit,
	     pred => 'scof',
	     obj => $scofs->[$i],
	    };
	    debug "Literal $lit is a scof ".$scofs->[$i];
	}

	push @ARC,
	    {
	     subj => $lit,
	     pred => 'is',
	     obj => 'literal_class',
	    };
    }


    debug "Adding nodes";
    my $root = $NODE{'root'}{'node'};
    my $sth_node = $dbh->prepare('insert into node (node,label,owned_by,pred_coltype,created,created_by,updated,updated_by) values (?,?,?,?,?,?,?,?)') or die;

    foreach my $label ( @NODES )
    {
	my $rec = $NODE{ $label };
	my $node = $rec->{'node'};
	my $owned_by = $root;
	my $pred_coltype = $rec->{'pred_coltype'} || undef;
	my $created = $now;
	my $created_by = $root;
	my $updated = $now;
	my $updated_by = $root;

	$sth_node->execute($node, $label, $owned_by, $pred_coltype, $created, $created_by, $updated, $updated_by);
    }

    debug "Extracting valtypes";
    foreach my $rec ( @ARC )
    {
	if( $rec->{'pred'} eq 'range' )
	{
	    my $pred = $rec->{'subj'};
	    my $valtype_name = $rec->{'obj'};
	    my $valtype = $NODE{$valtype_name}{'node'};
	    $VALTYPE{$pred} = $valtype;
	    debug "Valtype $pred = $valtype";
	}
    }

    debug "Adding arcs";
    my $source = $NODE{'ritbase'}{'node'};
    my $read_access = $NODE{'public'}{'node'};
    my $write_access = $NODE{'sysadmin_group'}{'node'};
    my $sth_arc = $dbh->prepare("insert into arc (id,ver,subj,pred,source,active,indirect,implicit,submitted,read_access,write_access,created,created_by,updated,activated,activated_by,valtype,obj,valtext,valclean,valbin) values (?,?,?,?,?,'t','f','f','f',?,?,?,?,?,?,?,?,?,?,?,?)") or die;
    foreach my $rec ( @ARC )
    {
	my $pred_name = $rec->{'pred'};
	my $coltype_num = $NODE{$pred_name}{'pred_coltype'} or die "No coltype given for pred $pred_name";
	my $coltype = $Rit::Base::Literal::Class::COLTYPE_num2name{$coltype_num} or die "Coltype $coltype_num not found";
	my $obj_in = $rec->{'obj'};
	my $value;
	if( $obj_in )
	{
	    if( $obj_in =~ /^\d+$/ )
	    {
		$value = $NOLABEL{ $obj_in };
		unless( $value )
		{
		    $value = $NOLABEL{ $obj_in }
		      = $dbix->get_nextval('node_seq');
		}
	    }
	    else
	    {
		$value = $NODE{$obj_in}{'node'};
	    }
	}
	else
	{
	    $value = $rec->{'value'};
	}

	my $subj;
	my $subj_in = $rec->{'subj'};
	if( $subj_in =~ /^\d+$/ )
	{
	    $subj = $NOLABEL{ $subj_in };
	    unless( $subj )
	    {
		$subj = $NOLABEL{ $subj_in }
		  = $dbix->get_nextval('node_seq');
	    }
	}
	else
	{
	    $subj = $NODE{$subj_in}{'node'};
	}

	my $id = $dbix->get_nextval('node_seq');
	my $ver = $dbix->get_nextval('node_seq');
	my $pred = $NODE{$pred_name}{'node'};
	my $valtype = $VALTYPE{$pred_name} or die "Could not find valtype for $pred_name";
	my( $obj, $valtext, $valclean, $valbin );

	if( $coltype eq 'obj' )
	{
	    $obj = $value;
	}
	elsif( $coltype eq 'valtext' )
	{
	    $valtext = $value;
	    $valclean = valclean( $value );
	}
	elsif( $coltype eq 'valbin' )
	{
	    $valbin = $value;
	}
	else
	{
	    die "$coltype not handled";
	}

	$sth_arc->execute($id, $ver, $subj, $pred, $source, $read_access, $write_access, $now, $root, $now, $now, $root, $valtype, $obj, $valtext, $valclean, $valbin) or die;
    }

    $dbh->commit;
    $Para::Frame::DEBUG = $old_debug;
    $Rit::Base::VACUUM_ALL = 1; # For not vacuuming recursively


    # Initialization of constants and valtypes
    Rit::Base::Literal::Class->on_startup();
    Rit::Base::Resource->on_startup();
    Rit::Base::Constants->on_startup();

    my $root_node = Rit::Base::Resource->get_by_id( $root );
    debug "Setting bg_user_code to $root";
    $Para::Frame::CFG->{'bg_user_code'} = sub{ $root_node };


    my $req = Para::Frame::Request->new_bgrequest();

    debug "Infering arcs";

    my $sth_arc_list = $dbh->prepare("select * from arc order by ver");
    $sth_arc_list->execute();
    my @arc_recs;
    while( my $arc_rec = $sth_arc_list->fetchrow_hashref )
    {
	push @arc_recs, $arc_rec;
    }
    $sth_arc_list->finish;

    foreach my $arc_rec (@arc_recs)
    {
	debug "  arc ".$arc_rec->{ver};
	my $arc = Rit::Base::Arc->get_by_rec_and_register($arc_rec);
	debug "  ".$arc->sysdesig;
	$arc->create_check;
    }

    $dbh->commit;

    debug "Initiating constants again";

    Rit::Base::Constants->on_startup;
    $Rit::Base::IN_STARTUP = 0;

    debug "Done!";

   return;
}


#######################################################################

sub convert_valuenodes
{
    my $dbix = $Rit::dbix;
    my $dbh = $dbix->dbh;
    my $req = Para::Frame::Request->new_bgrequest();
    my $now_db = DateTime::Format::Pg->format_datetime(now);
    my $R = Rit::Base->Resource;
    my $C = Rit::Base->Constants;

    print "\nCONVERTING VALUENODES\n\n";

#    my $arclist = $dbix->select_list("from arc where pred=4 order by ver desc");

    my @REMOVE;
    my @CONVERT;
    my %VNODE;


    my $dupsubjlist = $dbix->select_list("select distinct subj from arc where pred=4 and active is true group by subj having count(pred)>1 order by subj desc");
    debug sprintf "Got %d subjs with duplicate value arcs", $dupsubjlist->size;
    my( $dupsubjrec, $dserror ) = $dupsubjlist->get_first;
    while(! $dserror )
    {
	my $node = $R->get($dupsubjrec->{'subj'});

	debug $node->sysdesig;

	# Keeps the last value arc
	my $varcs = $node->arc_list('value')->sorted('id');
	my( $arc, $aerr ) = $varcs->get_first;
	while(!$aerr )
	{
	    if( $varcs->last )
	    {
		debug "Keeping  resource ".$arc->sysdesig;
	    }
	    else
	    {
		$arc->remove({force_recursive=>1});
	    }
	}
	continue
	{
	    ( $arc, $aerr ) = $varcs->get_next;
	};
    }
    continue
    {
	( $dupsubjrec, $dserror ) = $dupsubjlist->get_next;
    };


    my $arclist = $dbix->select_list("from arc where pred=4 order by ver desc");

    debug sprintf "Sorting %d arcs", $arclist->size;

    my $update_sth = $dbh->prepare("update arc set valfloat=?, valdate=?, valtext=?, valclean=?, valtype=?, activated=?, activated_by=?, updated=? where ver=?") or die;
    my $remove_sth = $dbh->prepare("delete from arc where ver=?");
    my $null_replaces = $dbh->prepare("update arc set replaces=null where replaces=?");

    my( $rec, $error ) = $arclist->get_first;
    while(! $error )
    {
	unless( $arclist->count % 1000 )
	{
	    debug sprintf "%5d sorted", $arclist->count;
#	    last if $arclist->count == 100;
	}


	my $arc = Rit::Base::Arc->get_by_rec($rec);

#	debug $arc->sysdesig;

	if(not $arc->active)
	{
#	    debug "NOT ACTIVE";
	    push @REMOVE, $arc;
	    next;
	}

	push @CONVERT, $arc;
    }
    continue
    {
	( $rec, $error ) = $arclist->get_next;
    };

    debug sprintf "Converting %d arcs",scalar(@CONVERT);

    my $cnt = 0;
    foreach my $arc ( @CONVERT )
    {
	$VNODE{$arc->{'subj'}}++;

	unless( ++$cnt % 100 )
	{
	    debug sprintf "%5d COMMITTING", $cnt;
	    $dbh->commit;
	}

	my $recs = $dbix->select_list("from arc where obj=? and active is true", $arc->{'subj'});

	unless( $recs->size )
	{
	    debug "Arc unconnected: ".$arc->{'id'};
	    push @REMOVE, $arc;
	    next;
	}

	# Ignoring source, created, created_by, read_access, write_access

	my $valtype = $arc->valtype;
	my $valtype_db = $arc->valtype->id;
	my $coltype = $arc->coltype;
	my $activated_db = $arc->{'arc_activated'};
	my $activated_by_db = $arc->{'activated_by'};
	my $updated_db = $arc->{'arc_updated'};

	my( $valfloat, $valdate, $valtext, $valclean );
	my $value = $arc->value;

	if( $coltype eq 'valfloat' )
	{
	    $valfloat = $value;
	}
	elsif( $coltype eq 'valdate' )
	{
	    $valdate = DateTime::Format::Pg->format_datetime($value);
	}
	elsif( $coltype eq 'valtext' )
	{
	    $valtext = $value;
	    $valclean = valclean( $value );
	}
	else
	{
	    die "What is this? ".datadump($arc);
	}

#	debug $arc->sysdesig;
#	debug "About to overwrite ".datadump($rec);
#	last;

	foreach my $rec ($recs->as_array)
	{
	    $update_sth->execute($valfloat, $valdate, $valtext, $valclean, $valtype_db, $activated_db, $activated_by_db, $updated_db, $rec->{'ver'});
	}

	$null_replaces->execute($arc->{'id'});
	$remove_sth->execute($arc->{'id'});
    }

    debug "Committing";
    $dbh->commit;

    debug sprintf "Removing %d arcs",scalar(@REMOVE);
    $cnt = 0;
    # Removes the latest arc first, avoiding arc_replaces_fkey
    foreach my $arc ( sort {$b->{id} <=> $a->{id}} @REMOVE )
    {
	unless( ++$cnt % 100 )
	{
	    debug sprintf "%5d COMMITTING", $cnt;
	    $dbh->commit;
	}
	debug sprintf "%5d Removing %s", $cnt, $arc->sysdesig;

	$null_replaces->execute($arc->{'id'});
	$remove_sth->execute($arc->{'id'});
    }

    debug "Committing";
    $dbh->commit;

    if( $R->find({label=>'value'})->size )
    {
	$R->get(4)->remove({force=>1});
    }

    debug "Setting valtype for obj arcs";
    my $obj_arcs_sth = $dbh->prepare("select * from arc where valfloat is null and valdate is null and valbin is null and valtext is null and obj is not null and valtype <> 5");
    $obj_arcs_sth->execute;
    my $valtype_update_sth = $dbh->prepare("update arc set valtype=? where ver=?");
    my $obj_arc_cnt = 0;
    my $valtype_updated_cnt = 0;
    debug "  ".$obj_arcs_sth->rows." records";
    while( my $rec = $obj_arcs_sth->fetchrow_hashref )
    {
	unless( ++$obj_arc_cnt % 1000 )
	{
	    debug sprintf "%6d Total updated %5d",
	      $obj_arc_cnt, $valtype_updated_cnt;
	    $dbh->commit;
	}

	my $pred = Rit::Base::Pred->get($rec->{'pred'});
	next unless $pred->objtype;

	my $old_valtype_id = $rec->{'valtype'};

	my $obj = $R->get($rec->{'obj'});
	my $new_valtype_id = $obj->this_valtype->id;
	if( $new_valtype_id != $old_valtype_id )
	{
	    $valtype_updated_cnt++;
	    $valtype_update_sth->execute($new_valtype_id,$rec->{'ver'});
#	    debug "$rec->{ver}: $old_valtype_id -> $new_valtype_id";
	}
    }
    $obj_arcs_sth->finish;
    debug "Updated $valtype_updated_cnt valtypes";
    debug "Committing";
    $dbh->commit;


    debug "Cleaning up texts from old errors";
    my $update_text_sth = $dbh->prepare("update arc set valtext=?, valclean=? where ver=?") or die;

    my $text_sth = $dbh->prepare("select ver, valtext from arc where valtext is not null");
    $text_sth->execute;
    my $cleaned = 0;
    my $text_cnt = 0;
    debug "  ".$text_sth->rows." records";
    while( my $rec = $text_sth->fetchrow_hashref )
    {
	unless( ++$text_cnt % 10000 )
	{
	    debug sprintf "%6d Total cleaned %5d", $text_cnt, $cleaned;
#	    $dbh->commit;
	}

	my $ver = $rec->{'ver'};

	# Cleaning up UTF8...
	my $valtext = $rec->{'valtext'};
	my $decoded = $valtext;
	if( $valtext =~ /Ã./ )
	{
	    my $res;
	    while( length $decoded )
	    {
		$res .= decode("UTF-8", $decoded, Encode::FB_QUIET);
		$res .= substr($decoded, 0, 1, "") if length $decoded;
	    }
	    $decoded = $res;
	}
	else
	{
	    utf8::upgrade( $decoded );
	}

	# Repair chars in CP 1252 text,
	# incorrectly imported as ISO 8859-1.
	# For example x96 (SPA) and x97 (EPA)
	# are only used by text termianls.
	$decoded =~ s/\x{0080}/\x{20AC}/g; # Euro sign
	$decoded =~ s/\x{0085}/\x{2026}/g; # Horizontal ellipses
	$decoded =~ s/\x{0091}/\x{2018}/g; # Left single quotation mark
	$decoded =~ s/\x{0092}/\x{2019}/g; # Right single quotation mark
	$decoded =~ s/\x{0093}/\x{201C}/g; # Left double quotation mark
	$decoded =~ s/\x{0094}/\x{201D}/g; # Right double quotation mark
	$decoded =~ s/\x{0095}/\x{2022}/g; # bullet
	$decoded =~ s/\x{0096}/\x{2013}/g; # en dash
	$decoded =~ s/\x{0097}/\x{2014}/g; # em dash


	# Remove Unicode 'REPLACEMENT CHARACTER'
	$decoded =~ s/\x{fffd}//g;

	# Replace Space separator chars
	$decoded =~ s/\p{Zs}/ /g;

	# Replace Line separator chars
	$decoded =~ s/\p{Zl}/\n/g;

	# Replace Paragraph separator chars
	$decoded =~ s/\p{Zp}/\n\n/g;

	$decoded =~ s/[ \t]*\r?\n/\n/g; # CR and whitespace at end of line
	$decoded =~ s/^\s*\n//; # Leading empty lines
	$decoded =~ s/\n\s+$/\n/; # Trailing empty lines

	# Remove invisible characters, other than LF
	$decoded =~ s/(?!\n)\p{Other}//g;

	if( $valtext ne $decoded)
	{
	    $cleaned++;

#	    ### FIXED
#	    $valtext =~ s/\r//g;
#	    $valtext =~ s/\x{fffd}//g;
#	    $valtext =~ s/\x{000b}//g; # Vertical tabulation
#	    $valtext =~ s/\x{00ad}//g; # Soft hypen
#	    $valtext =~ s/\x{0009}//g; # Horizontal tabulation
#	    $valtext =~ s/\p{Co}//g;   # Private unicode char
#
#	    $valtext =~ s/\x{0080}/\x{20AC}/g; # Euro sign
#	    $valtext =~ s/\x{0085}/\x{2026}/g; # Horizontal ellipses
#	    $valtext =~ s/\x{0091}/\x{2018}/g; # Left single quotation mark
#	    $valtext =~ s/\x{0092}/\x{2019}/g; # Right single quotation mark
#	    $valtext =~ s/\x{0093}/\x{201C}/g; # Left double quotation mark
#	    $valtext =~ s/\x{0094}/\x{201D}/g; # Right double quotation mark
#	    $valtext =~ s/\x{0095}/\x{2022}/g; # bullet
#	    $valtext =~ s/\x{0096}/\x{2013}/g; # en dash
#	    $valtext =~ s/\x{0097}/\x{2014}/g; # em dash
#	    if( $valtext eq $decoded )
#	    {
#		next;
#	    }
#	    else
#	    {

# 		for( my $i=0; $i<length($valtext); $i++ )
# 		{
# 		    my $char1 = substr($valtext,$i,1);
# 		    my $char2 = substr($decoded,$i,1);
# 		    if( ord($char1) != ord($char2) )
# 		    {
# 			debug sprintf "Position %d, char %s(%4x)!=%s(%4x)",
# 			  $i, $char1, ord($char1), $char2, ord($char2);
# 			if( $char1 =~ /\pL/ ){ debug "  LETTER" };
# 			if( $char1 =~ /\pM/ ){ debug "  MARK" };
# 			if( $char1 =~ /\pZ/ ){ debug "  SEPARATOR" };
# 			if( $char1 =~ /\pS/ ){ debug "  SYMBOL" };
# 			if( $char1 =~ /\pN/ ){ debug "  NUMBER" };
# 			if( $char1 =~ /\pP/ ){ debug "  PUNCTUATION" };
# 			if( $char1 =~ /\p{Cc}/ ){ debug "  CONTROL" };
# 			if( $char1 =~ /\p{Cf}/ ){ debug "  FORMAT" };
# 			if( $char1 =~ /\p{Co}/ ){ debug "  PRIVATE" };
# 			if( $char1 =~ /\p{Cs}/ ){ debug "  SURROGATE" };
# 			if( $char1 =~ /\p{Cn}/ ){ debug "  UNASSIGNED" };
#
# 			last;
# 		    }
# 		}

#	    }


	    my $cleaned = valclean($decoded);

#	    debug "Cleaning text in $ver";
#
#	    $valtext =~ s/\r/\\r/g;
#	    $valtext =~ s/\n/\\n\n/g;
#	    $valtext =~ s/ /_/g;
#
#	    $decoded =~ s/\r/\\r/g;
#	    $decoded =~ s/\n/\\n\n/g;
#	    $decoded =~ s/ /_/g;
#

#	    debug "---\n$valtext\n---\n$decoded\n---";
#	    die;

	    $update_text_sth->execute($decoded, $cleaned, $ver);
	}
    }
    $text_sth-> finish;
    debug "Cleaned $cleaned";


#    debug "Committing";
#    $dbh->commit;
#    debug "Adding id's to all arcs";
#    $dbh->do("update arc set obj=nextval('node_seq') where obj is null");

    debug "COMMIT";
    $Para::Frame::REQ->done;
}

#######################################################################

1;
