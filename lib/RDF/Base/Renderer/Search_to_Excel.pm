package RDF::Base::Renderer::Search_to_Excel;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;
use utf8;
use base 'Para::Frame::Renderer::Custom';

use POSIX qw( locale_h );
use Spreadsheet::WriteExcel;
#use Carp qw( cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw );
use Para::Frame::L10N qw( loc );


##############################################################################

sub render_output
{
    my( $rend ) = @_;

    setlocale(LC_NUMERIC, "C");

    my $R = RDF::Base->Resource;
    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    $req->note("Rendering spreadsheet");

#    cluck "rendering";

    open my $fh, '>', \my $str or die "Failed to open filehandle: $!";
    my $workbook  = Spreadsheet::WriteExcel->new($fh);
    my $sheet = $workbook->add_worksheet();
    $sheet->keep_leading_zeros(1);

    my $row = 0;

    my $rows = $req->session->search_collection->result->sorted('desig');
    my $rows_count = $rows->size;
    $req->note("Writing ".$rows_count." rows");

    my @preds = $q->param('list_pred');
    my @pred_names;
    if( $q->param('list_pred_name') )
    {
        @pred_names = $q->param('list_pred_name');
    }
    else
    {
        @pred_names = $q->param('list_pred');
    }



    $sheet->write($row++, 0, \@pred_names);

    debug "Wrote header";

    my( $item, $error ) = $rows->get_first;
    while(! $error )
    {
#	debug "Writing item ".$item->sysdesig;
	my @item_row;
	foreach my $pred (@preds)
	{
#	    debug "  parsing $pred";

	    my $val = $item->parse_prop($pred);
	    if( ref $val )
	    {
		if( UNIVERSAL::can($val, 'desig') )
		{
		    $val = $val->desig;
		}
		else
		{
		    $req->note(sprintf "Item %s has an invalid $pred: $val");
		    $val = undef;
		}
	    }

#	    debug "  $pred = $val";
	    push @item_row, $val;
	}
#	debug "writing @item_row";
	$sheet->write($row++, 0, \@item_row);

	unless( $row % 100 )
	{
	    $req->note("...". $row ."/". $rows_count);
	    $req->yield;
	}
    }
    continue
    {
	( $item, $error ) = $rows->get_next;
    }

    $req->note(sprintf "Wrote %d rows", $row);

    if( $error )
    {
	debug "Got error $error";
    }


    binmode $fh;
    utf8::decode( $str );

    $req->note('Done!');

    return \ $str;
}

##############################################################################

sub set_ctype
{
    $_[1]->set("application/vnd.ms-excel");
}


##############################################################################



1;

