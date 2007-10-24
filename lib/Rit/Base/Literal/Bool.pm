# $Id$
package Rit::Base::Literal::Bool;

=head1 NAME

Rit::Base::Literal::Bool

=cut

use strict;
use Carp;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Widget qw( checkbox label_from_params );

use Rit::Base::Utils qw( parse_propargs );

use base qw( Rit::Base::Literal::String );

=head1 DESCRIPTION

Inherits from L<Rit::Base::Literal::String>

=cut

warn "SYMBOL TABLE:\n";
foreach my $key ( keys %Rit::Base::Literal::Bool:: )
{
    warn " * $key\n";
    my $val = $Rit::Base::Literal::Bool::{$key};
    foreach my $type (qw( SCALAR ARRAY HASH CODE IO FORMAT ))
    {
	warn "   ".*{$val}{$type}."\n" if *{$val}{$type};
    }
}

    warn "\n****************************************\n\n";
    my $apa = label_from_params({
				 separator   => ":",
				 id          => "urban",
				});
    warn "test: $apa\n";

#######################################################################

=head2 wuirc

Display checkbox for updating...

=cut

sub wuirc
{
    debug "Bool wuirc.";

    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;
    my $req = $Para::Frame::REQ;

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;
    }
    else
    {
	$predname = $pred;
	# Only handles pred nodes
	$pred = Rit::Base::Pred->get_by_label($predname);
    }

    $args->{'id'} ||= "arc_singular__pred_${predname}__subj_". $subj->id ."__row_".$req->{'rb_wu_row'};

    $out .= label_from_params({
			       label       => $args->{'label'},
			       tdlabel     => $args->{'tdlabel'},
			       separator   => $args->{'separator'},
			       id          => $args->{'id'},
			       label_class => $args->{'label_class'},
			      });

    if( ($args->{'disabled'}||'') eq 'disabled' )
    {
	my $arclist = $subj->arc_list($predname, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= $arc->value->desig .'&nbsp;'. $arc->edit_link_html .'<br/>';
	}
    }
    elsif( $subj->count($predname) )
    {
	my $arclist = $subj->arc_list($predname, undef, $args);

	while( my $arc = $arclist->get_next_nos )
	{
	    $out .= checkbox($args->{'id'}, 1, $arc->value->plain) .
	      $arc->edit_link_html;

	}
    }
    else
    {
	$out .= checkbox($args->{'id'}, 1, 0);
    }

    return $out;
}


1;
