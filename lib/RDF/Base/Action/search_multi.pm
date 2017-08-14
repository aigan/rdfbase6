package RDF::Base::Action::search_multi;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.014;
use warnings;

use Para::Frame::Utils qw( throw debug );

use RDF::Base::Search;

=head1 DESCRIPTION

RDFbase Action for bulk handling of searches.

=cut

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $s = $req->session;

    my( @items ) = $q->param('do_item');

    my( $do ) = $q->param('do');
    my $cnt = scalar(@items) || 0;

    if( $do eq 'merge' )
    {
        unless( $cnt > 1 )
        {
            throw('validation', "Must have at least 2 searches");
        }

        my $col = RDF::Base->Search_Collection->new();
        my( $form_url, $result_url, $active );


        foreach my $label ( @items )
        {
            my $pcol = $s->search_get($label);

            if( scalar @{$pcol->custom_parts} )
            {
                throw('validation', "Merge not workning for custom parts");
            }

            foreach my $rb_part ( @{$pcol->rb_parts} )
            {
                $col->add($rb_part);
            }

            $form_url ||= $pcol->form_url;
            $result_url ||= $pcol->result_url;
            $active ||= $pcol->is_active;

            debug "Do $label";
        }

        $col->result_url($result_url);
        $col->form_url($form_url);

        $col->set_active if $active;

        $s->search_collection($col);
    }


    return "Did $cnt searches";
}


1;
