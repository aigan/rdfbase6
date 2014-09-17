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

use Carp qw( cluck confess longmess );
use Mail::Address;

use Para::Frame::Widget qw( input );
use Para::Frame::Email::Address;
use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use RDF::Base::Utils qw( parse_propargs );
use RDF::Base::Constants qw( $C_intelligent_agent $C_email_address_holder );

use RDF::Base::Widget qw( aloc build_field_key );

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

sub new
{
    my( $class, $in_value, $args ) = @_;

    my $a = RDF::Base::Literal::Email::Address->parse($in_value);

    my $code_in = $a->address;

    my $an_args = parse_propargs('all');
    $an_args->{'activate_new_arcs'} = 1;
    my $an = RDF::Base::Resource->set_one({
                                           code=>$code_in,
                                           is=>$C_email_address_holder,
                                          }, $an_args);

#    debug "New email address ".datadump($a,1);

    $an->update({name => $a->name, ea_original => $a}, $an_args);

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
    my $a = RDF::Base::Literal::Email::Address->parse($in_value);

#    debug "parsed to ".datadump($a,1);

    my $code_in = $a->address;

    my $an_args = parse_propargs('all');

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
    my( $class, $subj, $pred, $args_in ) = @_;
    my( $args ) = parse_propargs($args_in);

    my $out = "";

    my $predname;
    if( ref $pred )
    {
	$predname = $pred->label;
    }
    else
    {
	$predname = $pred;
	$pred = RDF::Base::Pred->get_by_label($predname);
    }

    debug "  $predname for ".$subj->sysdesig;

    my $divid = $args->{divid};
    my $size = $args->{'size'} ||"";

    $args->{'id'} ||= build_field_key({
				       pred => $predname,
				       subj => $subj,
				      });

    my $disabled = $args->{'disabled'}||'';
    if( $disabled )
    {
        my $arclist = $subj->arc_list($predname, undef, $args);
        while( my $arc = $arclist->get_next_nos )
        {
            $out .= $arc->value->as_html .'&nbsp;'. $arc->edit_link_html .'<br/>';
        }
    }

    my $arcversions =  $subj->arcversions($predname);
    my @arcs = map RDF::Base::Arc->get($_), keys %$arcversions;
    my $list_weight = 0;

    my $multi = $args->{'multi'} // not $pred->range_card_max_1;

    my $onchange = ""; #"RDF.Base.pageparts['$divid'].node_update()";

    foreach my $arc ( RDF::Base::List->new(\@arcs)->sorted([{on=>'obj.weight', dir=>'desc'}])->as_array )
    {
        my $arc_id = $arc->id;

        # Maby show weight

        if( $Para::Frame::U->has_root_access and
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

        $out .= input($field, $arc->value->code->plain, $fargs);
        $out .= $arc->edit_link_html;
        $out .= "<br>";
    }

    if( $multi or not @arcs )
    {
        my $props =
	{
	 pred => $predname,
	 subj => $subj,
	};

        my $default = '';
        if( my $def = $args->{default_value} )
        {
            $default = $def->address;
        }

        $out .= input( build_field_key($props),
                       $default,
                       {
                        class => $args->{'class'},
                        size => $size,
                        maxlength => $args->{'maxlength'},
                        id => $args->{'id'},
                        onchange => $onchange,
                       });
    }


    return $out;
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

    debug sprintf "Move agent from %s to %s", $ea_old->desig, $ea_new->desig;

    foreach my $arc ( $ea_old->revarc_list('has_email_address_holder',
                                           undef, $args)->as_array )
    {
        debug "Should move ".$arc->sysdesig;
    }

    die "Move agent to called";
}
##############################################################################

sub broken
{
    my $o = $_[0]->first_prop('ea_original');
     return $o ? $o->broken() : 1;
}


##############################################################################

sub error_message
{
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

    if( $name )
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

    return $ea->first_prop('ea_original')->format();
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

sub as_html
{
    return shift->first_prop('ea_original')->as_html(@_);
}

##############################################################################

1;

=head1 SEE ALSO

L<RDF::Base::Literal::Email::Address>,

=cut
