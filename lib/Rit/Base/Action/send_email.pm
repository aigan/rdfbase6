package Rit::Base::Action::send_email;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2009-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

use 5.010;
use strict;
use warnings;

=head1 DESCRIPTION

Ritbase Action for sending an email represented as a node

=cut

sub handler
{
    my( $req ) = @_;

    my $changed = 0;

    my $q = $req->q;

    my $id = $q->param('id');

    my $email = Rit::Base::Resource->get($id) or die;

    $req->note("Sending email");

    if( $email->send() )
    {
	return "Email sent";
    }
    else
    {
	return "";
    }
}

1;
