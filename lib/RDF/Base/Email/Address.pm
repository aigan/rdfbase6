package RDF::Base::Email::Address;
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

RDF::Base::Email::Address

=cut

use 5.010;
use strict;
use warnings;
#use experimental qw(smartmatch); # Not working before 5.18
#no warnings 'experimental::smartmatch'; # Not working before 5.18
use constant C => 'RDF::Base::Constants';
use constant LEA => 'RDF::Base::Literal::Email::Address';
use feature "switch";
use CGI qw( escapeHTML );


use Carp qw( cluck confess longmess croak );
use Mail::Address;
use DateTime::Duration;

use Para::Frame::Widget qw( input );
use Para::Frame::Email::Address;
use Para::Frame::Reload;
use Para::Frame::Time qw( now );
use Para::Frame::Utils qw( debug datadump catch );

use RDF::Base::Utils qw( parse_propargs solid_propargs is_undef );
use RDF::Base::Email::Classifier;
use RDF::Base::Widget qw( aloc build_field_key locnl);

use RDF::Base::Constants qw( $C_intelligent_agent
                             $C_email_address_holder
                             $C_ed_non_deliverable );

=head1 DESCRIPTION

Represents an Email Address

=cut


#########################################################################
################################  Constructors  #########################

=head2 Constructors

These can be called with the class name or any List object.

=cut

##############################################################################

=head3 new

  $this->new( $value, $args )

Calls L<Para::Frame::Email::Address/new>

Will B<not> throw an exception if email address is faulty

=cut

  ;# cperl formatting

sub new
{
    my( $class, $in_value, $args ) = @_;

    my $a = LEA->parse($in_value);


    my $code_in = $a->address;
    unless( $code_in )
    {
        cluck "empty email address";
        return is_undef;
    }

    my $code = lc $code_in;

    my $an_args = solid_propargs({
                                  default_create =>
                                  {
                                   ea_original => $a,
                                   name => $a->name,
                                  }
                                 });

    my $an = RDF::Base::Resource->set_one({
                                           code=>$code,
                                           is=>$C_email_address_holder,
                                          }, $an_args);

#    $an->update({ea_original => $a}, $an_args);
#    $an->update({name => $a->name}, $an_args) if $a->name;
#    cluck "Name changed to ".$a->name if $a->name;

    return $an;
}


##############################################################################

=head3 exist

  $this->exist( $value, $args )

Returns the node if existing, else undef

=cut

sub exist
{
    my( $class, $in_value, $args ) = @_;

#    debug "parsing ".datadump($in_value,1);
    my $a = LEA->parse($in_value);

#    debug "parsed to ".datadump($a,1);

    my $code_in = lc $a->address;

    my $an_args = solid_propargs();

    return RDF::Base::Resource->find({
                                      code=>$code_in,
                                      is=>$C_email_address_holder,
                                     }, $an_args)->get_first_nos;
}


##############################################################################

=head2 wuirc

=cut

sub wuirc
{
    return RDF::Base::Literal::String::wuirc(@_);
}

sub wuirc_disabled
{
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";

    my $predname;
    if ( ref $pred )
    {
        $predname = $pred->label;
    }
    else
    {
        $predname = $pred;
        $pred = RDF::Base::Pred->get_by_label($predname);
    }

#    debug "  $predname for ".$subj->sysdesig;

    my $divid = $args->{divid};
    my $size = $args->{'size'} ||"";
    my $wide_class = $size ? '' : ' wide';


    $args->{'id'} ||= build_field_key({
                                       pred => $predname,
                                       subj => $subj,
                                      });

    my $disabled = $args->{'disabled'}||'';
    my $arcversions =  $subj->arcversions($predname);
    my @arcs = map RDF::Base::Arc->get($_), keys %$arcversions;
    my $list_weight = 0;

    my $multi = $args->{'multi'} // not $pred->range_card_max_1;

    my $onchange = "";  #"RDF.Base.pageparts['$divid'].node_update()";


    my $columns = $args->{'columns'} ||
      $class->table_columns( $pred, $args );
    push @$columns, '-edit_link';
    $args->{'columns'} = $columns;
    $args->{'source'} = $subj;




    foreach my $arc ( RDF::Base::List->new(\@arcs)->sorted([{on=>'obj.weight', dir=>'desc'}])->as_array )
    {
        my $arc_id = $arc->id;

        # Maby show weight

        if ( $Para::Frame::U->has_root_access and
             ( (@{$arcversions->{$arc_id}} > 1) or
               $arcversions->{$arc_id}[0]->submitted ) )
        {
            # TODO: Handle new/submitted/removed arcs
            die "Implement multiple versions";
        }

        my $field = build_field_key({arc => $arc});
        $args->{id} = $field;

        my $fargs =
        {
         class => $args->{'class'},
         size => $size,
         maxlength => $args->{'maxlength'},
         onchange => $onchange,
         arc => $arc->id,
        };

        if ( $disabled )
        {
            $out .= "<table class=\"wuirc\">\n";
            $out .= $arc->table_row( $args );

#            $out .= $arc->value->as_html({method=>'address'});
        }
        else
        {
            $out .= "<table class=\"wuirc text_input$wide_class\">\n";
            $out .= $arc->table_row( $args );

#            my $val = $arc->value;
#            $out .= input($field, $val->code->plain, {tag_attr=>$fargs});
#            $out .= ' '.$val->deliverability_as_html($args);
        }
#        $out .= "&nbsp;" . $arc->edit_link_html;
#        $out .= "<br>";
        $out .= "</table>\n";
     }

    if ( ($multi or not @arcs) and not $disabled )
    {
        my $props =
        {
         pred => $predname,
         subj => $subj,
        };

        my $default = '';
        if ( my $def = $args->{default_value} )
        {
            $default = $def->address;
        }

        $out .= input( build_field_key($props),
                       $default,
                       { tag_attr =>
                         {
                          class => $args->{'class'},
                          size => $size,
                          maxlength => $args->{'maxlength'},
                          id => $args->{'id'},
                          onchange => $onchange,
                         }});
    }


    return $out;
}

##############################################################################

=head2 table_columns

  $n->table_columns()

=cut

sub table_columns
{
    return ['arc_weight','-.action_icon','-input','deliverability_as_html'];
}


##############################################################################

=head2 action_icon

  $n->action_icon()

=cut

sub action_icon
{
    my( $ea ) = @_;

    if( !ref $ea or $ea->broken  )
    {
        return '<i class="broken">@</i>';
    }
    else
    {
        return sprintf '<a href="%s" title="%s">@</a>',
          escapeHTML($ea->format), escapeHTML(locnl('Send email'));
    }
}


##############################################################################

sub find_by_string
{
    my( $node, $value, $props_in, $args) = @_;

#    my $class = ref $node;
#    debug "Class $class";


    return RDF::Base::Email::Address->new( $value, $args );
}

##############################################################################

sub parse
{
    my( $node, $value, $args) = @_;

    return RDF::Base::Email::Address->new( $value, $args );
}

##############################################################################
##############################################################################

=head2 move_agent_to

  $old->move_agent_to( $new_email_address, \%args )

TODO: Handle different classes of email addresses

=cut

sub move_agent_to
{
    my( $ea_old, $new_in, $args ) = @_;

    my $ea_new = $ea_old->parse( $new_in, $args );

    debug sprintf "MOVE AGENT from %s to %s", $ea_old->desig, $ea_new->desig;

    foreach my $arc ( $ea_old->revarc_list('has_email_address_holder',
                                           undef, $args)->as_array )
    {
        debug "Should move ".$arc->sysdesig;
    }

    $ea_old->update({'has_email_deliverability'=>
                     C->get('ed_address_changed')}, $args);

    return;
}
##############################################################################

sub broken
{
    my( $ea ) = @_;

    my $lea = $ea->first_prop('ea_original');;

    return 1 if $lea->broken;

    return 1 if $ea->first_prop('has_email_deliverability',
                                $C_ed_non_deliverable );

    return 0;

}


##############################################################################

sub error_message
{
    # TODO: Combine parsing error with deliverability status

    my $o = $_[0]->first_prop('ea_original');
    return $o ? $o->error_message() : 'not an email address';
}

##############################################################################

sub as_string
{
    return $_[0]->first_prop('code')->plain;
}

##############################################################################

sub original
{
    my $o = $_[0]->first_prop('ea_original');
    return $o ? $o->original : undef;
}

##############################################################################

sub user
{
    return $_[0]->first_prop('name')->plain;
}

##############################################################################

sub address
{
    return $_[0]->first_prop('code')->plain;
}

##############################################################################

sub host
{
    return $_[0]->first_prop('ea_original')->host;
}

##############################################################################

sub format
{
    my( $ea ) = shift @_;
    return $ea->first_prop('ea_original')->format(@_);
}

##############################################################################

sub format_mime
{
    my( $ea ) = shift @_;
    return $ea->first_prop('ea_original')->format_mime(@_);
}

##############################################################################

sub format_human
{
    my( $ea ) = @_;

    my $name = $ea->first_prop('name');

    if ( $name )
    {
        return sprintf "%s <%s>", $name, $ea->first_prop('code');
    }
    else
    {
        return $ea->first_prop('code');
    }
}

##############################################################################

sub phrase
{
    shift->first_prop('ea_original')->phrase(@_);
}

##############################################################################

sub comment
{
    return shift->first_prop('ea_original')->comment(@_);
}

##############################################################################

sub desig
{
    my( $ea ) = shift @_;

#    my $o = 

#    debug "desig for ".$ea->id;
#    debug "  original: ".$ea->first_prop('ea_original');
#    debug datadump($ea->first_prop('ea_original'),1);
#    return "--fixme--";

    return $ea->first_prop('ea_original')->format(@_);
}

##############################################################################

=head2

Returns the plain address

=cut

sub shortdesig
{
    return shift->address(@_);
}

##############################################################################

#sub sysdesig
#{
#    return shift->first_prop('ea_original')->sysdesig();
#}

##############################################################################

sub literal
{
    return shift->first_prop('ea_original')->literal();
}

##############################################################################

sub loc
{
    return shift->first_prop('ea_original')->loc();
}

##############################################################################

sub plain
{
    return shift->first_prop('code')->plain;
}

##############################################################################

=head2 as_html

=cut

sub as_html
{
    my( $ea, $args ) = @_;

    my $out = $ea->first_prop('ea_original')->as_html($args);
    $out .= " ".$ea->deliverability_as_html($args);

    return $out;
}

##############################################################################

=head2 deliverability_as_html

=cut

sub deliverability_as_html
{
    my( $ea, $args ) = @_;

    my $status;

    if ( $ea->broken )
    {
        $status = 'ed_broken';
    }
    elsif ( $ea->has_email_deliverability('ed_agent_away') )
    {
        $status = 'ed_agent_away';
    }
    elsif ( $ea->has_email_deliverability('ed_deliverable') )
    {
        $status = 'ed_deliverable';
    }
    elsif ( $ea->has_email_deliverability('ed_delayed') )
    {
        $status = 'ed_delayed';
    }
    elsif ( $ea->has_email_deliverability('ed_address_changed') )
    {
        $status = 'ed_address_changed';
    }
    elsif ( $ea->has_email_deliverability('ed_unclassified') )
    {
        $status = 'ed_unclassified';
    }
    else
    {
        $status = 'ed_unknown';
    }

    return sprintf '<a href="%s" class="fa fa-circle %s" title="%s"></a>', $ea->form_url($args), $status, escapeHTML locnl $status;
}

##############################################################################

=head2 update_deliverability

=cut

sub update_deliverability
{
    my( $ea, $c ) = @_;

    my $args = solid_propargs();
    my $o = $c->email_obj;
    my $email = $o->email;

    my $std_reason = $c->dsn_std_reason || '';

    my $patience = DateTime::Duration->new(days => 14);
    my $big_patience = DateTime::Duration->new(months => 2);

    if ( $c->is_dsn )
    {
        debug "DELIVERY STATUS NOTIFICATION";

#        foreach my $report ( $c->reports )
#        {
#            debug $report->as_string;
#        }

        $email->add({dsn_for_address => $ea}, $args);
        $email->add({is => C->get('dsn_email')}, $args);
    }

    debug "REASON: $std_reason";


    if ( $c->is_address_changed )
    {
        my $new = $c->{contact}{email_address}{changed_to};
        if ( $new )
        {
            $ea->move_agent_to($new, $args);
        }
        else
        {
            debug "New email not found in ".$email->id;
        }
    }
    elsif ( $c->is_quit_work )
    {
        $ea->update({'has_email_deliverability'=>
                     C->get('ed_mailbox_unavailible')}, $args);
    }
    elsif ( $c->is_bounce )
    {
        given( $std_reason )
        {
            when('user_unknown')
            {
                $ea->update({'has_email_deliverability'=>
                             C->get('ed_mailbox_unavailible')}, $args);
            }
            when('syntax_error')
            {
                $ea->update({'has_email_deliverability'=>
                             C->get('ed_address_error'),
                            }, $args);
            }
            when('domain_error')
            {
                $ea->update({'has_email_deliverability'=>
                             C->get('ed_domain_error'),
                            }, $args);
            }
            when('denied')
            {
                $ea->update({'has_email_deliverability'=>
                             C->get('ed_non_deliverable'),
                            }, $args);
            }
            when('unknown')
            {
                $ea->validate( $args );
            }
            default
            {
                die "fixme: $std_reason";
            }
        }
    }
    elsif ( $c->is_vacation and $c->dsn_date )
    {
        # 1. Short term
        # 2. Long term
        # 3. Reporting time in the past
        # 4. Unknown time

        my $agent_away = C->get('ed_agent_away');

        my $eda = $ea->arc('has_email_deliverability',$agent_away);
        my $ed_date = $eda->dsn_date;
        my $ed = $eda->obj;

        my $avail = $c->dsn_date_availible;
#	my $today = now();
        if ( $avail )
        {
            if ( $c->dsn_date > $avail + $big_patience )
            {
                # Should have come back a long time ago
                #
#		debug "AV1";
                $ea->update({'has_email_deliverability' =>
                             C->get('ed_non_deliverable')}, $args);
            }
            elsif ( $c->dsn_date + $patience > $avail )
            {
                # Back within a week
                #
#		debug "AV2";
                $ea->update({'has_email_deliverability' =>
                             C->get('ed_deliverable')}, $args);
            }
            #
            # Coming back at a specified future time
            #
            elsif ( $eda and $ed->label('ed_agent_away') )
            {
                # Maby update the time
                if ( $eda->dsn_date_availible < $avail )
                {
#                    debug "AV3";
                    $eda->update({dsn_date_availible => $avail}, $args);
                }
            }
            else                # Store the time
            {
#		debug "AV4";
                $eda->remove($args) if $eda;
                $eda = $ea->add_arc({has_email_deliverability =>
                                     $agent_away}, $args);
                $eda->add({dsn_date_availible => $avail}, $args);
            }

            # Update the latest time we got a specified return time
            #
#	    debug "AV5";
            $eda ||= $ea->arc('has_email_deliverability',$agent_away);
            if ( $eda->dsn_date )
            {
                if ( $eda->dsn_date < $c->dsn_date )
                {
                    $eda->arc('dsn_date')->remove;
                    $eda->add({dsn_date => $c->dsn_date}, $args);
                }
            }
            else
            {
                $eda->add({dsn_date => $c->dsn_date}, $args);
            }
        }
        #
        # Unspecified return time
        #
        elsif ( $ed and $ed_date and $ed->label('ed_agent_away') )
        {
            my $long_time = DateTime::Duration->new(months => 12);
            if ( $c->dsn_date > $ed_date + $long_time )
            {
                # Probably never coming back...
#		debug "AV6";
                $ea->update({'has_email_deliverability' =>
                             C->get('ed_non_deliverable')}, $args);
            }
        }
        else             # Remeber when we started seeing the vacation
        {
#		debug "AV7";
            $eda->remove($args) if $eda;
            $eda = $ea->add_arc({has_email_deliverability =>
                                 $agent_away}, $args);
            $eda->add({dsn_date => $c->dsn_date}, $args);
        }
    }
    elsif ( $c->is_transient and $c->dsn_date ) # Need the date
    {
        my $delayed = C->get('ed_delayed');
        my $eda = $ea->arc('has_email_deliverability');
        my $ed_date = $eda->dsn_date;
        my $ed = $eda->obj;

        if ( $ed and $ed_date and $ed->label('ed_delayed') )
        {
            debug " *** START : ".$ed_date->desig;
            debug " *** LATEST: ".$c->dsn_date->desig;
            debug " ***  LIMIT: ".($ed_date + $patience)->desig;

            if ( $c->dsn_date > $ed_date + $patience )
            {

                debug "  Not transient anymore";
                $ea->update({'has_email_deliverability' =>
                             C->get('ed_non_deliverable')}, $args);
            }
            else
            {
                debug "Limit not reached. Keep status";
            }
        }
        else
        {
            $eda->remove($args) if $eda;
            $eda = $ea->add_arc({has_email_deliverability =>
                                 $delayed}, $args);
            $eda->add({dsn_date => $c->dsn_date}, $args);
        }
    }
    elsif ( $c->is_spam )
    {
        debug "Is SPAM";
    }
    elsif ( $c->is_ticket )
    {
        $ea->add({'has_email_deliverability' =>
                  C->get('ed_queuing')}, $args);
    }
    elsif ( $c->is_vacation )
    {
        # Must get more info before we can say anything about this
        # See RDF::Base::Email::Classifier/analyze_vacation
        debug "VACATION. But need more info";
    }
    elsif ( $c->is_delivered )
    {
        $ea->update({'has_email_deliverability' =>
                     C->get('ed_deliverable')}, $args);
    }
    elsif ( $c->is_auto_reply )
    {
        $ea->validate( $args );
    }
    else
    {
        debug "WHAT IS THIS EMAIL?";
        debug datadump($c->{is});
    }



    unless( $ea->prop('has_email_deliverability') )
    {
        debug "UNCLASSIFIED has_email_deliverability ed_unclassified";
        $ea->add({has_email_deliverability=>C->ed_unclassified}, $args);
    }


}

##############################################################################

sub validate
{
    my( $ea, $args ) = @_;

#    my $lea = $ea->first_prop('ea_original');
#    $lea->validate;

    if ( $ea->is_nonhuman )
    {
        $ea->add({has_email_deliverability => C->get('ed_nonhuman')}, $args);
    }


    return;


    my $test;
    eval
    {
        $test = Para::Frame::Email::Address->parse_tolerant('my@bad.address');
        $test->validate;
    };
    if ( my $err = catch(['email']) )
    {
        debug "ERROR: ".$err->info;
    }

    if ( $test )
    {
        debug "Test: ".$test->error_message;
    }

    die "FIXME";


}

##############################################################################

=head2 is_role

Non-personal email addresses

=cut

sub is_role
{
    my( $this, $ea ) = @_;
    $ea = $this->address if ref $this;

    return $ea =~ qr{
                        -admin\@ |
                        -confirm\@|
                        ^news\@|
                        ^request|
                        ^sales\@|
                        ^info\@|
                        ^webmaster\@|
                        ^support\@
                        ^www\@|
                        ^owner- |
                        -owner\@
                }xmi;
}


##############################################################################

=head2 is_nonhuman

Non-human email addresses.

Might still be sent from a human, but not usable for sending back to
the human.

=cut

sub is_nonhuman
{
    my( $this, $ea ) = @_;
    $ea = $this->address if ref $this;
    cluck "Got nothing" unless $ea;

    # Strip <>
    $ea =~ s/^\s*<\s*//; $ea =~ s/\s*>\s*$//;

    return $ea =~ qr{
                        ^bounce-|
                        \@bounce\.|
                        -outgoing\@|
                        -relay\@|
                        -bounces\@|
                        -bounce\@|
                        -errors\@|
                        ^mailer\@|
                        ^postmaster|
                        ^mailer-daemon\@|
                        ^mailer_daemon\@|
                        ^majordomo\@|
                        ^majordom\@|
                        ^mailman\@|
                        ^reminder\@|
                        ^autoreply|
                        -autoresponder\@|
                        ^autoresponder\@|
                        ^server\@|
                        ^bounce\@|
                        ^httpd\@|
                        ^lighttpd\@|
                        ^nagios\@|
                        ^fetchmail|
                        ^listmaster\@|
                        ^mailmaster\@|
                        ^squid\@|
                        ^exim\@|
                        scomp\@aol.net |
                        mdaemon\@ |
                        -request\@ |
                        ^listserv\@|
                        ^daemon\@|
                        ^nobody\@|
                        ^noreply|
                        ^no-reply|
                        ^DoNotReply\@|
                        ^www-data\@|
                        ^root\@
                }xmi;
}


##############################################################################

=head2 vacuum_facet

=cut

sub vacuum_facet
{
    my( $ea, $args ) = @_;

    my $a = $ea->first_prop('ea_original', undef, $args);

    unless( $a )
    {
        $ea->remove($args);
        return $ea;
    }

    my $code_in = $a->address;
    unless( $code_in )
    {
        $ea->remove($args);
        return $ea;
    }

    my $code = lc $code_in;

    $ea->update({code => $code}, $args);

    my $nodes = $ea->find({
                           code => $code,
                           is => $C_email_address_holder,
                          }, $args)->sorted('id');
    my $node = $nodes->get_first_nos;
    while ( my $enode = $nodes->get_next_nos )
    {
        $enode->merge_node($node,
                           {
                            %$args,
                            move_literals => 1,
                           });
    }

    return $node;
}


##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Literal::Email::Address>,

=cut
