package Rit::Base::Email::RB::Head;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2009 Avisita AB.  All Rights Reserved.
#
#=============================================================================

=head1 NAME

Rit::Base::Email::RB::Head

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;
use utf8;
use base qw( Rit::Base::Email::Head );

use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
use List::Uniq qw( uniq ); # keeps first of each value

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );

use Rit::Base;
use Rit::Base::List;
use Rit::Base::Utils qw( parse_propargs is_undef );


##############################################################################

=head2 new_by_email

=cut

sub new_by_email
{
    my( $class, $email ) = @_;

    my $head = $class->new("");

    $email->initiate_rel;

    $head->header_set('subject', $email->list('email_subject')->as_array);
    $head->header_set('date', $email->list('email_sent')->as_array);
    $head->header_set('from', $email->list('email_from')->as_array);
    $head->header_set('bcc', $email->list('email_bcc')->as_array);
    $head->header_set('reply-to', $email->list('email_reply_to')->as_array);


    my @to_list = $email->list('email_to')->as_array;
    my $to_obj_list = $email->list('email_to_obj');
    while( my $to_obj = $to_obj_list->get_next_nos )
    {
	push @to_list, $to_obj->email_main->plain, $to_obj->contact_email->plain;
    }
    my @to_uniq = uniq @to_list;

    $head->header_set('to', @to_uniq );

    debug 2, "Creating TO header field with @to_uniq";

    return $head;
}


##############################################################################

1;
