#  $Id$  -*-cperl-*-
package Rit::Base::Email::IMAP::Part;
#=====================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2008 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Email::IMAP::Part

=head1 DESCRIPTION

=cut

use strict;
use utf8;
use Carp qw( croak confess cluck );
use Scalar::Util qw(weaken);
#use URI;
#use MIME::Words qw( decode_mimewords );
#use IMAP::BodyStructure;
#use MIME::QuotedPrint qw(decode_qp);
#use MIME::Base64 qw( decode_base64 );
#use MIME::Types;
#use CGI;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
#use Para::Frame::Utils qw( throw debug create_dir chmod_file idn_encode idn_decode datadump catch fqdn );
use Para::Frame::Utils qw( throw debug );
#use Para::Frame::L10N qw( loc );
use Para::Frame::List;

use Rit::Base;
use Rit::Base::Utils qw( parse_propargs alfanum_to_id is_undef );
use Rit::Base::Constants qw( $C_email );
use Rit::Base::Literal::String;
use Rit::Base::Literal::Time qw( now ); #);
use Rit::Base::Literal::Email::Address;
use Rit::Base::Literal::Email::Subject;
use Rit::Base::Email::Head;
use Rit::Base::Email::Classifier::Bounce;
use Rit::Base::Email::Classifier::Vacation;

use constant EA => 'Rit::Base::Literal::Email::Address';

use base qw( Rit::Base::Email::Part );

#######################################################################

=head2 new

=cut

sub new
{
    my( $part, $struct ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     struct => $struct,
    }, 'Rit::Base::Email::IMAP::Part';

    weaken( $sub->{'email'} );
#    weaken( $sub->{'top'} );

    return $sub;
}


#######################################################################

=head2 new_by_path

=cut

sub new_by_path
{
    my( $part, $path ) = @_;
    my $class = ref($part) or die "Must be called by parent";

    unless( $path )
    {
	return $part;
    }

    my $struct = $part->top->struct->part_at($path);

    my $sub = bless
    {
     email  => $part->email,
     top    => $part->top,
     struct => $struct,
    }, 'Rit::Base::Email::IMAP::Part';
    weaken( $sub->{'email'} );
#    weaken( $sub->{'top'} );

    return $sub;
}


#######################################################################

1;
