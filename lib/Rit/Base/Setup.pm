#  $Id$  -*-cperl-*-
package Rit::Base::Setup;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Database Setup
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2007 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Guides::Upgrade

=head2 DESCRIPTION

See also Rit::Base::Action::setup_db

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

use Para::Frame::Utils qw( debug datadump throw );
use Para::Frame::Time qw( now );

use Rit::Base;
use Rit::Base::Utils qw( valclean );
use Rit::Base::Constants;

our %NODE;
our @ARC;
our %VALTYPE;
our %NOLABEL;

sub setup_db
{
    my $dbix = $Rit::dbix;
    my $dbh = $dbix->dbh;
    my $now = DateTime::Format::Pg->format_datetime(now);


#    my $cnt = $dbix->get_lastval('node_seq');
#    debug "First node will have number $cnt";


    my $rb_root = $Para::Frame::CFG->{'rb_root'} or die "rb_root not given in CFG";
    open RBDATA, "$rb_root/data/base.data" or die $!;
    while(<RBDATA>)
    {
	chomp;
	last if $_ eq 'NODES';
    }

    $dbh->do("delete from arc") or die;
    $dbh->do("delete from node") or die;
    $dbh->do("select setval('node_seq',1,false)");


    print "Reading Nodes\n";
    while(<RBDATA>)
    {
	chomp;
	next unless $_;
	last if $_ eq 'ARCS';

	my( $label, $pred_coltype ) = split /\t/, $_;

	my $id = $dbix->get_nextval('node_seq');

	$NODE{$label} =
	{
	 label => $label,
	 pred_coltype => $pred_coltype,
	 node => $id,
	};
    }

    print "Reading Arcs\n";
    while(<RBDATA>)
    {
	chomp;
	next unless $_;
	last if $_ eq 'EOF';

	my( $subj, $pred, $obj, $value ) = split /\t/, $_;

	push @ARC,
	{
	 subj => $subj,
	 pred => $pred,
	 obj => $obj,
	 value => $value,
	};

	foreach my $label ($subj, $pred, $obj)
	{
	    next unless $label;
	    next if $label =~ /^\d+$/;

	    unless( $NODE{$label} )
	    {
		my $id = $dbix->get_nextval('node_seq');
		$NODE{$label} =
		{
		 label => $label,
		 node => $id,
		};
	    }
	}

    }

    close RBDATA;

    print "Adding nodes\n";
    my $root = $NODE{'root'}{'node'};
    my $sth_node = $dbh->prepare('insert into node (node,label,owned_by,pred_coltype,created,created_by,updated,updated_by) values (?,?,?,?,?,?,?,?)') or die;

    foreach my $rec ( values %NODE )
    {
	my $node = $rec->{'node'};
	my $label = $rec->{'label'};
	my $owned_by = $root;
	my $pred_coltype = $rec->{'pred_coltype'} || undef;
	my $created = $now;
	my $created_by = $root;
	my $updated = $now;
	my $updated_by = $root;

	$sth_node->execute($node, $label, $owned_by, $pred_coltype, $created, $created_by, $updated, $updated_by);
    }

    print "Extracting valtypes\n";
    foreach my $rec ( @ARC )
    {
	if( $rec->{'pred'} eq 'range' )
	{
	    my $pred = $rec->{'subj'};
	    my $valtype_name = $rec->{'obj'};
	    my $valtype = $NODE{$valtype_name}{'node'};
	    $VALTYPE{$pred} = $valtype;
	    print "Valtype $pred = $valtype\n";
	}
    }

    print "Adding arcs\n";
    my $source = $NODE{'ritbase'}{'node'};
    my $read_access = $NODE{'public'}{'node'};
    my $write_access = $NODE{'sysadmin_group'}{'node'};
    my $sth_arc = $dbh->prepare("insert into arc (id,ver,subj,pred,source,active,indirect,implicit,submitted,read_access,write_access,created,created_by,updated,activated,activated_by,valtype,obj,valtext,valclean) values (?,?,?,?,?,'t','f','f','f',?,?,?,?,?,?,?,?,?,?,?)") or die;
    foreach my $rec ( @ARC )
    {
	my $pred_name = $rec->{'pred'};
	my $coltype_num = $NODE{$pred_name}{'pred_coltype'} or die "No coltype given for pred $pred_name";
	my $coltype = $Rit::Base::COLTYPE_num2name{$coltype_num} or die "Coltype $coltype_num not found";
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
	my( $obj, $valtext, $valclean );

	if( $coltype eq 'obj' )
	{
	    $obj = $value;
	}
	elsif( $coltype eq 'valtext' )
	{
	    $valtext = $value;
	    $valclean = valclean( $value );
	}
	else
	{
	    die "$coltype not handled";
	}

	$sth_arc->execute($id, $ver, $subj, $pred, $source, $read_access, $write_access, $now, $root, $now, $now, $root, $valtype, $obj, $valtext, $valclean) or die;
    }

    $dbh->commit;

    print "Initiating constants\n";

    Rit::Base::Constants->init;

    my $req = Para::Frame::Request->new_bgrequest();

    print "Infering arcs\n";

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
	my $arc = Rit::Base::Arc->get_by_rec_and_register($arc_rec);
	$arc->create_check;
    }

    $dbh->commit;

    print "Initiating constants again\n";

    Rit::Base::Constants->init;
    $Rit::Base::IN_STARTUP = 0;

    print "Done!\n";

    return;
}

1;
