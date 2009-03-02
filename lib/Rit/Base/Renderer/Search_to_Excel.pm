# $Id$
package Rit::Base::Renderer::Search_to_Excel;

use strict;
use utf8;
use POSIX qw( locale_h );

use Spreadsheet::WriteExcel;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug timediff validate_utf8 throw );
use Para::Frame::L10N qw( loc );

use base 'Para::Frame::Renderer::Custom';

#######################################################################

sub render_output
{
    my( $rend ) = @_;

    setlocale(LC_NUMERIC, "C");

    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    $req->note("Rendering spreadsheet");

    open my $fh, '>', \my $str or die "Failed to open filehandle: $!";
    my $workbook  = Spreadsheet::WriteExcel->new($fh);
    my $sheet = $workbook->add_worksheet();
    $sheet->keep_leading_zeros(1);

    my $row = 0;

    my $rows = $req->session->search_collection->result->sorted('desig');
    my $rows_count = $rows->size;
    $req->note("Writing ".$rows_count." rows");

    my @preds = $q->param('list_pred');
    my @pred_names = $q->param('list_pred_name');

    $sheet->write($row++, 0, \@pred_names);

    foreach my $item ( $rows->as_array )
    {
#	debug "Writing item ".$item->sysdesig;
	my @item_row;
	foreach my $pred (@preds)
	{
	    my $val = $item->$pred;
	    $val = $val->desig if ref $val;
#	    debug "  $pred = $val";
	    push @item_row, $val;
	}
#	debug "writing @item_row";
	$sheet->write($row++, 0, \@item_row);

	$req->note("...". $row ."/". $rows_count)
	  unless( $row % 10 );
    }

    binmode $fh;
    utf8::decode( $str );

    $req->note('Done!');

    return \ $str;
}

#######################################################################

sub set_ctype
{
    $_[1]->set("application/vnd.ms-excel");
}


#######################################################################



1;

