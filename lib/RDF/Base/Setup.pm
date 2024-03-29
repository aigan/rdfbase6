package RDF::Base::Setup;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007-2021 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Setup

=head2 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;

use DBI;
use Carp qw( croak );
use DateTime::Format::Pg;
use Encode;                     # encode decode
use POSIX qw(setlocale LC_ALL);

use Para::Frame::Utils qw( debug datadump throw );
use Para::Frame::Time qw( now );

use RDF::Base;
use RDF::Base::Utils qw( valclean parse_propargs query_desig );
use RDF::Base::Constants;
use RDF::Base::Literal::Class;

our %NODE;
our @NODES;
our @ARC;
our %VALTYPE;
our %NOLABEL;
our %LITERAL;
our @LITERALS;

#
# For resetting an existing datbase use "setup_db clear"
#

sub setup_db
{
    my $dbix = $RDF::dbix;
    my $dbh = $dbix->dbh;
    my $now = DateTime::Format::Pg->format_datetime(now);
    $RDF::Base::IN_SETUP_DB = 1;


    my $old_debug = $Para::Frame::DEBUG;
    $Para::Frame::DEBUG = 0;

#    my $cnt = $dbix->get_lastval('node_seq');
#    debug "First node will have number $cnt";


    my $rb_root = $Para::Frame::CFG->{'rb_root'}
      or die "rb_root not given in CFG";

    if ( $dbix->table('arc') )  # setup_db clear
    {
        $dbh->do("drop table arc") or die;
        $dbh->do("drop table node") or die;
        $dbh->do("drop sequence node_seq") or die;
    }

    my $sql = "";
    open RBSCHEMA, "$rb_root/data/schema.sql" or die $!;
    while (<RBSCHEMA>)
    {
        $sql .= $_;
        if ( /;.*$/ )
        {
            $dbh->do($sql) or die "sql error";
            $sql = "";
        }
    }




    open RBDATA, "$rb_root/data/base.data" or die $!;
    while (<RBDATA>)
    {
        chomp;
        last if $_ eq 'NODES';
    }

    $dbh->do("delete from arc") or die;
    $dbh->do("delete from node") or die;
    $dbh->do("select setval('node_seq',1,false)");


    debug "Reading Nodes";
    while (<RBDATA>)
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
    while (<RBDATA>)
    {
        chomp;
        next unless $_;
        last if $_ eq 'EOF';

        if ( /^LITERALS/ )
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

        if ( $is_literal )
        {
            $LITERAL{$subj} = [$obj];
            push @LITERALS, $subj;

            if ( $LITERAL{$obj} )
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

            unless ( $NODE{$label} )
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

        for ( my $i=1; $i<= $#$scofs; $i++ )
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
        if ( $rec->{'pred'} eq 'range' )
        {
            my $pred = $rec->{'subj'};
            my $valtype_name = $rec->{'obj'};
            my $valtype = $NODE{$valtype_name}{'node'};
            $VALTYPE{$pred} = $valtype;
            debug "Valtype $pred = $valtype";
        }
    }

    debug "Adding arcs";
    my $source = $NODE{'rdfbase'}{'node'};
    my $read_access = $NODE{'public'}{'node'};
    my $write_access = $NODE{'contentadmin_group'}{'node'};
    my $sth_arc = $dbh->prepare("insert into arc (id,ver,subj,pred,source,active,indirect,implicit,submitted,read_access,write_access,created,created_by,updated,activated,activated_by,valtype,obj,valtext,valclean,valbin,valfloat) values (?,?,?,?,?,'t','f','f','f',?,?,?,?,?,?,?,?,?,?,?,?,?)") or die;
    foreach my $rec ( @ARC )
    {
        my $pred_name = $rec->{'pred'};
        my $coltype_num = $NODE{$pred_name}{'pred_coltype'} or die "No coltype given for pred $pred_name ".datadump($rec);
        my $coltype = $RDF::Base::Literal::Class::COLTYPE_num2name{$coltype_num} or die "Coltype $coltype_num not found";
        my $obj_in = $rec->{'obj'};
        my $value;
        if ( $obj_in )
        {
            if ( $obj_in =~ /^\d+$/ )
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
        if ( $subj_in =~ /^\d+$/ )
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
        my( $obj, $valtext, $valclean, $valbin, $valfloat );

        if ( $coltype eq 'obj' )
        {
            $obj = $value;
        }
        elsif ( $coltype eq 'valtext' )
        {
            $valtext = $value;
            $valclean = valclean( $value );
        }
        elsif ( $coltype eq 'valbin' )
        {
            $valbin = $value;
        }
        elsif ( $coltype eq 'valfloat' )
        {
            $valfloat = $value;
        }
        else
        {
            die "$coltype not handled";
        }

        $sth_arc->execute($id, $ver, $subj, $pred, $source, $read_access, $write_access, $now, $root, $now, $now, $root, $valtype, $obj, $valtext, $valclean, $valbin, $valfloat) or die;
    }

    $dbh->commit;
    $Para::Frame::DEBUG = $old_debug;
    $RDF::Base::VACUUM_ALL = 1; # For not vacuuming recursively


    # Initialization of constants and valtypes
    RDF::Base::Literal::Class->on_startup();
    RDF::Base::Resource->on_startup();
    RDF::Base::Constants->on_startup();

    my $root_node = RDF::Base::Resource->get_by_id( $root );
    debug "Setting bg_user_code to $root";
    $Para::Frame::CFG->{'bg_user_code'} = sub{ $root_node };


    my $req = Para::Frame::Request->new_bgrequest();

    debug "Infering arcs";

    my $sth_arc_list = $dbh->prepare("select * from arc order by ver");
    $sth_arc_list->execute();
    my @arc_recs;
    while ( my $arc_rec = $sth_arc_list->fetchrow_hashref )
    {
        push @arc_recs, $arc_rec;
    }
    $sth_arc_list->finish;

    foreach my $arc_rec (@arc_recs)
    {
        my $arc = RDF::Base::Arc->get_by_rec_and_register($arc_rec);
#	debug "  ".$arc->sysdesig;
        $arc->create_check;
    }

    $dbh->commit;

    debug "Initiating constants again";

    RDF::Base::Constants->on_startup;
    $RDF::Base::IN_STARTUP = 0;

    debug "Done!";

    return 1;
}


##############################################################################

sub convert_valuenodes
{
    my $dbix = $RDF::dbix;
    my $dbh = $dbix->dbh;
    my $req = Para::Frame::Request->new_bgrequest();
    my $now_db = DateTime::Format::Pg->format_datetime(now);
    my $R = RDF::Base->Resource;
    my $C = RDF::Base->Constants;

    print "\nCONVERTING VALUENODES\n\n";

#    my $arclist = $dbix->select_list("from arc where pred=4 order by ver desc");

    my @REMOVE;
    my @CONVERT;
    my %VNODE;


    my $dupsubjlist = $dbix->select_list("select distinct subj from arc where pred=4 and active is true group by subj having count(pred)>1 order by subj desc");
    debug sprintf "Got %d subjs with duplicate value arcs", $dupsubjlist->size;
    my( $dupsubjrec, $dserror ) = $dupsubjlist->get_first;
    while (! $dserror )
    {
        my $node = $R->get($dupsubjrec->{'subj'});

        debug $node->sysdesig;

        # Keeps the last value arc
        my $varcs = $node->arc_list('value')->sorted('id');
        my( $arc, $aerr ) = $varcs->get_first;
        while (!$aerr )
        {
            if ( $varcs->last )
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
        }
        ;
    }
    continue
    {
        ( $dupsubjrec, $dserror ) = $dupsubjlist->get_next;
    }
    ;


    my $arclist = $dbix->select_list("from arc where pred=4 order by ver desc");

    debug sprintf "Sorting %d arcs", $arclist->size;

    my $update_sth = $dbh->prepare("update arc set valfloat=?, valdate=?, valtext=?, valclean=?, valtype=?, activated=?, activated_by=?, updated=? where ver=?") or die;
    my $remove_sth = $dbh->prepare("delete from arc where ver=?");
    my $null_replaces = $dbh->prepare("update arc set replaces=null where replaces=?");

    my( $rec, $error ) = $arclist->get_first;
    while (! $error )
    {
        unless( $arclist->count % 1000 )
        {
            debug sprintf "%5d sorted", $arclist->count;
#	    last if $arclist->count == 100;
        }


        my $arc = RDF::Base::Arc->get_by_rec($rec);

#	debug $arc->sysdesig;

        if (not $arc->active)
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
    }
    ;

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

        if ( $coltype eq 'valfloat' )
        {
            $valfloat = $value;
        }
        elsif ( $coltype eq 'valdate' )
        {
            $valdate = DateTime::Format::Pg->format_datetime($value);
        }
        elsif ( $coltype eq 'valtext' )
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

    if ( $R->find({label=>'value'})->size )
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
    while ( my $rec = $obj_arcs_sth->fetchrow_hashref )
    {
        unless( ++$obj_arc_cnt % 1000 )
        {
            debug sprintf "%6d Total updated %5d",
              $obj_arc_cnt, $valtype_updated_cnt;
            $dbh->commit;
        }

        my $pred = RDF::Base::Pred->get($rec->{'pred'});
        next unless $pred->objtype;

        my $old_valtype_id = $rec->{'valtype'};

        my $obj = $R->get($rec->{'obj'});
        my $new_valtype_id = $obj->this_valtype->id;
        if ( $new_valtype_id != $old_valtype_id )
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
    while ( my $rec = $text_sth->fetchrow_hashref )
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
        if ( $valtext =~ /Ã./ )
        {
            my $res;
            while ( length $decoded )
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
        $decoded =~ s/^\s*\n//;         # Leading empty lines
        $decoded =~ s/\n\s+$/\n/;       # Trailing empty lines

        # Remove invisible characters, other than LF
        $decoded =~ s/(?!\n)\p{Other}//g;

        if ( $valtext ne $decoded)
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

##############################################################################

sub dbconnect
{
    my %db;
    if ( open RB_DB, '<', $::CFG->{'rb_root'}."/.rb_dbconnect" )
    {
        while (<RB_DB>)
        {
            /(\w+)=(.*)\n/;
            $db{$1}=$2;
        }
    }

    $db{pass} = undef if $db{pass} eq '-';

    return [ sprintf( "dbi:Pg:dbname=%s;host=%s;port=%d",
                      $db{name},
                      $db{host},
                      $db{port},
                    ),
             $db{user}, $db{pass},
           ];
}


##############################################################################

#
# Set $ARGV[0] to 'upgrade' for upgrading constants. See RDF::Base::Constants
#
# Set $ARGV[0] to 'vacuum_text' for valtext arcs
#
# Set $ARGV[0] to 'vacuum_all' for vacuuming all nodes
#

sub upgrade_db
{
    my $C = RDF::Base->Constants;
    my $R = RDF::Base->Resource;
    my( $args, $arclim, $res ) = parse_propargs({
                                                 activate_new_arcs => 1,
                                                 arclim => ['active'],
                                                 unique_arcs_prio => ['active'],
                                                });

    # A new clean setup should bring version up to current on its own
    return if $RDF::Base::IN_SETUP_DB;
    $RDF::Base::IN_SETUP_DB = 1;

    ### PRE 0 DB setup
    $R->find_set({label => 'rdfbase'});
    my $int = $R->get_by_label('int',{nonfatal=>1}) || $R->get({scof=>$C->get('valfloat'),name=>'int'});
    my $rb = $C->get('rdfbase');
    my $pred = $C->get('predicate');

    unless ( $R->find({label => 'has_version'}) )
    {
        my $req = Para::Frame::Request->new_bgrequest();
        $R->find_set({
                      label       => 'has_version',
                      is          => $pred,
                      range       => $int,
                     }, $args);
        $req->done;
    }

    my $ver = $rb->has_version->literal || 0;
    debug "RDF-Base Upgrade";

    if ( $ver < 1 )
    {
        my $req = Para::Frame::Request->new_bgrequest();
        my $class = $C->get('class');
        my $chbpm = 'class_handled_by_perl_module';

        my $term = $R->find_set({label => 'term'});

        $term->update({scof => $C->get('valtext')},$args);

        $C->get('name')->update({range=>$term},$args);
        RDF::Base::Resource->commit(); # Heavy update

        $C->get('name_short')->update({range => $term},$args);
        RDF::Base::Resource->commit();

        $int->update({label => 'int'}, $args);


        my $tr_module =
          $R->find_set({
                        code => 'RDF::Base::Translatable',
                        is   => 'class_perl_module',
                       }, $args);

        my $tr = $R->find_set({label => 'translatable'}, $args)
          ->update({
                    is             => $class,
                    $chbpm         => $tr_module,
                   }, $args);


        $R->find_set({label => 'has_translation'},$args)
          ->update({
                    label => 'has_translation',
                    is => $pred,
                    range => $C->get('text'),
                   },$args);

        $C->get('has_translation')->update({'domain' => $tr},$args);

        $R->find_set({label => 'translation_label'}, $args );

        $C->get('translation_label')->update({
                                              'domain' => $tr,
                                              'range' => $term,
                                              is => $pred,
                                             },$args);

        my $trl = $R->find({translation_label_exist=>1});
        while ( my $trn = $trl->get_next_nos )
        {
            $trn->update({is=>$tr},$args);
        }

        $rb->update({ has_version => 1 },$args);
        Para::Frame->flag_restart(); # Added constants
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 2 )
    {
        my $req = Para::Frame::Request->new_bgrequest();
        my $class = $C->get('class');
        my $wt = $C->get('website_text')->
          update({
                  is => $class,
                  class_form_url => "rb/translation/html.tt",
                 },$args);
        $C->get('webpage')->
          update({ is => $class }, $args);

        my $hhc = $R->find_set({
                                label       => 'has_html_content',
                                is          => 'predicate',
                                domain      => $wt,
                                range       => $C->get('text_html'),
                               }, $args);

        $hhc->update({description=>'HTML box of content on a web page'},$args);

        $R->find_set({label       => 'has_member'},$args)
          ->update({
                    label       => 'has_member',
                    is          => 'predicate',
                    range       => $C->get('resource'),
                   }, $args);

        my $wtl = $wt->revlist('is');
        while ( my $wtn = $wtl->get_next_nos )
        {
            my $code = $wtn->first_prop('code')->plain or next;
            next unless $code =~ /\@/;
            $code =~ s/\@/#/;
            $wtn->update({code=>$code},$args);
        }

        $rb->update({ has_version => 2 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 3 )
    {
        my $req = Para::Frame::Request->new_bgrequest();
        my $pred = $C->get('predicate');
        my $int = $C->get('int');
        my $bool = $C->get('bool');

        foreach my $label (qw( domain_card_min domain_card_max
                               range_card_min range_card_max
                            ))
        {
            $R->find_set({
                          label       => $label,
                          is          => $pred,
                          domain      => $pred,
                          range       => $int,
                         }, $args);
        }

        $R->find_set({
                      label       => 'literal_compare_clean',
                      is          => $pred,
                      domain      => $pred,
                      range       => $bool,
                     }, $args);


        # AD range_card_max
        foreach my $label (qw( domain range domain_scof range_scof pred_1 pred_2 pred_3 weight class_handled_by_perl_module url_part site_code has_version translation_label domain_card_min domain_card_max range_card_min range_card_max literal_compare_clean ))
        {
            $C->get($label)->update({range_card_max => 1},$args);
        }


        # AD literal_compare_clean
        foreach my $label (qw( name ))
        {
            $C->get($label)->update({literal_compare_clean => 1},$args);
        }



        $rb->update({ has_version => 3 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 4 )
    {
        debug "**** UPGRADING Rit -> RDF";
        my $dbix = $RDF::dbix;
        my $dbh = $dbix->dbh;

        my $sth_rit2rdf = $dbh->prepare("update arc set valtext=regexp_replace(valtext, '^Rit::Base', 'RDF::Base') where valtext like 'Rit::Base%'") or die;

        $sth_rit2rdf->execute;

        my $req = Para::Frame::Request->new_bgrequest();

        $R->find({code_begins => 'Rit::Base'}, $args )->vacuum_node($args);

        $rb->update({ has_version => 4 },$args);
        $res->autocommit;
        $req->done;
        Para::Frame->flag_restart();
    }

    if ( $ver < 5 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $c_is = $C->get('is');
        my $c_class = $C->get('class');

        my $ia = $R->find_set({label => 'instances_are'},$args)
          ->update({
                    domain => $c_class,
                    range => $c_class,
                    is => $C->get('predicate'),
                    range_card_max => 1,
                   },$args);

        RDF::Base::Rule->create($c_is, $ia, $c_is, 0 );

        $rb->update({ has_version => 5 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 6 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $pred = $C->get('predicate');

        $R->find_set({label => 'has_cyc_id'},$args)
          ->update({
                    range => $C->get('term'),
                    is => $pred,
                    range_card_max => 1,
                   },$args);

        $R->find_set({label => 'has_wikipedia_id'},$args)
          ->update({
                    range => $C->get('term'),
                    is => $pred,
                    range_card_max => 1,
                   },$args);


        $C->get('login_account')
          ->update({
                    has_cyc_id => 'Cyclist',
                   },$args);

        $C->get('admin_comment')
          ->update({
                    has_cyc_id => 'comment',
                   },$args);

        $C->get('swedish')
          ->update({
                    has_cyc_id => 'SwedishLanguage',
                    has_wikipedia_id => 'Swedish_language',
                   },$args);

        $C->get('english')
          ->update({
                    has_cyc_id => 'EnglishLanguage',
                    has_wikipedia_id => 'English_language',
                   },$args);

        $C->get('language')
          ->update({
                    has_cyc_id => 'NaturalLanguage',
                    has_wikipedia_id => 'Language',
                   },$args);

        $C->get('intelligent_agent')
          ->update({
                    has_cyc_id => 'IntelligentAgent',
                   },$args);

        $C->get('phone_number')
          ->update({
                    has_cyc_id => 'PhoneNumber',
                    has_wikipedia_id => 'Telephone_number',
                   },$args);


        my $c_is = $C->get('is');
        my $c_scof = $C->get('scof');
        my $c_class = $C->get('class');

        my $iscof = $R->find_set({label => 'instances_scof'},$args)
          ->update({
                    domain => $c_class,
                    range => $c_class,
                    is => $C->get('predicate'),
                    range_card_max => 1,
                   },$args);

        RDF::Base::Rule->create($c_is, $iscof, $c_scof, 0 );

        my $sscof = $R->find_set({label => 'subclasses_scof'},$args)
          ->update({
                    domain => $c_class,
                    range => $c_class,
                    is => $C->get('predicate'),
                    range_card_max => 1,
                   },$args);

        RDF::Base::Rule->create($c_scof, $sscof, $c_scof, 0 );

        $rb->update({ has_version => 6 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 7 )
    {
        my $req = Para::Frame::Request->new_bgrequest();
        $C->get('class_handled_by_perl_module')->arc('range_card_max')->remove($args);

        $R->find_set({label => 'has_url'}, $args)
          ->update({
                    is => $pred,
                    admin_comment => 'A salient URL of the thing',
                    has_cyc_id => 'salientURL',
                    range => $C->get('url'),
                   }, $args);


        $rb->update({ has_version => 7 },$args);
        $res->autocommit;
        $req->done;
    }


    if ( $ver < 8 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $C_class = $C->get('class');
        my $C_predicate = $C->get('predicate');
        my $C_email = $C->get('email');

        my $m_ea = $R->find_set({code => 'RDF::Base::Email::Address',
                                 is=>$C->get('class_perl_module')},$args);

        my $c_url = $R->find_set({label => 'url_holder'},$args)
          ->update({
                    is => $C_class,
                    has_cyc_id => 'UniformResourceLocator',
                    has_wikipedia_id => 'Uniform_resource_locator',
                   },$args);

        my $c_ea = $R->find_set({label => 'email_address_holder'},$args)
          ->update({
                    scof => $c_url,
                    has_cyc_id => 'EMailAddress',
                    class_handled_by_perl_module => $m_ea,
                   },$args);

        $R->find_set({label => 'has_email_address_holder'},$args)
          ->update({
                    domain => $C->get('intelligent_agent'),
                    range => $c_ea,
                    is => $C_predicate,
                   },$args);

        $R->find_set({label => 'has_contact_email_address_holder'},$args)
          ->update({
                    domain => $C->get('intelligent_agent'),
                    range => $c_ea,
                    is => $C_predicate,
                   },$args);

        $R->find_set({label => 'ea_original'},$args)
          ->update({
                    domain => $c_ea,
                    range => $C->get('email_address'),
                    is => $C_predicate,
                    range_card_max => 1,
                   },$args);

        my $m_d = $R->find_set({code => 'RDF::Base::Domain',
                                is=>$C->get('class_perl_module')},$args);

        my $c_d = $R->find_set({label => 'internet_domain'},$args)
          ->update({
                    scof => $c_url,
                    has_cyc_id => 'DomainName',
                    has_wikipedia_id => 'Domain_name',
                    class_handled_by_perl_module => $m_d,
                   },$args);

        my $m_ed = $R->find_set({code => 'RDF::Base::Email::Deliverability',
                                 is=>$C->get('class_perl_module')},$args);

        my $c_ed = $R->find_set({label => 'email_deliverability'},$args)
          ->update({
                    is => $C_class,
                    class_handled_by_perl_module => $m_ed,
                   },$args);

        $R->find_set({label => 'has_email_deliverability'},$args)
          ->update({
                    domain => $c_url,
                    range => $c_ed,
                    is => $C_predicate,
                   },$args);

        $R->find_set({label => 'in_internet_domain'},$args)
          ->update({
                    range => $c_d,
                    is => $C_predicate,
                    range_card_max => 1,
                   },$args);

        my $c_dsn = $R->find_set({label => 'dsn_email'},$args)
          ->update({
                    is => $C_class,
                    has_wikipedia_id => 'Bounce_message',
                    scof => $C_email,
                   },$args);

        $R->find_set({label => 'dsn_for_address'},$args)
          ->update({
                    domain => $c_dsn,
                    range => $c_ea,
                    is => $C_predicate,
                   },$args);

        my $c_ed_non = $R->find_set({label => 'ed_non_deliverable'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        my $c_ed_dlv = $R->find_set({label => 'ed_deliverable'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        $R->find_set({label => 'ed_opening'},$args)
          ->update({
                    scof => $c_ed_dlv,
                   },$args);

        $R->find_set({label => 'ed_interacting'},$args)
          ->update({
                    scof => $c_ed_dlv,
                   },$args);

        $R->find_set({label => 'ed_queuing'},$args)
          ->update({
                    scof => $c_ed_dlv,
                   },$args);

        $R->find_set({label => 'ed_agent_away'},$args)
          ->update({
                    scof => $c_ed_dlv,
                   },$args);

        $R->find_set({label => 'ed_address_changed'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        $R->find_set({label => 'ed_pending_action'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        $R->find_set({label => 'ed_paranoia'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        $R->find_set({label => 'ed_delayed'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        $R->find_set({label => 'ed_unclassified'},$args)
          ->update({
                    is => $c_ed,
                   },$args);

        $R->find_set({label => 'ed_mailbox_unavailible'},$args)
          ->update({
                    scof => $c_ed_non,
                   },$args);

        $R->find_set({label => 'ed_address_error'},$args)
          ->update({
                    scof => $c_ed_non,
                   },$args);

        $R->find_set({label => 'ed_domain_error'},$args)
          ->update({
                    scof => $c_ed_non,
                   },$args);


        $rb->update({ has_version => 8 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 9 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $C_class = $C->get('class');
        my $C_predicate = $C->get('predicate');

        $R->find_set({label => 'dsn_date'},$args)
          ->update({
                    domain => $C->get('arc'),
                    range => $C->get('date'),
                    is => $C_predicate,
                    admin_comment => "The date of the Delivery Status Notification",
                   },$args);

        $R->find_set({label => 'dsn_date_availible'},$args)
          ->update({
                    domain => $C->get('arc'),
                    range => $C->get('date'),
                    is => $C_predicate,
                    admin_comment => "The date for the person coming back to work according to the Delivery Status Notification",
                   },$args);

        $R->find_set({label => 'ed_nonhuman'},$args)
          ->update({
                    scof => $C->get('ed_non_deliverable'),
                   },$args);

        RDF::Base::Rule->create( 'has_email_deliverability',
                                 'scof',
                                 'has_email_deliverability',
                               );



        $rb->update({ has_version => 9 },$args);
        $res->autocommit;
        $req->done;
    }

    if( $ver < 10 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $access = $R->find_set({label => 'acl_access'},$args)
          ->update({
                    is => $C->get('class'),
                    has_cyc_id => 'AccessingAnIBT',
                    admin_comment => "An action by which an agent accesses the content of some instance(s) of InformationBearingThing. Cyc differs between FilePermission for the specific permission types and FileOperation for the activities those permissions allows. This class denotes the activity rather than the actual permission type. See http://www.w3.org/wiki/WebAccessControl",
                   },$args);

        $R->find_set({label => 'acl_append'},$args)
          ->update({
                    scof => $access,
                    admin_comment => "Append accesses are specific write access which only add information, and do not remove information.
For text files, for example, append access allows bytes to be added onto the end of the file.
For RDF graphs, Append access allows adds triples to the graph but does not remove any.
Append access is useful for dropbox functionality.
Dropbox can be used for link notification, which the information added is a notification that a some link has been made elsewhere relevant to the given resource.
http://www.w3.org/ns/auth/acl#Append",
                   },$args);

        $R->find_set({label => 'acl_control'},$args)
          ->update({
                    scof => $access,
                    admin_comment => "Allows read/write access to the ACL for the resource(s). Might be better implemented by specifying access to the node talking about the access of the resource.
http://www.w3.org/ns/auth/acl#Control",
                   },$args);

        $R->find_set({label => 'acl_read'},$args)
          ->update({
                    scof => $access,
                    admin_comment => "The class of read operations.
http://www.w3.org/ns/auth/acl#Read",
                   },$args);

        $R->find_set({label => 'acl_write'},$args)
          ->update({
                    scof => $access,
                    admin_comment => "The class of write operations.
http://www.w3.org/ns/auth/acl#Write",
                   },$args);


        my $chbpm = 'class_handled_by_perl_module';
        my $class_module =
          $R->find_set({
                        code => 'RDF::Base::Class',
                        is   => 'class_perl_module',
                       }, $args);
        $C->get('class')->update({ $chbpm => $class_module }, $args);


        $rb->update({ has_version => 10 },$args);
        $res->autocommit;
        $req->done;
    }

    if( $ver < 11 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        $R->find_set({label => 'exclusive_domain_holder'},$args)
          ->update({
                    domain => $C->get('internet_domain'),
                    range => $C->get('intelligent_agent'),
                    range_card_max => 1,
                    is => $C->get('predicate'),
                    admin_comment => "The only agent that uses this domain. Engough to derive connections for web- and email- addresses.",
                   },$args);

        $R->find_set({label => 'underspecified'},$args)
          ->update({
                    scof => $C->get('class'),
                    admin_comment => "See related cyc node UnderspecifiedCollectionType",
                   },$args);

        $R->find_set({label => 'email'},$args)
          ->update({
                    has_cyc_id => 'EMailMessage',
                   },$args);

        $R->find_set({label => 'email_spam'},$args)
          ->update({
                    has_cyc_id => 'Spam-UnsolicitedEMail',
                    has_wikipedia_id => 'Email_spam',
                    scof => $C->get('email'),
                   },$args);

        $rb->update({ has_version => 11 },$args);
        $res->autocommit;
        $req->done;
    }

    if( $ver < 12 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        $R->find_set({label => 'has_custom_data'},$args)
          ->update({
                    range => $C->get('text_large'),
                    is => $C->get('predicate'),
                    admin_comment => "Unsearchable custom data outside the node graph",
                   },$args);

        $R->find_set({label => 'json_data'},$args)
          ->update({
                    scof => $C->get('text_large'),
                   },$args);

        $rb->update({ has_version => 12 },$args);
        $res->autocommit;
        $req->done;
    }

    if( $ver < 13 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $class_module =
          $R->find_set({
                        code => 'RDF::Base::Literal::JSON',
                        is   => 'class_perl_module',
                       }, $args);

        $R->find_set({label => 'json_data'},$args)
          ->update({
                    class_handled_by_perl_module => $class_module,
                   },$args);

        $rb->update({ has_version => 13 },$args);
        $res->autocommit;
        $req->done;
    }

    if( $ver < 14 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        $R->find_set({label => 'class_list_url'},$args)
          ->update({
                    range => $C->get('url'),
                    is => $C->get('predicate'),
                    admin_comment => "URL from relative site root for the list of nodes of this class",
                   },$args);


        $rb->update({ has_version => 14 },$args);
        $res->autocommit;
        $req->done;
    }

    if( $ver < 15 )
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $C_predicate = $C->get('predicate');

        my $authorization = $R->find_set({label => 'acl_authorization'},$args)
          ->update({
                    is => $C->get('class'),
                    admin_comment => "An element of access control,
    allowing agent to agents access of some kind to resources or classes of resources. See http://www.w3.org/ns/auth/acl#Authorization",
                   },$args);

        $R->find_set({label => 'acl_access_to'},$args)
          ->update({
                    domain => $authorization,
                    range => $C->get('resource'),
                    is => $C_predicate,
                    admin_comment => "The information resource to which access is being granted. See http://www.w3.org/ns/auth/acl#accessTo",
                   },$args);

        $R->find_set({label => 'acl_mode'},$args)
          ->update({
                    domain => $authorization,
                    range => $C->get('acl_access'),
                    is => $C_predicate,
                    admin_comment => "A mode of access such as read or write. See http://www.w3.org/ns/auth/acl#mode",
                   },$args);

        $R->find_set({label => 'acl_agent'},$args)
          ->update({
                    domain => $authorization,
                    range => $C->get('intelligent_agent'),
                    is => $C_predicate,
                    admin_comment => "A person or social entity to being given the right. See http://www.w3.org/ns/auth/acl#agent",
                   },$args);


        $rb->update({ has_version => 15 },$args);
        $res->autocommit;
        $req->done;
    }


    if ( $ver < 16)
    {
        my $req = Para::Frame::Request->new_bgrequest();

        $R->find_set({label => 'working_on'},$args)
          ->update({
                    domain => $C->get('login_account'),
                    range => $C->get('resource'),
                    is => 'predicate',
                   },$args);


        $rb->update({ has_version => 16 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 17)
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $c_password = $R->get_by_label('password',{nonfatal=>1});
        unless( $c_password )
        {
            $c_password = $R->find_one({name=>'password',
                                        scof => $C->get('valtext')});

            my $pw_module =
              $R->find_set({
                            code => 'RDF::Base::Literal::Password',
                            is   => 'class_perl_module',
                           }, $args);
            $c_password->update({label => 'password',
                                 'class_handled_by_perl_module' => $pw_module,
                                }, $args);
        }

        # ... don't bother about older insecure passwords...
#        $C->get('has_password')->update({range_card_max => 1},$args);

        $R->find_set({label => 'has_secret'},$args)
          ->update({
                    is    => 'predicate',
                    range => $c_password,
                    range_card_max => 1,
                   }, $args);

        $R->find_set({label => 'has_password_hash'},$args)
          ->update({
                    is    => 'predicate',
                    domain => $C->get('login_account'),
                    range => $c_password,
                    range_card_max => 1,
                   }, $args);

        $rb->update({ has_version => 17 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 18)
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $cma = $R->find_set({label => 'content_management_access'},$args)
          ->update({
                    is => $C->get('system_access_right'),
                   },$args);

        $R->find_set({label => 'sysadmin_group'},$args);


        $rb->update({ has_version => 18 },$args);
        $res->autocommit;
        $req->done;
    }


    ### Moved 19 to 20 for redoing user vacuum

    if ( $ver < 20)
    {
        my $req = Para::Frame::Request->new_bgrequest();

        my $sag = $C->get('sysadmin_group');
        $sag->set_write_access( $sag );

        my $users = $R->find({has_access_right_exist=>1});
        while( my $user = $users->get_next_nos )
        {
            $user->vacuum_node;
        }

        $rb->update({ has_version => 20 },$args);
        $res->autocommit;
        $req->done;
    }

    if ( $ver < 21 )
    {
        my $req = Para::Frame::Request->new_bgrequest();


#        $rb->update({ has_version => 21 },$args);
        $res->autocommit;
        $req->done;
    }


#    if ( $ver < 20 )
#    {
#        my $req = Para::Frame::Request->new_bgrequest();
#
#        my $cma = $C->get('content_management_access');
#        my $users = $C->get('full_access')->revlist('has_access_right');
#        while( my $user = $users->get_next_nos )
#        {
#            next if $user->equals($C->get('root'));
#            $user->update({has_access_right=>$cma},$args);
#        }
#
##        $rb->update({ has_version => 20 },$args);
#        $res->autocommit;
#        $req->done;
#    }


    $ARGV[0] //= '';
    if ( $ARGV[0] eq 'vacuum_all' )
    {
        vacuum_all();
    }

    if ( $ARGV[0] eq 'vacuum_text' )
    {
        vacuum_text();
    }

}


##############################################################################

sub upgrade_tables
{
    my $dbix = $RDF::dbix;
    my $dbh = $dbix->dbh;

    my $ver = $dbix->select_record("from arc where active is true and subj=(select node from node where label='rdfbase')")->{valfloat};

    debug "RDF-Base DB version $ver";

    if( $ver < 13 )
    {
        ### Special namespace change from ritbase to rdfspace
        my( $ritbase_id ) = $dbh->selectrow_array("select node from node where label='ritbase'");
        if ( $ritbase_id )
        {
            $dbh->do("update node set label='rdfbase' where label='ritbase'");
            $dbh->do("update arc set valtext=regexp_replace(valtext, '^Rit::Base', 'RDF::Base') where valtext like 'Rit::Base%'");
            $dbh->commit;
        }
    }

    if( $ver < 18)
    {
			my( $cag ) = $dbh->selectrow_array("select node from node where label='contentadmin_group'");
			if( !$cag )
			{
				my $now = DateTime::Format::Pg->format_datetime(now);
				$dbh->do("insert into node (node, label, owned_by, created, created_by, updated, updated_by) select nextval('node_seq'), 'contentadmin_group', owned_by, ?, created_by, ?, updated_by from node where label = 'full_access'", undef, $now, $now);
				$dbh->commit;
			}
    }

}


##############################################################################

sub vacuum_all
{
    debug "\n\nVACUUMING ALL NODES\n\n";

    my $dbh =  $RDF::dbix->dbh;
    my $A = RDF::Base->Arc;
    my $R = RDF::Base->Resource;

    my $req = Para::Frame::Request->new_bgrequest();
    my( $args, $arclim, $res ) = parse_propargs('solid');
    $req->user->set_default_propargs({
                                      %$args,
                                      activate_new_arcs => 1,
                                     });

    $RDF::Base::VACUUM_ALL = 1;

    my $start = $ARGV[1] || 0;
    my $vnodes_sth = $dbh->prepare("select distinct subj from arc where active is true and subj >= $start order by subj asc");
    $vnodes_sth->execute;

    my $obj_node_total = $vnodes_sth->rows;
    debug sprintf "Vacuuming %d nodes", $obj_node_total;
    my $obj_node_cnt = 0;
    my $time = time();
    while ( my $rec = $vnodes_sth->fetchrow_hashref )
    {
        ++$obj_node_cnt;
        my $node = $R->get($rec->{subj});
        eval
        {
            # Giving id for traceback debugging
            $node->vacuum_node($args,$node->id);
        };
        if ( my $err = catch($@) )
        {
            my $part = $req->result->error($err);
            $part->prefix_message( "During vacuum of ".$node->id );
            debug $part->as_string;
        }

        if ( $time+5 < time() )
        {
            $time = time();
            $R->commit;
            $RDF::dbix->commit;
            debug sprintf "%6d / %6d VACUUMED %d",$obj_node_cnt, $obj_node_total, $node->id;
        }

#        die; # TEST
    }

    # To clean by hand:
    # 5922849: Eva Södervall som...


    $RDF::Base::VACUUM_ALL = 0;

    $res->autocommit;
    $Para::Frame::REQ->done;
    $req->user->set_default_propargs(undef);
}

##############################################################################

sub vacuum_text
{
    debug "\n\nCLEANING UP TEXTS\n";

    my $dbix = $RDF::dbix;
    my $dbh = $dbix->dbh;
    my $R = RDF::Base->Resource;

		#debug "locale " . setlocale(LC_ALL);


		my $update_text_sth = $dbh->prepare("update arc set valtext=?, valclean=? where ver=?") or die;

    my $start = $ARGV[1] || 0;

    my $text_sth = $dbh->prepare("select ver, valtext, valclean from arc where valtext is not null and active is true and ver >= $start order by ver asc");
    $text_sth->execute;
    my $cleaned = 0;
    my $text_cnt = 0;
		my $total = $text_sth->rows;
		my $time = time();
		debug $total." records";
    while ( my $rec = $text_sth->fetchrow_hashref )
    {
        my $ver = $rec->{'ver'};

        if ( $time+5 < time() )
        {
            $time = time();
            $R->commit;
            $RDF::dbix->commit;
            debug sprintf "%7d / %7d at arc ver %8d cleaned %5d",$text_cnt, $total, $ver, $cleaned;
        }


        my $valtext = $rec->{'valtext'};
        my $valclean = $rec->{'valclean'};
        my $decoded = $valtext;
				$text_cnt ++;

#        # Cleaning up UTF8...
#        if ( $valtext =~ /Ã./ )
#        {
#            my $res;
#            while ( length $decoded )
#            {
#                $res .= decode("UTF-8", $decoded, Encode::FB_QUIET);
#                $res .= substr($decoded, 0, 1, "") if length $decoded;
#            }
#            $decoded = $res;
#        }
#        else
#        {
#            utf8::upgrade( $decoded );
#        }

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
        $decoded =~ s/^\s*\n//;         # Leading empty lines
        $decoded =~ s/\n\s+$/\n/;       # Trailing empty lines

        # Remove invisible characters, other than LF
        $decoded =~ s/(?!\n)\p{Other}//g;

        my $newclean = valclean($decoded);

        if ( ($valtext ne $decoded) or ($valclean ne $newclean))
        {
            $cleaned++;

            if($valtext ne $decoded)
            {
                debug "Text '$valtext' ---> '$decoded'";
            }
            else
            {
#                debug "Clean '$valclean' ---> '$newclean'";
            }
            #next;

            $update_text_sth->execute($decoded, $newclean, $ver);
        }
    }

    $text_sth-> finish;

    debug "Cleaned $cleaned arcs";
}

##############################################################################

1;
