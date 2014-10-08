package RDF::Base::Email::Classifier;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2014 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::Classifier - Analyzes and classifies emails

=cut

use 5.010;
use strict;
use warnings;
use feature "state";
use utf8;
use constant R => 'RDF::Base::Resource';
use constant EA => 'RDF::Base::Email::Address';
use constant LT => 'RDF::Base::Literal::Time';

use Carp qw( croak confess cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump trim );

use RDF::Base::Constants qw( $C_email $C_email_address_holder );
use RDF::Base::Literal::Time;
use RDF::Base::Utils qw( is_undef );

our $DEBUG = 0;

my $RETURNED_MESSAGE_BELOW = qr/(
    (?:original|returned) \s message \s (?:follows|below)
  | (?: this \s is \s a \s copy \s of
      | below \s this \s line \s is \s a \s copy
    ) .{0,100} \s message
  | message \s header \s follows
  | ^ (?:return-path|received|from):
  | ^ original \s mail \s header:
  | ^ included \s is \s a \s copy \s of \s the \s message \s header:
)/sixm;


our $EMAIL_ADDR_REGEX = qr{
# Avoid using something like Email::Valid
# Full rfc(2)822 compliance isn't exactly what we want, and this seems to work
# for most real world cases
(?:<|^|\s)            # Space, or the start of a string
(?:mailto:)?
([^\s\/<]+            # some non-space, non-/ characters; none are <
\@                    # at sign (duh)
(?:[-\w]+\.)+[-\w]+)  # word characters or hypens organized into
                      # at least two dot-separated words
(?:$|\s|\.\W|>)       # then the end
}sx;

my @REPORT_FIELDS = qw(
 email
 host
 smtp_code
 status_code
 reporting-mta
 arrival-date
 reason
 std_reason
 raw
);
my %REPORT_FIELDS; for(@REPORT_FIELDS){$REPORT_FIELDS{$_}=1};

our $AUTO_REGEX = qr{   Automatiskt.meddelande
                    |   Automatiskt.svar
                    |   autosvar
                    |   Auto\s?reply
                    |   Auto.Response
                    |   Auto-Antwort
                    |   Auto
                }sxi;

our $CONTACTINFO_REGEX = qr{(?: Istället.kan.du.vända.dig.till
                            |   Vid.problem
                            |   Fråga.efter
                            |   Behöver.(?:ni|du)
                            |   Vid.brådskande.ärenden
                            |   Vänlig(?:en)?.kontakta
                            |   Det.går.även.bra.att
                            |   If.you.need.to.get.in.contact
                            |   You.may.reach
                            |   In.urgent.matters
                            |   Alla.ärenden
                            )
                       }sxi;

our $EMAIL_LABEL_REGEX = qr{(?:
                                (?:e-?)?
                                (?:post|mail|mejl)
                                (?:\s*-?\s*add?ress)?
                            |
                                (?:add?ress)
                            )}sxi;



# Probably not intended for reaching human reader
#
our $computer_ea = qr{
                }xmi;




=head1 DESCRIPTION

Based on L<Mail::DeliveryStatus::BounceParser>

dsn std_reason mapping:

user_unknown => 5.1.0, 5.1.1
domain_error => 5.1.2
over_quota   => 5.2.2
syntax_error => 5.5.2
denied       => 5.7.1
address_changed => 5.1.6
delayed      => ...
unknown      => X.0.0



other classifications

dsn
ticket
vacation
bounce
address_changed
challenge_response ~
newsletter ~
spam ~
spam_response ~
transient ~


email status
------------
LÄST ljusgrön?
+ dsn seen

OK grön
+ dsn deliviered
+ ticket system
+ vacation

OKÄND grå

TEMPFEL gul
+ dsn transient

ÅTGÄRDAS blå
= manual revision
+ dsn unclassified
+ challenge_response

FEL / DEFFEL
= email_address_error
+ dsn bounce
+ address_changed


=cut


#######################################################################

=head2 new

  Email::Classifier->new( $email_obj )

C<$email> should be an object compatible with L<Email::MIME> 1.861

contact fields:
  {contact}{email_address}{node}
  {contact}{email_address}{changed_to}

=cut

sub new
{
    my( $this, $email_obj ) = @_;
    my $class = ref($this) || $this;

#    warn "new Classifier object\n" if $DEBUG;

    my $c = bless
    {
     email_obj => $email_obj,
     reports => [],
     is => {},
     analyzed => {},
     ticket => undef, # original email/ticket node
     contact => {}, # Contact information gathered
     dsn_date => undef,
    }, $class;

    return $c;
}



#######################################################################

=head2 is_dsn

=cut

sub is_dsn
{
    my( $c ) = @_;
    $c->analyze_dsn;
    return $c->{is}{dsn} ? 1 : 0;
}


#######################################################################

=head2 analyze_dsn

=cut

sub analyze_dsn
{
    my( $c ) = @_;

    return if $c->{analyzed}{dsn};
    $c->{analyzed}{dsn} ++;

    debug "Analyzing for DSN" if $DEBUG;

    if( $c->is_auto_reply or
        $c->is_bounce or
        $c->is_vacation or
        $c->is_address_changed )
    {
        $c->{is}{dsn} ++;
        return;
    }

    return;
}


#######################################################################

=head2 is_delivered

=cut

sub is_delivered
{
    my( $c ) = @_;
    $c->analyze_delivered;
    return $c->{is}{delivered} ? 1 : 0;
}


#######################################################################

=head2 analyze_delivered

=cut

sub analyze_delivered
{
    my( $c ) = @_;

    return if $c->{analyzed}{delivered};
    $c->{analyzed}{delivered} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Delivered" if $DEBUG;


    # Some auto-responders keeps nothing of the original email except
    # the To-address, and just sends the pre-formatted message. Look
    # for common subjects
    #
    ### Subject
    #
    my $subject = trim $o->head->parsed_subject->plain;
    if( $subject =~ /^Thank you for your email\b|the message has been delivered|Tack för ditt mejl|Vi har mottagit ditt meddelande|Din förfrågan är mottagen/i )
    {
        $c->{is}{delivered} = 1;
        return;
    }

    return unless $c->is_computer_generated;
    return if $o->effective_type eq 'multipart/report';

    my $cpart = $o->guess_content_part;
    my( $bodyr, $ct_source ) = $cpart->body_as_text;
    return unless $ct_source;
    my $body = trim $bodyr;


#    debug "PARSED BODY---------------\n$body\n-----------------";

    ### Indicates auto-reply
    #
    state $outrx = qr/ Vi.har.mottagit.ditt.e?-?mail
		   |   Vi.har.tagit.emot.eran.förfrågan
		   |   Vi.hör.av.oss.till.er.så.snart.som.möjligt
                   |   Vi.återkommer.inom
		   |   Tack.för.din.e-post.till
		   |   Vi.kommer.att.besvara.det.så.snart.vi.kan
		   |   Ditt.meddelande.är.mottaget
		   |   Vi.svarar.inom
		   |   har.kommit.fram
		   |   Jag.svarar.så.fort.jag.kan
		   |   återkommer.imorgon
                   |   återkommer.till.dig.inom.kort
		   |   Jag.har.gått.för.dagen
		   |   We.have.received.your.enquiry
                   |   nås.under.kontorstid
		     /xi;
    if( $body =~ $outrx )
    {
        $c->{is}{delivered} = 1;
        return;
    }

    if( $c->is_ticket )
    {
        $c->{is}{delivered} = 1;
        return;
    }


    return;
}


#######################################################################

=head2 is_ticket

=cut

sub is_ticket
{
    my( $c ) = @_;
    $c->analyze_ticket;
    return $c->{is}{ticket} ? 1 : 0;
}


#######################################################################

sub analyze_ticket
{
    my( $c ) = @_;

    return if $c->{analyzed}{ticket};
    $c->{analyzed}{ticket} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Ticket" if $DEBUG;

    return unless $c->is_computer_generated;

#    debug "  Parse subject: ".$o->head->parsed_subject->plain;

    my $subject = trim $o->head->parsed_subject->plain;

    $c->{is}{ticket} = 1 
      if $subject =~ /^(?:Re:\s*)?\[[^\]]*#[^\]]+\]/;


    $c->{is}{ticket} = 1
      if $subject =~ /^Request received:/i;

    return 1;
}


#######################################################################

=head2 is_newsletter

=cut

sub is_newsletter
{
    my( $c ) = @_;
    $c->analyze_newsletter;
    return $c->{is}{newsletter} ? 1 : 0;
}


#######################################################################

sub analyze_newsletter
{
    my( $c ) = @_;

    return if $c->{analyzed}{newsletter};
    $c->{analyzed}{newsletter} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Newsletter" if $DEBUG;

    my $newsletter = 0;

    return if $c->is_reply;
    return if $c->is_dsn;

    $newsletter ++ if $c->is_computer_generated;
    $newsletter ++ if ($o->header('Precedence')||'') =~ /junk|bulk|list/;
    $newsletter ++ if $o->header('List-Unsubscribe');

    my $news_address_rx = qr/newsletter|nyhetsbrev|info/;

    foreach my $h ('From', 'Reply-To', 'Return-path')
    {
#        debug "  $h: ".$o->header($h);
        my $v = $o->header($h) or next;
        $newsletter ++ if $v =~ $news_address_rx;
        $newsletter ++ if EA->is_nonhuman($v);
    }

    my $html_part = $o->first_part_with_type('text/html');
    if( $html_part )
    {
        $newsletter ++;
        $newsletter ++ if $html_part->size > 10000;
        $newsletter ++ if $html_part->size > 20000;

        debug "HTML Size: ".$html_part->size;

        my $body = ${$html_part->body_as_text};
        foreach my $rx (
                        qr/Se det här brevet på webben/i,
                        qr/Webbversion/i,
                        qr/prenumeration/,
                        qr/nyhetsbrev/,
                       )
        {
            if( $body =~ $rx )
            {
                $newsletter ++;
                debug "Body matched $rx";
            }
        }
    }

    if( $o->head->parsed_subject =~ /nyhetsbrev|nyheter|news/i )
    {
        $newsletter ++;
    }

    debug "Newsletter points: $newsletter";

    if( $newsletter >= 4 )
    {
        $c->{is}{newsletter} = $newsletter;
    }

    return;
}


#######################################################################

=head2 is_challenge_response

=cut

sub is_challenge_response
{
    my( $c ) = @_;
    $c->analyze_challenge_response;
    return $c->{is}{challenge_response} ? 1 : 0;
}


#######################################################################

sub analyze_challenge_response
{
    my( $c ) = @_;

    return if $c->{analyzed}{challenge_response};
    $c->{analyzed}{challenge_response} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Challenge Response" if $DEBUG;

### TODO: spamarrest.com
}


#######################################################################

=head2 is_unsubscribe

=cut

sub is_unsubscribe
{
    my( $c ) = @_;
    $c->analyze_unsubscribe;
    return $c->{is}{unsubscribe} ? 1 : 0;
}


#######################################################################

sub analyze_unsubscribe
{
    my( $c ) = @_;

    return if $c->{analyzed}{unsubscribe};
    $c->{analyzed}{unsubscribe} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Unsubscribe" if $DEBUG;

    return unless $c->is_reply;

    my $bodyr = $o->guess_content_part->body_as_text;
    if( $$bodyr =~ /
                       sänd.inte.fler.mail
                   /ix )
    {
        $c->{is}{unsubscribe} = 1;
    }

    return;
}


#######################################################################

=head2 is_computer_generated

=cut

sub is_computer_generated
{
    my( $c ) = @_;
    $c->analyze_computer_generated;
#    debug "IS computer_generated" if $c->{is}{computer_generated};
    return $c->{is}{computer_generated} ? 1 : 0;
}


#######################################################################

sub analyze_computer_generated
{
    my( $c ) = @_;

    return if $c->{analyzed}{computer_generated};
    $c->{analyzed}{computer_generated} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Computer generated" if $DEBUG;

    if( $o->header('X-FC-MachineGenerated')
      )
    {
        $c->{is}{computer_generated} = 1;
        return;
    }

    state $hwc =
    {
     'Auto-Submitted'      => qr/^auto-/,
     'X-Mailer'           => qr/
				   ^StarScan |
				   Internet[ ]Agent |
				   OTRS
			       /xi,
    };
    foreach my $h ( keys %$hwc )
    {
	my $r = $hwc->{$h};
#        debug "  Looking at $h ".($o->header($h)||'');
        if( ($o->header($h)||'') =~ $r )
        {
#            debug "Found header $h indicating computer_generated";
            $c->{is}{computer_generated} = 1;
            return;
        }
    }

    if( $c->is_auto_reply )
    {
        $c->{is}{computer_generated} = 1;
        return;
    }

    if( ${$o->first_non_multi_part->body} =~ $AUTO_REGEX )
    {
        $c->{is}{computer_generated} = 1;
    }

    return 1;
}


#######################################################################

=head2 is_auto_reply

=cut

sub is_auto_reply
{
    my( $c ) = @_;
    $c->analyze_auto_reply;
#    debug "Auto-reply? ".$c->{is}{auto_reply};
    return $c->{is}{auto_reply} ? 1 : 0;
}


#######################################################################

sub analyze_auto_reply
{
    my( $c ) = @_;

    return if $c->{analyzed}{auto_reply};
    $c->{analyzed}{auto_reply} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Auto-reply" if $DEBUG;

    if( $o->header('Return-path') =~ /<mailer-daemon\@.*>/ )
    {
        $c->{is}{auto_reply} ++;
        return;
    }

#    debug "A1";

    foreach my $header (qw(X-Autorespond X-AutoReply-From
                           X-Mail-Autoreply X-Autoreply
                           x-ms-exchange-parent-message-id
                           x-ms-exchange-generated-message-source
                           X-MDaemon-Deliver-To))
    {
        if( $o->header($header) )
        {
            $c->{is}{auto_reply} ++;
            return;
        }
    }

#    debug "A2";
    state $hwc =
    {
     'Preference'          => qr/auto_reply/i,
     'X-Autogenerated'     => qr/Reply/i,
     'X-POST-MessageClass' => qr/Autoresponder/i,
     'Delivered-To'        => qr/Autoresponder/i,
     'Auto-Submitted'      => qr/auto-replied/i,
     'X-Loop'              => qr/Vacation/i,
    };
    foreach my $h ( keys %$hwc )
    {
	my $r = $hwc->{$h};
#        debug "  Looking at $h ".($o->header($h)||'');
        if( ($o->header($h)||'') =~ $r )
        {
#            debug "Found header $h indicating DSN";
            $c->{is}{auto_reply} ++;
            return;
        }
    }

    my $subject = trim $o->head->parsed_subject->plain;
#    debug "A3";
    if( $subject =~ $AUTO_REGEX )
    {
        $c->{is}{auto_reply} ++;
        return;
    }

#    debug "A4";
    if( $subject =~ /Thank you for your e-?mail/i )
    {
        $c->{is}{auto_reply} ++;
        return;
    }

#    debug "A5";
    if( $c->is_delivered )
    {
        $c->{is}{auto_reply} = 1;
        return;
    }


#    debug "A6";
    if( $c->is_computer_generated and $c->is_reply )
    {
        $c->{is}{auto_reply} ++;
        return;
    }

#    debug "A7";
    if( $c->is_dsn )
    {
        $c->{is}{auto_reply} ++;
        return;
    }

#    debug "A8";

    return 1;
}


#######################################################################

=head2 is_reply

=cut

sub is_reply
{
    my( $c ) = @_;
    $c->analyze_reply ;
    return $c->{is}{reply} ? 1 : 0;
}


#######################################################################

sub analyze_reply
{
    my( $c ) = @_;

    return if $c->{analyzed}{reply};
    $c->{analyzed}{reply} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Reply" if $DEBUG;

    if( $c->is_auto_reply )
    {
        $c->{is}{reply} = 1;
        return;
    }

    if( $o->header("in-reply-to") or
        $o->header("references") )
    {
        $c->{is}{reply} = 1;
        return;
    }

    if( $c->is_verp )
    {
        $c->{is}{reply} = 1;
        return;
    }

    if( $o->first_part_with_type("message/rfc822") )
    {
	$c->{is}{reply} = 1;
        return;
    }

    if( $o->head->parsed_subject =~ /^(Re|Sv):/i )
    {
        $c->{is}{reply} = 1;
        return;
    }

    return 1;
}


#######################################################################

=head2 is_vacation

=cut

sub is_vacation
{
    my( $c ) = @_;
    $c->analyze_vacation;
    return $c->{is}{vacation} ? 1 : 0;
}


#######################################################################

sub analyze_vacation
{
    my( $c ) = @_;

    return if $c->{analyzed}{vacation};
    $c->{analyzed}{vacation} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Vacation" if $DEBUG;


    # From Mail::DeliveryStatus::BounceParser:
    #
    # we'll deem autoreplies to be usually less than a certain size.
    #
    # Some vacation autoreplies are (sigh) multipart/mixed, with an
    # additional part containing a pointless disclaimer; some are
    # multipart/alternative, with a pointless HTML part saying the
    # exact same thing.  (Messages in this latter category have the
    # decency to self-identify with things like '<META
    # NAME="Generator" CONTENT="MS Exchange Server version
    # 5.5.2653.12">', so we know to avoid such software in future.)
    # So look at the first part of a multipart message (recursively,
    # down the tree).

    # is bounce?
    return if $o->effective_type eq 'multipart/report';


    # Unambigous vacation subjects
    #
    my $outrx = qr/ ^Fr.{1,2}nvaro\b
		|    borta.från.kontoret
		|    är.inte.på.kontoret
		|    Är.på.resande.fot
		|    Jag.är.sjukskriven
		|    Är.på.semester
		|    (out|away|on.holiday).*office
		|    rufe.meine.E-Mail.zur.Zeit.nicht.ab
		|    semestersvar
                |    Semestermeddelande
		|    Jag.är.ledig
		|    ^Bortrest
		|    ^Ej.inne
		|    I'm.on.a.business.trip
		|    ^Fraværende
		  /xi;

    # Ambigous vacation content, only for autoreply
    #
    my $outrx2 = qr/   vacation
                   |   semester
                   |   tjänsteresa
                   |   read.my.mail
                   |   Jag.är.inte.på.kontoret
                   |   During.my.abcense
                   |   föräldraledig
                   |   Jag.är.tjänstledig
                   |   maternity.leave
                   |   tagit.ledigt
                   /xi;

    my $subject = trim $o->head->parsed_subject->plain;
    # Strip common prefixes from subject
    $subject =~ s/^(Re:)?\s*$AUTO_REGEX\s*[:\-]?\s*//i;
#    debug "Subject: $subject";

    my $vacation = 0;

    $vacation ++ if $subject =~ $outrx;

    if( ($o->header('X-Loop')||'') =~ /vacation/ ) # Postfix
    {
        $vacation ++;
    }



#    debug "v3";

    # Stop parsing if email content is stupid
    #
    my $cpart = $o->guess_content_part;
    my( $bodyr, $ct_source ) = $cpart->body_as_text;
    return unless $ct_source;
    my $string = trim $bodyr;
    return if length($string) > 10000;

#    debug "v4";

    # Outlook and exchange are BAD BAD BAD.
    # Keep processing if the email comes from a retarded system
    my $underspecified = 0;
    if( $o->header('Thread-Index') )
    {
        $underspecified = 1;
    }

    ### Keep processing?
    #
    unless( $vacation or
            $c->is_computer_generated or
            ( $c->is_reply and $underspecified ) )
    {
        return;
    }

#    debug "  Parse $string";

    $vacation ++ if $subject =~ $outrx2;
    $vacation ++ if $string =~ $outrx;
    $vacation ++ if $string =~ $outrx2;

    ### Continue if sign of vacation
    #
    return unless $vacation; ## Get the details

#    debug "v5";

    if( $c->is_address_changed or $c->is_quit_work )
    {
	return;
    }

#    debug "v6";

    # Expecting personal info folowed by details on alternative
    # contact methods.

    my $body = $o->footer_remove( $string );

    my( $personal, $context ) = split $CONTACTINFO_REGEX, $body, 2;

    if( $context )
    {
        # Add a point for analyzing fuzzy context
        $vacation ++;
    }
    else
    {
	# Stop parsing dates after first email.
	( $personal, $context ) = split $EMAIL_ADDR_REGEX, $body, 2;
    }

    $body = $personal;


#    ### Short term phrases
#    #
#    id( $body =~ m/
#		  /xi )
#    {
#    }


    ### Removing start dates in from-to format.
    #
    foreach my $rx (
		    qr/from .{3,20}? until/i,
		    qr/Fr\.?o\.?m\.? .{3,20}? (har|och)/i, # (Från och med)
		    qr/från.{3,20} (har|och)/i, # (Från och med)
		    qr/Between .{3,20}? and/i,
		    qr/starting .{3,20}? and/i,
                    qr/\båter/i,
		   )
    {
        if( $body =~ s/$rx// )
        {
            # Add a point for analyzing fuzzy context
            $vacation ++;
            last;
        }
    }

    # Translate some unspecific dates
    #  Callibrated for latest return time
    #
    $body =~ s/våren/maj/gi;
    $body =~ s/sommaren/augusti/gi;
    $body =~ s/hösten/november/gi;
    $body =~ s/vintern/februari/gi;


#    debug "BODY AFTER TRIM -------------\n$body\n-----------------------";
    my $date = LT->extract_date(\$body, $c->dsn_date );

    if( $date )
    {
        # Add a point for analyzing fuzzy context
        $vacation ++;

        $c->{contact}{date_availible} = $date;
        debug "DATE found: $date";
    }
    else
    {
	debug "Date not found in text";
	return;
    }

    if( $c->is_computer_generated or
        $vacation >= 3 )
    {
        debug "Vacation points: ".$vacation;
        $c->{is}{vacation} = $vacation;
    }

    # 1. Back next business day
    # 2. Back after normal length vacation
    # * Is the mail forwarded, delivered and/or ignored?
    # * The date the person is expected back
    # * Recommended alternative email addresses or phone numbers

    return;
}


#######################################################################

=head2 is_transient

=cut

sub is_transient
{
    my( $c ) = @_;
    $c->analyze_transient;
    return $c->{is}{transient} ? 1 : 0;
}


#######################################################################

=head2 analyze_transient

=cut

sub analyze_transient
{
    my( $c ) = @_;

    return if $c->{analyzed}{transient};
    $c->{analyzed}{transient} ++;

    debug "Analyzing for Transient" if $DEBUG;

    $c->analyze_bounce;

    return;
}


#######################################################################

=head2 is_bounce

A bounce means that the email didn't reach the destination

=cut

sub is_bounce
{
    my( $c ) = @_;
    $c->analyze_bounce;
    return $c->{is}{bounce} ? 1 : 0;
}


#######################################################################

=head2 analyze_bounce

=cut

sub analyze_bounce
{
    my( $c ) = @_;

    return if $c->{analyzed}{bounce};
    $c->{analyzed}{bounce} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Bounce" if $DEBUG;

#    debug $o->viewtree;


    $c->analyze_multipart_report;

    # Try more if no reason found
    if( ($c->dsn_std_reason||'unknown') eq "unknown" )
    {
	$c->analyze_bounce_guess;
    }
    return if $c->{is}{bounce};


    if( $c->is_quit_work )
    {
	$c->{is}{bounce} = 1;
	return;
    }


    return;
}


#######################################################################

=head2 is_verp

=cut

sub is_verp
{
    my( $c ) = @_;
    $c->analyze_verp;
    return $c->{is}{verp} ? 1 : 0;
}


#######################################################################

=head2 analyze_verp

VERP = Variable envelope return path

=cut

sub analyze_verp
{
    my( $c ) = @_;

    return if $c->{analyzed}{verp};
    $c->{analyzed}{verp} ++;

    my $o = $c->email_obj;
    debug "Analyzing for VERP" if $DEBUG;
#                debug datadump($c,2);

    my $to =  $o->head->parsed_address('to') ;
    my $be = $Para::Frame::CFG->{'bounce_emails'} or return;
    if( $to->address =~ /.+$be$/i  )
    {
        if( $to->address =~ /t(\d+)-/ )
        {
            $c->{ticket} = R->get($1);
            debug "Got ticket ".$c->{ticket}->desig;
        }

        if( $to->address =~ /r(\d+)-/ )
        {
            my $node = R->get($1);
            if( $node->prop('is',$C_email_address_holder) )
            {
                $c->{contact}{email_address}{node} = $node;
                debug "Got recipient ".$node->desig;
                $c->{is}{verp} = 1;
                die "FIXME";
                return;
            }
        }
    }

    my @refs = ( $o->header("in-reply-to"),
                 $o->header("references") );

    foreach my $mid_string ( @refs )
    {
        $mid_string =~ s/^<|>$//g;
        foreach my $mid ( split />\s*</, $mid_string )
        {
            if( $mid =~ /t(\d+)-.*-pf\@/ )
            {
                $c->{ticket} = R->get($1);
                debug "Got ticket ".$c->{ticket}->desig;
            }

            if( $mid =~ /r(\d+)-.*-pf\@/ )
            {
                my $node = R->get($1);
                if( $node->prop('is',$C_email_address_holder) )
                {
                    $c->{contact}{email_address}{node} = $node;
                    debug "Got recipient ".$node->desig;
                    $c->{is}{verp} = 1;
                die "FIXME";
                    return;
                }
            }
        }
    }

    ### Looking for our OPTOUT code in body, in case the original
    ### email was included
    #
    my $cpart = $o->guess_content_part;
    my( $bodyr, $ct_source ) = $cpart->body_as_text;
    return unless $ct_source;
    my $string = $$bodyr;

    debug "  Looking in body ".length($string) if $DEBUG;
    if( $string =~ /\/optout\.tt\?e=([^&]+(?:%40|@)[^&]+)&/ )
    {
	my $adr = $1;
	$adr =~ s/%40/\@/;
	debug "    Matched $adr";

	if( my $node = EA->exist( $adr ) )
	{
	    $c->{contact}{email_address}{node} = $node;
	    debug "Got recipient ".$node->desig;
	    $c->{is}{verp} = 1;
	    return;
	}
    }

    return;
}


#######################################################################

=head2 analyze_multipart_report

=cut

sub analyze_multipart_report
{
    my( $c ) = @_;

    return if $c->{analyzed}{multipart_report};
    $c->{analyzed}{multipart_report} ++;

    my $o = $c->email_obj;
    debug "Analyzing multipart/report" if $DEBUG;

    # The report might be attached and not top-level
    #
    return unless $o->first_part_with_type('multipart/report');

    my($delivery_status) =
      $o->first_part_with_type("message/delivery-status");
    return 0 unless $delivery_status;

    my %global =
      (
       "reporting-mta" => undef,
       "arrival-date"  => undef,
      );

    # Some MTAs generate malformed multipart/report messages with
    # no message/delivery-status part
    my $delivery_status_body = ${$delivery_status->body || \ ''};
    unless( $delivery_status_body )
    {
	warn "  no message/delivery-status found\n" if $DEBUG;
    }

#    warn "DELIVERY-STATUS:\n${$delivery_status_body}\n--------\n" if $DEBUG;


    # Used to be \n\n, but now we allow any number of newlines
    # between individual per-recipient fields to deal with stupid
    # bug with the IIS SMTP service.  RFC1894 (2.1, 2.3) is not
    # 100% clear about whether more than one line is allowed - it
    # just says "preceded by a blank line".  We very well may put
    # an upper bound on this in the future.
    #
    # See t/iis-multiple-bounce.t

    # TODO: Handle X-Notes folding in the middle of a word:
    # Diagnostic-Code: X-Notes; User marie.ekstrom (marie.ekstrom@mcdonalds.s
    #  e) not listed in Domino Directory

    $c->{is}{dsn} = 1;


    $delivery_status_body =~ s/\r//g;
    foreach my $para ( split /\n{2,}/, $delivery_status_body )
    {
#        warn "DELIVERY-STATUS PARA:\n${$delivery_status_body}\n--------\n" if $DEBUG;

	$para =~ s/\s+$/\n\n/g;

	# See t/surfcontrol-extra-newline.t - deal with bug #21249
	$para =~ s/\A\n+//g;

	my $report_in = RDF::Base::Email::Head->new($para);
	my %report; # New report

	if( $DEBUG )
	{
	    warn "Parsed a report:\n";
	    warn join "", map{ "  $_\n"} split /\n/,
	      ($report_in->as_string||'');
	}


	# Some MTAs send unsought delivery-status notifications
	# indicating success; others send RFC1892/RFC3464 delivery
	# status notifications for transient failures.

	if( my $action = lc($report_in->header('Action')||''))
	{
	    if( $action =~ s/^\s*([a-z]+)\b.*/$1/s )
	    {
		# In general, assume that anything other than
		# 'failed' is a non-bounce; but 'expanded' is
		# handled after the end of this foreach loop,
		# because it might be followed by another
		# per-recipient group that says 'failed'.

		if( $action eq 'expanded' )
		{
                    $global{seen_action}{expanded} = 1;
		}
		elsif( $action eq 'failed' )
		{
                    $global{seen_action}{failed} = 1;
		}
		elsif( $action eq 'delayed' )
		{
                    $global{seen_action}{delayed} = 1;
		}
		else
		{
		    warn("message/delivery-status says 'Action: $1'")
		      if $DEBUG;
		    return 1;
		}
	    }
	    else
	    {
		warn "Failed to parse action: $action\n" if $DEBUG;
	    }
	}
	else
	{
	    warn "Report has no action\n" if $DEBUG;
	}

	foreach my $hdr (qw(reporting-mta arrival-date))
	{
	    if( my $report_hdr = $report_in->header($hdr) )
	    {
		warn "Extracting $hdr from report\n" if $DEBUG;
		$global{$hdr} ||= $report_hdr;
	    }

	    if( $global{$hdr} )
	    {
		warn "Setting report $hdr = $global{$hdr}\n" if $DEBUG;
		$report{$hdr} = $global{$hdr};
	    }
	}

	my $rcpt; # recipient

	my $rcpt_orig = $report_in->header("original-recipient");
	my $rcpt_final = $report_in->header("final-recipient");

	if( $c->{prefer_final_recipient} )
	{
	    $rcpt = $rcpt_final || $rcpt_orig || '';
	}
	else
	{
	    $rcpt = $rcpt_orig || $rcpt_final || '';
	}

	next unless $rcpt;

	warn "Parsing for recipient: $rcpt\n" if $DEBUG;

	# Diagnostic-Code: smtp; 550 5.1.1 User unknown
	my $diag = $report_in->header("diagnostic-code") || '';

	if( my $reason = $diag )
	{
	    # strip leading X-Postfix;
	    if( $reason =~ s/([^;]+;\s*)// )
	    {
		warn "Stripped prefix $1\n" if $DEBUG;
	    }
	    warn "Found reason:'$diag'\n" if $DEBUG;
	    $reason =~ s/\s+/ /g;


	    $report{reason} = $reason;
	}

	# strip leading RFC822; or LOCAL; or system;
	$rcpt =~ s/[^;]+;\s*//;
	$rcpt = _cleanup_email($rcpt);
	$report{email} = $rcpt;

	if( my $status = $report_in->header('Status') )
	{
	    # RFC 1893... prefer Status: if it exists and is
	    # something we know about.
	    # Not 100% sure about 5.1.0...

	    if( $status =~ /^[45].2.2/ )
	    {
		$report{std_reason} = "over_quota";
	    }
	    elsif( $status =~ /^4\.\d\.\d/ )
	    {
		$report{std_reason} = "delayed";
	    }
	    elsif( $status =~ /^5\.1\.[01]$/ )
	    {
		$report{std_reason} = "user_unknown";
	    }
	    elsif( $status =~ /^5\.2\.1$/ ) # Disabled
	    {
		$report{std_reason} = "user_unknown";
	    }
	    elsif( $status eq "5.1.2" )
	    {
		$report{std_reason} = "domain_error";
	    }
	    elsif( $status eq "5.5.2" )
	    {
		$report{std_reason} = "syntax_error";
	    }
	    elsif( $status eq "5.7.1" )
	    {
		$report{std_reason} = "denied";
	    }
	    elsif( $status =~ /^\d.1.6$/ )
	    {
		$report{std_reason} = "address_changed";
	    }
	    else
	    {
		warn "Unknown status code: $status\n" if $DEBUG;
#                debug "Looking for reason in:\n$diag";
		$diag =~ s/\s+/ /g;
		my $std_reason = _std_reason($diag);
		$report{std_reason} = $std_reason;
	    }
	}
	else
	{
	    warn "No status given in report\n" if $DEBUG;
	    my $std_reason = _std_reason($diag);
	    $report{std_reason} = $std_reason;
	}

	my($host) = $diag =~ /\bhost\s+(\S+)/i;
	$report{host} = $host if $host;

	warn "diag: $diag\n" if $DEBUG;
	if( $diag =~ m/ ( [245] \d{2} ) \s
                          | \s ( [245] \d{2} ) (?!\.) /x )
	{
	    my $code = $1 || $2 || '';
	    warn "Got code '$code'\n" if $DEBUG;
	    $report{smtp_code} = $code if $code;
	}


	unless( $host )
	{
	    warn "Setting host based on recipient\n" if $DEBUG;
	    $host = ($rcpt =~ /\@(.+)/)[0];
	    $report{host} = $host if $host;
	}

	if( ($report{smtp_code}||'') =~ /^2../ )
	{
	    warn "SMTP code is $report{smtp_code}; no_problemo\n" if $DEBUG;
	    next;
	}

#        debug "Host: ".$report{host};
#        debug "Reporting MTA: ".$global{'reporting-mta'}
#          if $global{'reporting-mta'};

	warn "Reason found in report: $report{std_reason}\n" if $DEBUG;

	$c->new_report(\%report);

    } # END foreach $para


    my $seen = $global{seen_action};
    if( $seen->{expanded} and not $seen->{failed} )
    {
	# We've seen at least one 'Action: expanded' DSN-field,
	# but no 'Action: failed'

	warn("message/delivery-status says 'Action: expanded'\n")
	  if $DEBUG;
	return 1;
    }
    elsif( $seen->{delayed} )
    {
        $c->{is}{transient} = 1;
    }
    else
    {
        $c->_extract_from_reports;
    }

    return;
}


#######################################################################

=head2 analyze_bounce_guess

Only if we think that it may be a bounce, but not in a standard format

=cut

sub analyze_bounce_guess
{
    my( $c ) = @_;

    $c->{analyzed}{bounce_guess} ++;

    my $o = $c->email_obj;
    debug "Analyzing for Bounce - guessing" if $DEBUG;

    # A second try with a report or just general message
    #
    if( my $report = $o->first_part_with_type('multipart/report') )
    {
        $o = $report;
    }


    # Only try to guess bounce report if we belive this realy could be
    # a bounce message
    my $common_subjects = qr/ failure[ ]?notice
                          | undeliverable
                          | delivery[ ]?failure
                          | NDN:
                          | This[ ]account[ ]isn't[ ]in[ ]use
                            /ix;
    my $subject = trim $o->head->parsed_subject->plain;
    return unless( $c->is_computer_generated or
		   $o->header('From') =~ /mailer-daemon|postmaster/i or
		   $subject =~ $common_subjects );



    ### Bad non-standard bounces
    #
    # user_unknown
    #
    if( $subject =~
        /   Message.delivery.has.failed
        |   Leverans.misslyckades
        |   This.
            (account|$EMAIL_LABEL_REGEX).
            (isn't|is.not|is.no.longer).
            in.use
        |   Denna.$EMAIL_LABEL_REGEX.
            är.ej.längre.i.bruk
        /xi )
    {
	if( my $adr = $c->dsn_for_address('guess') )
	{
	    $c->{is}{bounce_guess} = 1;
	    $c->{is}{bounce} = 1;
	    $c->new_report({
			    std_reason => 'user_unknown',
			    email => $adr,
			    raw => $o->head->parsed_subject,
			   });
	    return;
	}
    }
    #
    # denied
    #
    if( $subject =~ /Postning ej tillåten/i )
    {
	if( my $adr = $c->dsn_for_address('guess') )
	{
	    $c->{is}{bounce_guess} = 1;
	    $c->{is}{bounce} = 1;
	    $c->new_report({
			    std_reason => 'denied',
			    email => $adr,
			    raw => $o->head->parsed_subject,
			   });
	    return;
	}
    }


#    debug "PARTS: ".datadump($o->parts,1);

    $c->_bounce_guess_subpart( $o, 'text/plain' );

    # Try again for more types of DSNs,
    # if there is another sign of an DSN
    #
    if( not @{$c->{reports}} and $c->is_computer_generated )
    {
        debug "Trying again";
        $c->_bounce_guess_subpart( $o, 'text/html' );
    }

    $c->{is}{bounce_guess} = 1;
    $c->_extract_from_reports;

    return;
}


#######################################################################

sub _bounce_guess_subpart
{
    my( $c, $part, $type ) = @_;

    # Do not look inside attached messages
    return if $part->type eq 'message/rfc822';

    foreach my $sub ( $part->parts )
    {
        $c->_bounce_guess_subpart( $sub, $type );
    }

    return unless $part->type =~ /^$type/;

    debug "Trying to extract reports from part ".$part->path if $DEBUG;

    my $body = trim $part->body_as_text;

    if( $body =~ $RETURNED_MESSAGE_BELOW )
    {
        debug "Matching RETURNED_MESSAGE_BELOW" if $DEBUG;
        my ($stuff_before, $stuff_splitted, $stuff_after) =
          split $RETURNED_MESSAGE_BELOW, $body, 3;

        push @{$c->{reports}}, _extract_reports($stuff_before);
        # TODO: Set up $c->{'orig_message'}
    }
    elsif( $body =~ /(.+)\n\n(.+?Message-ID:.+)/is )
    {
        debug "Matching Message-ID string" if $DEBUG;
        push @{$c->{reports}}, _extract_reports($1);
    }
    else
    {
        debug "looking at the whole part" if $DEBUG;
        push @{$c->{reports}}, _extract_reports($body);
    }

    return;
}


#######################################################################

=head2 is_quit_work

=cut

sub is_quit_work
{
    my( $c ) = @_;
    $c->analyze_quit_work;
    return $c->{is}{quit_work} ? 1 : 0;

}


#######################################################################

=head2 analyze_quit_work

=cut

sub analyze_quit_work
{
    my( $c ) = @_;

    return if $c->{analyzed}{quit_work};
    $c->{analyzed}{quit_work} ++;

    debug "Analyzing for Quit work" if $DEBUG;
    my $o = $c->email_obj;

    my $quit = 0;


    my $subject = trim $o->head->parsed_subject->plain;
    # Strip common prefixes from subject
    $subject =~ s/^(Re:)?\s*$AUTO_REGEX\s*[:\-]?\s*//i;
#    debug "Subject: $subject";

    if( $subject =~ /^I'm not longer employed at|Jag har gått i pension|Jag har slutat/i )
    {
        $quit ++;
    }

    my $body = trim $o->guess_content_part->body_as_text;

    # Outlook and exchange are BAD BAD BAD.
    # Keep processing if the email comes from a retarded system
    my $underspecified = 0;
    if( $o->header('Thread-Index') )
    {
        $underspecified = 1;
    }


    ### Keep processing?
    #
    return unless $quit or $c->is_computer_generated or
      ( $c->is_reply and $underspecified );


    my $leave_rx = qr{   The.person.you.are.looking.for.has.left
		     |   Sedan.{4,20}.jobbar.{2,20}.inte.längre.
                         (på|hos|inom|som)
		     |	 Jag.jobbar.inte.(längre.)?(kvar.)?(på|hos|inom|som)
		     |   arbetar.inte.längre.(kvar.)?(på|hos|inom|som)
		     |	 har.{1,20}slutat.(på|hos|inom)
		     |	 har.
                         (nu.)?
                         (av)?slutat.min.
                         (anställning|tjänst).
                         (på|hos|inom|som)
		     |	 avslutad.anställning
		     |   slutade.jag.min.anställning
		     |	 employment.terminated
                     |   will.leave
                     |   no.longer.employed
		     |	 I.am.no.longer.(working.at|with)
		     |   I.am.released.from.my.duties
		     |   I.have.left
		     |	 Jag.är.pensionär
		     |   Jag.har.(gått|går).i.pension
		     |   I.have.{1,20}retired
		     |   has.retired
		     |	 Den.du.söker.{0,20}.har.slutat.(på|hos|inom|som)
		     |   är.inte.anställd.(på|hos|inom)
                     |   är.inte.med.i
		     |   has.left.*no.longer.monitored
		     |   tyvärr.finns.jag.inte.kvar.(på|hos|inom).företaget
		     |   do(es)?.not.work.for
                     |   min.sista.arbetsdag
                 }ix;


#debug "----------------------------\n$$body\n-------------------------";
    $quit ++ if $subject =~ $leave_rx;
    $quit ++ if $body =~ $leave_rx;

    ### Continue if sign of quitting
    #
    return unless $quit; ## Get the details

    $quit ++ if $body =~ $CONTACTINFO_REGEX;

    if( $c->is_computer_generated or
        $quit >= 2 )
    {
        debug "Quit points: ".$quit;
        $c->{is}{quit_work} = $quit;
    }

    return;
}


#######################################################################

=head2 is_address_changed

=cut

sub is_address_changed
{
    my( $c ) = @_;
    $c->analyze_address_changed;
    return $c->{is}{address_changed} ? 1 : 0;

}


#######################################################################

=head2 analyze_address_changed

=cut

sub analyze_address_changed
{
    my( $c ) = @_;

    return if $c->{analyzed}{address_changed};
    $c->{analyzed}{address_changed} ++;

    debug "Analyzing for Address changed" if $DEBUG;
#                debug datadump($c,2);
    my $o = $c->email_obj;

    my $subject = trim $o->head->parsed_subject->plain;
    if( $subject =~
        m/   Jag.har.bytt.$EMAIL_LABEL_REGEX
           | I.have.a.new.$EMAIL_LABEL_REGEX
           | Ny.$EMAIL_LABEL_REGEX
           | Fel.$EMAIL_LABEL_REGEX
           | New.$EMAIL_LABEL_REGEX
         /xi )
    {
        $c->{is}{address_changed} ++;
    }

    my $body = trim $o->guess_content_part->body_as_text;
#    debug "TEXT IS:\n$body\n---------------";

    if( $c->is_computer_generated )
    {
	if( $body =~
	    / bytt.$EMAIL_LABEL_REGEX
	  |   $EMAIL_LABEL_REGEX.
	      (kommer.att.upphöra|är.ändrad.till)
	  |   Denna.$EMAIL_LABEL_REGEX.är.numer.stängd
	  |   uppdatera.er.adressbok
	  |   når.du.mig.numera.på
	  |   the.$EMAIL_LABEL_REGEX.has.changed.to
	  |   Please.use.my.new.$EMAIL_LABEL_REGEX
          |   We.have.changed.domain.name.for
          |   Instead.use.$EMAIL_LABEL_REGEX.as.described
	  |   Vi.har.ny.$EMAIL_LABEL_REGEX
	  |   jag.har.flyttad.till
	  |   Min.nya.$EMAIL_LABEL_REGEX
	    /xi )
	{
	    $c->{is}{address_changed} ++;
	    debug "  Matched content text";
	}
    }

    unless( $c->{is}{address_changed} )
    {
        $c->analyze_dsn;

        foreach my $report ( @{$c->{reports}} )
        {
            my $std_reason = $report->header('std_reason') or next;
            if( $std_reason eq 'address_changed' )
            {
                $c->{is}{address_changed} = 1;
                last;
            }
        }
    }


    # Only soft-parse body content if we have other indications of
    # this beeing an DSN
    #
#    debug "Is dsn? ".$c->is_dsn;
#    debug datadump($c,2);
    if( $c->{is}{address_changed} and $c->is_dsn )
    {
        my $old_ea = $c->dsn_for_address;

        debug "Address changed from OLD address ".$old_ea;

        # Remove old ea before searching for new
        $body =~ s/$old_ea//g;

        my $new_ea;

#        debug "Looking for new email address";
#        debug $body;
        if( $body =~ /bytt $EMAIL_LABEL_REGEX till${EMAIL_ADDR_REGEX}/i )
        {
            $new_ea = $1;
        }

        unless( $new_ea )
        {
#            debug "Look for first email address";
            if( $body =~ /${EMAIL_ADDR_REGEX}/ )
            {
                $new_ea = $1;
            }
        }

        unless( $new_ea )
        {
            # Also looks for emails inside tags
            while( $body =~ />(.*?\@.*?)</g )
            {
                if( $1 =~ /${EMAIL_ADDR_REGEX}/ )
                {
                    $new_ea = $1;
                    last;
                }
            }
        }

#        debug "  found $new_ea" if $new_ea;
        if( $new_ea )
        {
            $c->{contact}{email_address}{changed_to} = EA->new($new_ea);
        }
    }

    return;
}


#######################################################################

=head2 is_spam

=cut

sub is_spam
{
    my( $c ) = @_;
    $c->analyze_spam;
    return $c->{is}{spam} ? 1 : 0;

}


#######################################################################

=head2 analyze_spam

=cut

sub analyze_spam
{
    my( $c ) = @_;

    return if $c->{analyzed}{spam};
    $c->{analyzed}{spam} ++;

    debug "Analyzing for Spam" if $DEBUG;
    my $o = $c->email_obj;

    return if $c->is_dsn;


    if( my $flag = $o->header('X-Spam-Flag') )
    {
	if( $flag =~ /yes/i )
	{
	    $c->{is}{spam} = 1;
	    return;
	}
    }
    elsif( my $status = $o->header('X-Spam-Status') )
    {
	if( $status =~ /^yes/i )
	{
	    $c->{is}{spam} = 1;
	    return;
	}
    }
    elsif( my $score = $o->header('X-Spam-Score') )
    {
	if( $score > 2 )
	{
	    $c->{is}{spam} = 1;
	    return;
	}
    }

    return;
}


#######################################################################

=head2 is_personal

A personal email can be auto-generated, but is probably sent from the
address that is talked about in the email, as opposed to DSNs from a
postmaster.

=cut

sub is_personal
{
    my( $c ) = @_;
    $c->analyze_personal;
    return $c->{is}{personal} ? 1 : 0;

}


#######################################################################

=head2 analyze_personal

=cut

sub analyze_personal
{
    my( $c ) = @_;

    return if $c->{analyzed}{personal};
    $c->{analyzed}{personal} ++;

    debug "Analyzing for Personal" if $DEBUG;
    my $o = $c->email_obj;

    return if $c->is_ticket;

    if( $c->is_delivered or $c->is_vacation )
    {
        $c->{is}{personal} = 1;
    }

    if( $c->is_quit_work )
    {
        my $body = trim $o->guess_content_part->body_as_text;

        ### Not personal
        #
        if( $body =~ / The.person
                     |   Den.du..söker
                       /ix )
        {
            $c->{is}{personal} = 0;
            return
        }

        if( $body =~ /   Jag
                       |   min
                       |   mig
                       |   I\s(am|have)
                       /ix )
        {
            $c->{is}{personal} = 1;
            return;
        }
    }

    return if $c->is_auto_reply;

    $c->{is}{personal} = 1 if $c->is_reply;

    return;
}


#######################################################################

sub _extract_reports
{
    my( $text ) = @_;

    my %by_email;

    # we'll assume that the text is made up of:
    # blah blah 0
    #             email@address 1
    # blah blah 1
    #             email@address 2
    # blah blah 2
    #

    # we'll break it up accordingly, and first try to detect a reason
    # for email 1 in section 1; if there's no reason returned, we'll
    # look in section 0.  and we'll keep going that way for each
    # address.

    return unless $text;

    ### Remove non-email-related email-like text
    $text =~ s/Transaction${EMAIL_ADDR_REGEX}failed//i;

#    debug "Extract report from text:\n$text\n---------\n";


    ### Remove emails not being the recipient
    $text =~ s/From\s*:\s*${EMAIL_ADDR_REGEX}//ig;
    $text =~ s/Message-ID:\s*${EMAIL_ADDR_REGEX}//ig;
    $text =~ s/mail address has changed to${EMAIL_ADDR_REGEX}//ig;

    #### Remove contact information
    $text =~ s/${CONTACTINFO_REGEX}.*//s;

    debug "AFTER CLEANUP\n$text\n---------\n" if $DEBUG > 1;


    my @split = split($EMAIL_ADDR_REGEX, $text);

    foreach my $i ( 0 .. $#split )
    {
#        warn "PART $i: ".$split[$i]."\n";

	# only interested in the odd numbered elements, which are the
	# email addressess.
	next if $i % 2 == 0;

	my $email = _cleanup_email($split[$i]);


#	if( $split[$i-1] =~ /they are not accepting mail from/ )
#	{
#	    # aol airmail sender block
#	    warn "aol airmail sender block\n" if $DEBUG;
#	    next;
#	}

	my $std_reason = "unknown";
	$std_reason = _std_reason($split[$i+1]) if $#split > $i;
	$std_reason = _std_reason($split[$i-1]) if $std_reason eq "unknown";

	# todo:
	# if we can't figure out the reason, if we're in the
	# delivery-status part, go back up into the text part and try
	# extract_report() on that.


	# Keep the best reason found so far:
	if( exists $by_email{$email}
	    and
	    $by_email{$email}->{std_reason} ne "unknown"
	    and
	    $std_reason eq "unknown"
	  )
	{
	    next;
	}

	$by_email{$email} =
	{
	 email => $email || '',
	 raw   => join ("", @split[$i-1..$i+1]),
	 std_reason => $std_reason || '',
	};
    }


#    warn "reports to generate:";
#    warn datadump(\%by_email);

    # Try again for reports of malformed addresses
    unless( keys %by_email )
    {
        debug "Look for malformed address";
#        if( $text =~ /^([a-z\@\-\.]+): malformed address/im )
        if( $text =~ /\n\s*<?([a-z\@\-\.]+)>?: malformed address/im )
        {
            $by_email{$1} =
            {
             email => $1 || '',
             raw   => $text,
             std_reason => 'syntax_error',
            };
        }
    }


    my @toreturn;
    foreach my $email (keys %by_email)
    {
        # Use RDF::Base::Email::Head/create instead of new
	my $report = RDF::Base::Email::Head->new("raw: -\r\n\r\n");
#	debug "***** Creating a new report";
	foreach my $key ( keys %{$by_email{$email}} )
	{
#	    debug "  setting $key = $by_email{$email}{$key}";
	    $report->header_set($key => $by_email{$email}{$key});
	}

	push @toreturn, $report;
    }


    return @toreturn;
}


#######################################################################

sub _std_reason
{
    local $_ = shift;

    if( /(?:domain|host)\s+(?:not\s+found|unknown)/i )
    {
	return "domain_error";
    }

    if(
       /try.again.later/is or
       /mailbox\b.*\bfull/ or
       /storage/i          or
       /quota/i            or
       /\s552\s.*quota/i   or
       /\s#?5\.2\.2\s/                                  # rfc 1893
      )
    {
	return "over_quota";
    }

    my $user_re =
      qr'(?: mailbox  | user | recipient | address (?: ee)?
          | customer | account | e-?mail | <? $EMAIL_ADDR_REGEX >? )'ix;

    if(
       /\s \(? \#? 5\.1\.[01] \)? \s/x or                  # rfc 1893
       /\s \(? \#? 5\.2\.1 \)? \s/x or                    # rfc 1893 disabled
       /$user_re\s+ (?:\S+\s+)? (?:is\s+)?                 # Generic
         (?: (?: un|not\s+) (?: known | recognized )
           | [dw]oes\s?n[o']?t
           (?: exist|found ) | disabled | expired ) /ix or
       /no\s+(?:such\s+)?$user_re/i or                     # Gmail and other
       /inactive user/i or                                 # Outblaze
       /unknown local part/i or                            # Exim(?)
       /user\s+doesn't\s+have\s+a/i or                     # Yahoo!
       /account\s+has\s+been\s+(?:disabled|suspended)/i or # Yahoo!
       /$user_re\s+(?:suspended|discontinued)/i or         # everyone.net / other?
       /unknown\s+$user_re/i or                            # Generic
       /$user_re\s+(?:is\s+)?(?:inactive|unavailable)/i or # Hotmail, others?
       /(?:(?:in|not\s+a\s+)?valid|no such)\s$user_re/i or # Various
       /$user_re\s+(?:was\s+)?not\s+found/i or             # AOL, generic
       /$user_re \s+ (?:is\s+)? (?:currently\s+)?
         (?:suspended|unavailable)/ix or                   # ATT, generic
       /address is administratively disabled/i or          # Unknown
       /no $user_re\s+(?:here\s+)?by that name/i or        # Unknown
       /<?$EMAIL_ADDR_REGEX>? is invalid/i or              # Unknown
       /address.*not known here/i or                       # Unknown
       /recipient\s+(?:address\s+)?rejected/i or           # Cox, generic
       /not\s+listed\s+in\s+Domino/i or                    # Domino
       /account not activated/i or                         # usa.net
       /not\s+our\s+customer/i or                          # Comcast
       /doesn't handle mail for that user/i or             # mailfoundry
       /Unrouteable address/i or                           # Exim
       /550 this email address does not exist/i or         # (?)
       /non-existent address/i or                          # qmail
       /The name was not found at the remote site/i or     # FC
       /Delivery failed for the following recipient/i or   # bigfish
       /Denna $EMAIL_LABEL_REGEX anv..?nds inte/i or              # Generic
       /Denna $EMAIL_LABEL_REGEX genererar inget svar/i or        # Generic
       /does not exists in this domain/i or                       # Generic
       /Several matches found/i or                                # Lotus Domino
       /Den här $EMAIL_LABEL_REGEX är ej längre i bruk/i or       # Generic
       /Den $EMAIL_LABEL_REGEX du angivit finns inte/i or         # Generic
       /Deleted $EMAIL_LABEL_REGEX/i or                           # Generic
       /The recipient does not exist/i or                         # Generic
       /This $EMAIL_LABEL_REGEX no longer accepts mail/i or       # Generic
       /Please verify the accuracy of the $EMAIL_LABEL_REGEX/i or # Generic
       /deactivated mailbox/i or                                  # Generic
       /ディレクトリには見つかりません/i or
       /fBNgÉÍ©Â©èÜ¹ñB/            # Jaapanese:It is not found in the directory
      )
    {
	return "user_unknown";
    }

    if(
       /domain\s+syntax/i or
       /timed\s+out/i or
       /route\s+to\s+host/i or
       /connection\s+refused/i or
       /no\s+data\s+record\s+of\s+requested\s+type/i or
       /\s550 authentication\s/ or
       /\s550 not local host\s/ or
       /\b#?5\.4\.\d\b/ or
      /\b#?5\.1\.2\b/ or
       /\snon-existent hosts\s/ or
       /Cannot find OUTBOUND MX Records for domain/
      )
    {
	return "domain_error";
    }

    if(
       /\b#?5\.7\.(0|1)\b/
      )
    {
	return "denied";
    }

    if(
       /\b#?5\.5\.2\b/ or
       /\bmalformed address\b/ or
       /\bdomain missing or malformed\b/ or
       /\bincorrectly constructed\b/
      )
    {
	return "syntax_error";
    }

    if(
       /\b#?5\.1\.6\b/
      )
    {
	return "address_changed";
    }

    if(
       /entry does not specify a valid .{0,10}mail file/ or
       /forwarding loop/ or
       /Maximum hop count/i or
       /too many hops/i or
       /has not yet been delivered/i
      )
    {
	return "delayed";
    }

#    warn "  UNKNOWN reason\n<<<$_>>>\n";

    return "unknown";
}

#######################################################################

sub _cleanup_email
{
    local $_ = shift;

#    warn "CLEANUP EMAIL $_\n";

    chomp;
    # Get rid of parens around addresses like (luser@example.com)
    # Got rid of earlier /\(.*\)/ - not sure what that was about - wby
    tr/[()]//d;
    s/^To:\s*//i;
    s/[.:;]+$//;
    s/<(.+)>/$1/;
    # IMS hack: c=US;a= ;p=NDC;o=ORANGE;dda:SMTP=slpark@msx.ndc.mc.uci.edu; on
    # Thu, 19 Sep...
    s/.*:SMTP=//;
    s/^\s+//;
    s/\s+$//;
    # hack to get rid of stuff like "luser@example.com...User"
    s/\.{3}\S+//;
    # SMTP:foo@example.com
    s/^SMTP://;
    # 554-Address:foo@example.com
    s/^554-Address://;

    return $_;
}


#######################################################################

=head2 bounce_reports

=cut

sub bounce_reports
{
    return @{$_[0]->{'reports'}};
}


#######################################################################

=head2 new_report

=cut

sub new_report
{
    my( $c, $data ) = @_;
    $data ||= {};

    # Use RDF::Base::Email::Head/create instead of new
    my $report = RDF::Base::Email::Head->new("raw: -\r\n\r\n");

    foreach my $key (keys %$data)
    {
	unless( $REPORT_FIELDS{$key} )
	{
	    datadump(\%REPORT_FIELDS);
	    confess "Not a valid report field: $key";
	}

	my $val = $data->{$key};
	$report->header_set($key => $val);
#	warn "  $key: $val\n" if $DEBUG;
    }

    push @{$c->{'reports'}}, $report;
    return $report;
}


#######################################################################

=head2 reports

=cut

sub reports
{
    return @{$_[0]->{reports}};
}


#######################################################################

=head2 dsn_for_address

=cut

sub dsn_for_address
{
    my( $c, $guess ) = @_;

    return undef unless $c->is_dsn;

    my $o = $c->email_obj;

#    debug "dsn_for_address";
    debug $o->viewtree if $DEBUG > 1;
#    debug "Path: ".$o->path;

#    debug datadump( $o->{struct}, 8);

    # If there is a report, use it as the base
    if( my $report = $o->first_part_with_type('multipart/report') )
    {
        debug "Using the report as the base for finding address" if $DEBUG;
        $o = $report;
    }

    my( $adr, $backup_adr );

    $c->analyze_verp;
    if( my $ea = $c->{contact}{email_address}{node} )
    {
	return $ea->address;
    }

    if( my $eml = $o->first_subpart_with_type("message/rfc822") )
    {
        debug "  found part:\n".$eml->desig if $DEBUG;
	my $to = $eml->head->parsed_address('to')->get_first_nos->address;
        debug"FOUND TO $to" if $DEBUG;
	return $to if $to;
    }

    ### Parsing subject and content
    #
    my $subject = trim $o->head->parsed_subject->plain;
    if( $subject =~ /message to ${EMAIL_ADDR_REGEX}/ )
    {
	$adr = $1;
	undef $adr if EA->is_nonhuman($adr);
	return $adr if $adr;
    }

    if( my $part = $o->first_non_multi_part )
    {
#        debug "BODY:\n".${ $part->body } ."\n-----------------------";

        my $body = trim $part->body_as_text;
	if( $body
            =~ m/   Original.Message.+?^\s*To:\s(.+?)\n
                |    meddelande.som.genererades.för\s(.+?)\n
                /xsmi )
	{
	    if( my $node = EA->exist( $1 ) )
	    {
		$c->{contact}{email_address}{node} = $node;
		debug "Got recipient ".$node->desig;
		return $node->address;
	    }
	}
    }


    $c->analyze_bounce;
    foreach my $report ( @{$c->{reports}} )
    {
	my $std_reason = $report->header('std_reason');
        next unless $std_reason;
        $backup_adr = $report->header('email') or next;
        next if $std_reason eq 'unknown' and $c->{is}{bounce_guess};

        my $new_adr = $backup_adr;

        if( EA->is_nonhuman($new_adr) )
        {
            debug "Ignoring $new_adr";
            next;
        }

        if( $adr )
        {
            debug "Not knowing which address to use";
            debug "  $adr or $new_adr";
        }

        debug "Got dsn address from reports" if $DEBUG;

        $adr = $new_adr;
    }

    if( $guess ) # Accept address from guess
    {
        debug "  Guessing DSN email address" if $DEBUG;
        unless( $c->is_personal )
        {
            debug "  from uncertain reports" if $DEBUG;
            $adr = $backup_adr;
        }

	unless( $adr )
	{
            debug "  from sender" if $DEBUG;
            $adr = $c->sender_email_address;
	}
    }

    return undef unless $adr;
    return undef if EA->is_nonhuman($adr);

    debug "Found dsn for address $adr" if $DEBUG;

    return $adr;
}


#######################################################################

sub email_obj
{
    return $_[0]->{'email_obj'};
}

#######################################################################

sub sender_email_address
{
    my( $c ) = @_;

    my $o =  $c->email_obj;

    if( $o->header('From') =~ /${EMAIL_ADDR_REGEX}/ )
    {
        return $1;
    }

    foreach my $recieved ( $o->header('Received') )
    {
        if( $recieved =~ /envelope-from ${EMAIL_ADDR_REGEX}/i )
        {
            return $1;
        }
    }

    if( $o->header('Return-path') =~ /${EMAIL_ADDR_REGEX}/ )
    {
        return $1;
    }

    return undef;
}

#######################################################################

sub dsn_for_address_node
{
    my( $c, $guess ) = @_;

    return undef unless $c->is_dsn;

    $c->analyze_verp;
    my $ea = $c->{contact}{email_address}{node};

    unless( $ea )
    {
        my $ea_string = $c->dsn_for_address( $guess );
        return unless $ea_string;
        $ea = EA->new( $ea_string );
        $c->{contact}{email_address}{node} = $ea;
    }

    return $ea;
}

#######################################################################

sub dsn_std_reason
{
    my( $c ) = @_;

    $c->analyze_bounce;
    my $reason = '';

    foreach my $report ( @{$c->{reports}} )
    {
        my $new_reason = $report->header('std_reason');

        $reason ||= $new_reason;

        unless( $new_reason eq 'unknown')
        {
            $reason = $new_reason;
        }
    }

    return $reason;
}

#######################################################################

sub dsn_date
{
    my( $c ) = @_;

    return $c->{dsn_date} if $c->{dsn_date};

    $c->analyze_bounce;

    foreach my $report ( @{$c->{reports}} )
    {
        if( my $date = $report->header('arrival-date') )
        {
            return $c->{dsn_date} = LT->get($date);
        }
    }

    if( my $date = $c->email_obj->header('Delivery-date') )
    {
        return $c->{dsn_date} = LT->get($date);
    }

    if( my $date = $c->email_obj->header('Date') )
    {
        return $c->{dsn_date} = LT->get($date);
    }

    return $c->{dsn_date} = is_undef;
}

#######################################################################

sub dsn_date_availible
{
    my( $c ) = @_;

    $c->analyze_vacation;

    return $c->{contact}{date_availible};
}

#######################################################################

sub _extract_from_reports
{
    my( $c ) = @_;

    foreach my $report ( @{$c->{reports}} )
    {
	my $std_reason = $report->header('std_reason') or next;
        next if $std_reason eq 'unknown';

        if( $std_reason eq 'delayed' )
        {
            $c->{is}{transient} = 1;
        }
        elsif( $std_reason eq 'over_quota' )
        {
            $c->{is}{transient} = 1;
        }
        else
        {
            $c->{is}{bounce} = 1;
        }

        return;
    }

    return;
}

#######################################################################

=head2 as_html

=cut

sub as_html
{
    my( $c ) = @_;

    my $out = "";

    my $found = 0;
    foreach my $test (qw( vacation
			  address_changed
			  quit_work
			  spam
			  delivered
                          unsubscribe
                          newsletter
		       ))
    {
        my $call = 'is_'.$test;
        if( $c->$call )
        {
	    $found ++;
            $out .= $test . " ";
        }
    }

    unless( $found )
    {
        if( ($c->dsn_std_reason||'unknown') ne 'unknown' )
        {
            return $c->dsn_std_reason;
        }

	foreach my $test (qw( dsn
			      auto_reply
			      computer_generated
			      reply
			   ))
	{
	    my $call = 'is_'.$test;
	    if( $c->$call )
	    {
		$found ++;
                $out .= $test;
                last;
	    }
	}
    }

    return $out;
}

#######################################################################

1;
