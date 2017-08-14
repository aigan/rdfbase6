package RDF::Base::Literal::Image;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Literal::Image

=cut

use 5.014;
use warnings;
use base qw( RDF::Base::Literal::String );

use Carp qw( cluck confess longmess );
#use CGI;
use URI;

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Widget qw( filefield );

use RDF::Base::Utils qw( parse_propargs );


=head1 DESCRIPTION

Inherits from L<RDF::Base::Literal::String>

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
    my $R = RDF::Base->Resource;

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
	$pred = RDF::Base::Pred->get_by_label($predname);
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

L<RDF::Base::Literal>,
L<RDF::Base::Resource>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::Search>

=cut
