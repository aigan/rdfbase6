package RDF::Base::Email::Classifier;

=head1 NAME

RDF::Base::Email::Classifier - Analyzes and classifies emails

=cut

use 5.010;
use strict;
use warnings;
use utf8;

use Carp qw( croak confess cluck );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug datadump );

our $DEBUG = 1;

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
);
my %REPORT_FIELDS; for(@REPORT_FIELDS){$REPORT_FIELDS{$_}=1};



=head1 DESCRIPTION

Based on L<Mail::DeliveryStatus::BounceParser>

dsn std_reason mapping:

user_unknown => 5.1.0, 5.1.1
domain_error => 5.1.2
over_quota   => 5.2.2
syntax_error => 5.5.2
denied       => 5.7.1
address_changed => 5.1.6
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

  Email::Classifier->new( $email )

C<$email> should be an object compatible with L<Email::MIME> 1.861

contact fields:
  {contact}{email_address}{node}
  {contact}{email_address}{changed_to}

=cut

sub new
{
    my( $this, $email ) = @_;
    my $class = ref($this) || $this;

#    warn "new Classifier object\n" if $DEBUG;

    my $c = bless
    {
     email => $email,
     reports => [],
     is => {},
     analyzed => {},
     ticket => undef, # original email/ticket node
     contact => {}, # Contact information gathered
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
    return $c->{'is'}{'dsn'} ? 1 : 0;
}


#######################################################################

=head2 analyze_dsn

=cut

sub analyze_dsn
{
    my( $c ) = @_;

    return if $c->{analyzed}{dsn};
    $c->{analyzed}{dsn} ++;

    my $e = $c->email;
    if( $e->header('Auto-Submitted') )
    {
        $c->{is}{dsn} ++;
        return;
    }

    if( $e->head->parsed_subject =~ /^(tack f..?r|autosvar|Autoreply)/i )
    {
        $c->{is}{dsn} ++;
        return;
    }

    return if $c->is_bounce;
    return if $c->is_vacation;
    return if $c->is_address_changed;

    if( ${$e->first_non_multi_part->body} =~ /automatiskt meddelande/ )
    {
        $c->{is}{dsn} ++;
    }
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

    my $e = $c->email;
    debug "Analyzing for Ticket" if $DEBUG;

    $c->{is}{ticket} = 1
      if $e->head->parsed_subject =~ /^\[[^\]]*#[^\]]+\]/;

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

    my $e = $c->email;
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
    return if $e->effective_type eq 'multipart/report';

    my $outrx = qr/semester|vacation|(out|away|on holiday).*office/i;

#    debug "v1";
    $c->{is}{vacation} = 1
      if $e->head->parsed_subject =~ /(^Fr.{1,2}nvaro:|borta från kontoret)/;
#    debug "v2 ".$c->{is}{vacation};

    $c->{is}{vacation} = 1
      if $e->head->parsed_subject =~ $outrx;
#    debug "v3 ".$c->{is}{vacation};

    my $first_part = $e->first_part_with_type("text/plain");
    return if !$first_part || $first_part->effective_type ne 'text/plain';

    my $string = ${ $first_part->body };
    return if length($string) > 3000;

    $c->{is}{vacation} = 1
      if $string =~ $outrx;
#    debug "v4 ".$c->{is}{vacation};

    $c->{is}{dsn} = 1;

    return 1;
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

    my $e = $c->email;
    debug "Analyzing for Bounce" if $DEBUG;

    #
    # try to extract email addresses to identify members.
    # we will also try to extract reasons as much as we can.
    #
    if( $e->effective_type eq "multipart/report" )
    {
	$c->analyze_multipart_report;
        return if $c->reports;
    }

    $c->analyze_verp;


    # Only try to guess bounce report if we belive this realy could be
    # a bounce message

    my $common_subjects = qr/ failure[ ]?notice
                          | undeliverable
                          | delivery[ ]?failure
                            /ix;

    if( $e->header('Auto-Submitted') or
	$e->header('From') =~ /mailer-daemon|postmaster/i or
	$e->header('Subject') =~ $common_subjects
      )
    {
        return $c->analyze_bounce_guess;
    }

    return 1;
}


#######################################################################

=head2 analyze_verp

VERP = Variable envelope return path

=cut

sub  analyze_verp
{
    my( $c ) = @_;

    return if $c->{analyzed}{verp};
    $c->{analyzed}{verp} ++;

    my $e = $c->email;
    debug "Analyzing for VERP" if $DEBUG;

    my $to =  $e->head->parsed_address('to') ;
    my $be = $Para::Frame::CFG->{'bounce_emails'} or return;
    if( $to->address =~ /.+$be$/i  )
    {
        if( $to->address =~ /t(\d+)-/i )
        {
            $c->{ticket} = RDF::Base::Resource->get($1);
            debug "Got ticket ".$c->{ticket}->desig;
        }

        if( $to->address =~ /r(\d+)-/i )
        {
            my $node = RDF::Base::Resource->get($1);
            $c->{contact}{email_address}{node} = $node;
            debug "Got recipient ".$node->desig;
        }

        $c->{is}{dsn} = 1;
    }

    return;
}


#######################################################################

=head2 analyze_multipart_report

=cut

sub  analyze_multipart_report
{
    my( $c ) = @_;

    return if $c->{analyzed}{multipart_report};
    $c->{analyzed}{multipart_report} ++;

    my $e = $c->email;
    debug "Analyzing multipart/report" if $DEBUG;

    my($delivery_status) =
      $e->first_part_with_type("message/delivery-status");
    return 0 unless $delivery_status;

    my %global =
      (
       "reporting-mta" => undef,
       "arrival-date"  => undef,
      );

    my( $seen_action_expanded, $seen_action_failed );


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
	      $report_in->as_string;
	}


	# Some MTAs send unsought delivery-status notifications
	# indicating success; others send RFC1892/RFC3464 delivery
	# status notifications for transient failures.

	if( my $action = lc $report_in->header('Action'))
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
		    $seen_action_expanded = 1;
		}
		elsif( $action eq 'failed' )
		{
		    $seen_action_failed   = 1;
		}
		else
		{
		    warn("message/delivery-status says 'Action: $1'")
		      if $DEBUG;
		    $c->{is}{bounce} = 0;
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

	    if( $status =~ /^5\.1\.[01]$/ )
	    {
		$report{std_reason} = "user_unknown";
	    }
	    elsif( $status eq "5.1.2" )
	    {
		$report{std_reason} = "domain_error";
	    }
	    elsif( $status eq "5.2.2" )
	    {
		$report{std_reason} = "over_quota";
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

        debug "Host: ".$report{host};
        debug "Reporting MTA: ".$global{'reporting-mta'};

	warn "Reason found in report: $report{std_reason}\n" if $DEBUG;

	$c->new_report(\%report);

    } # END foreach $para


    if( $seen_action_expanded && !$seen_action_failed )
    {
	# We've seen at least one 'Action: expanded' DSN-field,
	# but no 'Action: failed'

	warn("message/delivery-status says 'Action: expanded'\n")
	  if $DEBUG;
	$c->{is}{bounce} = 0;
	return 1;
    }

    $c->{is}{bounce} = 1;
    $c->{is}{dsn} = 1;

    return 1;
}


#######################################################################

=head2 analyze_bounce_guess

Only if we think that it may be a bounce, but not in a standard format

=cut

sub analyze_bounce_guess
{
    my( $c ) = @_;

#    return if $c->{analyzed}{bounce_guess};
#    return if $c->{analyzed}{bounce};
    $c->{analyzed}{bounce_guess} ++;

    my $e = $c->email;
    debug "Analyzing for Bounce - guessing" if $DEBUG;

    if( $e->effective_type =~ /multipart/i )
    {
	# but not a multipart/report.  look through each non-message/*
	# section.  See t/corpus/exchange.unknown.msg

	my @delivery_status_parts =
	  grep{ $_->content_type =~ m{text/plain}i } $e->parts;

	warn "Trying to extract reports from multipart message\n"
	  if $DEBUG;

	foreach my $status_part ( @delivery_status_parts )
	{
	    my $text = ${$status_part->body};

            if( $text =~ $RETURNED_MESSAGE_BELOW )
            {
                warn "Matching RETURNED_MESSAGE_BELOW\n" if $DEBUG;
                my ($stuff_before, $stuff_splitted, $stuff_after) =
                  split $RETURNED_MESSAGE_BELOW, $text, 3;
                push @{$c->{reports}}, _extract_reports($stuff_before);
                # TODO: Set up $c->{'orig_message'}
            }
            else
            {
                push @{$c->{reports}}, _extract_reports($text);
            }
	}
    }
    elsif( $e->effective_type =~ m{text/plain}i )
    {
	# handle plain-text responses

	# This used to just take *any* part, even if the only part
	# wasn't a text/plain part
	#
	# We may have to specifically allow some other types, but in
	# my testing, all the messages that get here and are actual
	# bounces are text/plain wby - 20060907

	# they usually say "returned message" somewhere, and we can
	# split on that, above and below.

	warn "Trying to find report in single text/plain body\n"
	  if $DEBUG;

	my $body_string = ${$e->body};

#        warn $body_string;
#        die "DEBUG";

	if( $body_string =~ $RETURNED_MESSAGE_BELOW )
	{
	    warn "Matching RETURNED_MESSAGE_BELOW\n" if $DEBUG;
	    my ($stuff_before, $stuff_splitted, $stuff_after) =
	      split $RETURNED_MESSAGE_BELOW, $body_string, 3;

	    push @{$c->{reports}}, _extract_reports($stuff_before);

	    # TODO: Set up $c->{'orig_message'}
	}
	elsif( $body_string =~ /(.+)\n\n(.+?Message-ID:.+)/is )
	{
	    warn "Matching Message-ID string\n" if $DEBUG;
	    push @{$c->{reports}}, _extract_reports($1);
	}
	else
	{
	    warn "  looking at the whole part\n" if $DEBUG;
	    push @{$c->{reports}}, _extract_reports($body_string);
	}
    }

    foreach my $report ( @{$c->{reports}} )
    {
	my $std_reason = $report->header('std_reason') or next;
        if( $std_reason ne 'unknown' )
        {
            $c->{is}{bounce} = 1;
            $c->{is}{dsn} = 1;
            $c->{is}{bounce_guess} = 1;
            return;
        }
    }

    return 1;
}


#######################################################################

=head2 is_address_changed

=cut

sub is_address_changed
{
    my( $c ) = @_;
    $c->analyze_address_changed;
    return $c->{'is'}{'address_changed'} ? 1 : 0;

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
    my $e = $c->email;

    if( $e->head->parsed_subject =~ /^Jag har bytt e-postadress/i )
    {
        $c->{is}{address_changed} ++;
    }

    my $textref = $e->first_non_multi_part->body;

    if( $$textref =~ /bytt e-postadress till/ )
    {
        $c->{is}{address_changed} ++;
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

    if( $c->{is}{address_changed} )
    {
        $c->{is}{dsn} = 1;

        debug "Looking for new email address";
#        debug $$textref;
        if( $$textref =~ /bytt e-postadress till${EMAIL_ADDR_REGEX}/i )
        {
            debug "  found $1";
            $c->{contact}{email_address}{changed_to} = $1;
        }
    }



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

    debug "Extract report from text:\n$text\n---------\n";

    return unless $text;

    ### Remove non-email-related email-like text
    $text =~ s/Transaction${EMAIL_ADDR_REGEX}failed//;


    my @split = split($EMAIL_ADDR_REGEX, $text);

    foreach my $i ( 0 .. $#split )
    {
        warn "PART $i: ".$split[$i]."\n";


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
        if( $text =~ /\n\s*([a-z\@\-\.]+): malformed address/im )
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
	my $report = RDF::Base::Email::Head->new("");
#	warn "Creating a new report";
	foreach my $key ( keys %{$by_email{$email}} )
	{
#	    warn "  setting $key = $by_email{$email}{$key}";
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
       /550 this email address does not exist/ or          # (?)
       /non-existent address/                              # qmail
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
       /\snon-existent hosts\s/
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

    my $report = RDF::Base::Email::Head->new("");

    foreach my $key (keys %$data)
    {
	unless( $REPORT_FIELDS{$key} )
	{
	    datadump(\%REPORT_FIELDS);
	    confess "Not a valid report field: $key";
	}

	my $val = $data->{$key};
	$report->header_set($key => $val);
	warn "  $key: $val\n" if $DEBUG;
    }

    push @{$c->{'reports'}}, $report;
    $c->{is}{bounce} = 1;
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
    my( $c ) = @_;

    return undef unless $c->is_dsn;

    my $adr;

    foreach my $report ( @{$c->{reports}} )
    {
	my $std_reason = $report->header('std_reason');
        next unless $std_reason;
        next if $std_reason eq 'unknown';

        $adr = $report->header('email') or next;
        last;
    }

    $adr ||= $c->email->header('From');

    return undef if $adr =~ /mailer-daemon|postmaster/i;


    return $adr;
}


#######################################################################

sub email
{
    return $_[0]->{'email'};
}

#######################################################################

1;
