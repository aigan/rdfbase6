package Rit::Base::Email::RB::Head;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008-2011 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
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
use Para::Frame::Utils qw( throw debug timediff );

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

#    $email->initiate_rel;

    $head->header_set('subject', $email->list('email_subject')->as_array);
    $head->header_set('date', $email->list('email_sent')->as_array);
    $head->header_set('from', $email->list('email_from')->as_array);
    $head->header_set('bcc', $email->list('email_bcc')->as_array);
    $head->header_set('reply-to', $email->list('email_reply_to')->as_array);

    $head->{'rb_email'} = $email;

    return $head;
}


##############################################################################

=head2 init_to

=cut

sub init_to
{
    return if $_[0]->{'rb_head_to_initiated'};

    debug "Initiating RB 'to' field";
#    cluck "Initiating RB 'to' field";


    my( $head ) = @_;

    my $email = $head->{'rb_email'};

#    debug timediff('init_to');
#    $Para::Frame::REQ->may_yield;

    my @to_list = $email->list('email_to')->as_array;

#    debug timediff('init_to email_to');
#    $Para::Frame::REQ->may_yield;

    my $to_obj_list = $email->list('email_to_obj');

#    debug timediff('init_to email_to_obj');
#    $Para::Frame::REQ->may_yield;

    if( $to_obj_list->size > 1000 )
    {
	$Para::Frame::REQ->note(sprintf "Email has %d recipients",
				$to_obj_list->size);
    }

    my( $to_obj, $to_err ) = $to_obj_list->get_first;
    while( !$to_err )
    {
	push @to_list, $to_obj->email_main->plain, $to_obj->contact_email->plain;

	unless( $to_obj_list->count % 1000 )
	{
	    $Para::Frame::REQ->note("  at recipient ".$to_obj_list->count);
	    $Para::Frame::REQ->may_yield;
	    die "cancelled" if $Para::Frame::REQ->cancelled;
	}

	($to_obj, $to_err) = $to_obj_list->get_next;
    }
    my @to_uniq = grep defined, uniq @to_list;

#    debug timediff('init_to to_list');
#    $Para::Frame::REQ->may_yield;

    $head->header_set('to', @to_uniq );

    if( debug > 1 )
    {
	debug 2, "Creating TO header field with @to_uniq";
    }

    $head->{'rb_head_to_initiated'} = 1;

    return;
}


##############################################################################

=head2 count_to

=cut

sub count_to
{
    if( $_[0]->{'rb_head_to_count'} )
    {
	return $_[0]->{'rb_head_to_count'};
    }

    my( $head ) = @_;
    my $email = $head->{'rb_email'};

    my $cnt = $email->count('email_to') + $email->count('email_to_obj');
    return $head->{'rb_head_to_count'} = $cnt;
}


##############################################################################

1;
