package RDF::Base::Email::Bulk;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2010-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Email::Bulk

=head1 DESCRIPTION

=cut

use 5.014;
use warnings;
use utf8;

use Carp qw( croak confess cluck );
use Storable qw(store retrieve);
use File::Path qw(remove_tree);

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug create_dir datadump );
use Para::Frame::Email::Sending;


use RDF::Base::Utils qw( query_desig );
#use RDF::Base;
#use RDF::Base::Literal::String;
#use RDF::Base::Email::Head;


##############################################################################

sub continue_any
{
    my $bulk = $_[0]->select() or return;
    $bulk->process(10);
    $bulk->store_state;
    return;
}


##############################################################################

sub select
{
    my( $class ) = @_;
    debug "Bulk process of email sending";

    my $vardir = $class->vardir;
    create_dir($vardir);
    my $d = IO::Dir->new($vardir);
    while ( defined(my $bulkid = $d->read) )
    {
        next if $bulkid =~/^\./;
        debug "Dir $bulkid";

        my $bulk = $class->new_by_file( $bulkid );
        if ( $bulk->at_end )
        {
            $bulk->report;
            $bulk->remove;
        }
        else
        {
            return $bulk;
        }
    }

    return;
}


##############################################################################

sub new_by_file
{
    my( $class, $bulkid ) = @_;

    my $dirname = $class->vardir .'/'. $bulkid;

    my $state = retrieve($dirname.'/state')
      or die "no state for $bulkid";

    my $params = retrieve($dirname.'/params')
      or die "no params for $bulkid";

    my $recv = IO::File->new($dirname.'/receivers')
      or die "no recievers for $bulkid";

    my $bulk =
      bless
      {
       bulkid => $bulkid,
       state => $state,
       params => $params,
       recv => $recv,
       err => {},
      }, $class;

    return $bulk;
}


##############################################################################

sub process
{
    my( $bulk, $batch ) = @_;

    debug "in process of ".$bulk->id;

    my $R = RDF::Base->Resource;
    my $at = $bulk->{'state'}{'at'};
    debug "At $at";
    my $fh = $bulk->{'recv'};
    $fh->seek($at,0);
    $batch ||= 1;

    # Turn it to objects
    #
    my $esp_in = $bulk->{'params'};
    $esp_in->{'u'} = $R->get($esp_in->{'u'});
    $esp_in->{'site'} = Para::Frame::Site->get($esp_in->{'site'});

    my $es = Para::Frame::Email::Sending->new($esp_in);
    my $esp = $es->params;


    if ( $esp->{'email_body'} )
    {
        $esp->{'plaintext'} = $esp->{'email_body'};
        $esp->{'template'}  = 'plaintext.tt';
    }
    elsif ( my $te_in = $esp->{'has_email_body_template_email'} )
    {
        debug "Adding email as a template";

        my $te = $R->get($te_in);
        my $rend = RDF::Base::Renderer::Email::From_email->
          new({ template => $te, params => $esp });

        $es->{'renderer'}  = $rend;
    }
    else
    {
        throw 'validation', "Email has no body";
    }


    for ( my $i=0; $i<$batch; $i++ )
    {
        my $to_id = <$fh>;
        unless( $to_id )
        {
            debug "Got to end of file";
            $bulk->{'state'}{'at_end'} = 1;
            last;
        }
        chomp($to_id);
        my $to_obj = $R->get($to_id);
        my $to = $to_obj->list('has_email_address_holder')->first_prop('code')->as_arrayref;
#	debug "To ".datadump($to_obj->list('has_email_address_holder')->first_prop('code')->as_arrayref,1);
        $bulk->{'state'}{'cnt_proc'} ++;
        eval
        {
            $es->send_by_proxy({to => $to,
                                to_obj => $to_obj,
                               });
            $bulk->{'state'}{'cnt_sent'} ++;
        };
        if ( $@ )
        {
            my $err = $@;
            chomp($err);
            debug "Problem sending to $to: $err";
            if(my $to_str = eval{$to->[0]->plain})
            {
                $bulk->{'state'}{'err'}{$to_str} = $err;
            }
            else
            {
                $bulk->{'state'}{'err'}{$to} = $err;
            }
            $bulk->{'state'}{'cnt_failed'} ++;
        }
    }

    $bulk->{'state'}{'at'} = $fh->tell;

    return 1;
}


##############################################################################

sub store_state
{
    my( $bulk ) = @_;

    my $state = $bulk->{'state'};
#    debug datadump($state);
    debug "Storing bulk state";

    my $dirname = $bulk->vardir .'/'. $bulk->id;

    store( $state, $dirname.'/state.new' );
    rename( $dirname.'/state.new', $dirname.'/state' );

    if ( $bulk->at_end )
    {
        $bulk->report;
        $bulk->remove;
    }
}


##############################################################################

sub report
{
    my( $bulk ) = @_;

    my $params = $bulk->{'params'};

    debug "Finished sending bulkmail ".$bulk->id;
    debug sprintf "Sent %d of %d", $bulk->cnt_proc, $bulk->cnt_total;
    if ( my $err = $bulk->{'state'}{'err'} )
    {
        my $fcnt = $bulk->cnt_failed;
        debug "$fcnt failures:";
        foreach my $key ( keys %$err )
        {
            my $emsg = $err->{$key};
            debug "  $key: $emsg";
        }
    }
}


##############################################################################

sub remove
{
    my( $bulk ) = @_;

    my $dirname = $bulk->vardir .'/'. $bulk->id;
    remove_tree( $dirname ) or die "Faild to remove $dirname";
    return 1;
}


##############################################################################

sub at_end
{
    return $_[0]->{'state'}{'at_end'} || 0;
}


##############################################################################

sub cnt_proc
{
    return $_[0]->{'state'}{'cnt_proc'};
}


##############################################################################

sub cnt_total
{
    return $_[0]->{'state'}{'cnt_total'};
}


##############################################################################

sub cnt_sent
{
    return $_[0]->{'state'}{'cnt_sent'};
}


##############################################################################

sub cnt_failed
{
    return $_[0]->{'state'}{'cnt_failed'};
}


##############################################################################

sub vardir
{
    return $Para::Frame::CFG->{'dir_var'}.'/bulkmail';
}


##############################################################################

sub id
{
    return $_[0]->{'bulkid'};
}


##############################################################################

sub user
{
    return $_[0]->{'user'} ||=
      RDF::Base::Resource->get( $_[0]->{'params'}{'u'} );
}


##############################################################################

1;
