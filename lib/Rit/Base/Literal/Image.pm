package Rit::Base::Literal::Image;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

=head1 NAME

Rit::Base::Literal::Image

=cut

use 5.010;
use strict;
use warnings;
use base qw( Rit::Base::Literal::String );

use Carp qw( cluck confess longmess );
use CGI;
use URI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Widget qw( filefield );

use Rit::Base::Utils qw( parse_propargs );


=head1 DESCRIPTION

Inherits from L<Rit::Base::Literal::String>

=cut

##############################################################################

=head2 wuirc

Display field for updating images

=cut

sub wuirc
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";
    my $R = Rit::Base->Resource;

    my $multiple = $args->{'multiple'};

    my $maxw = $args->{'maxw'} ||= 400;
    my $maxh = $args->{'maxh'} ||= 300;
    $args->{'inputtype'} = 'input_image';
    $args->{'image_url'} = $Para::Frame::CFG->{'images_uploaded_url'} ||
      '/images';

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

    $out .= $class->SUPER::wuirc($subj, $pred, $args);

    if( $multiple )
    {
	if( $subj->list($pred, undef, ['active','submitted']) )
	{
	    my $subj_id = $subj->id;
	    $out .= '<br/>'. filefield("arc___file_image__pred_${predname}__subj_${subj_id}__maxw_${maxw}__maxh_${maxh}");
	}
    }

    return $out;
}


##############################################################################

1;

=head1 SEE ALSO

L<Rit::Base::Literal>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::Pred>,
L<Rit::Base::Search>

=cut
