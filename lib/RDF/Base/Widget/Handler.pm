package RDF::Base::Widget::Handler;
#=============================================================================
#
# AUTHOR
#   Jonas Liljegren <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2017 Avisita AB.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=============================================================================

=head1 NAME

RDF::Base::Widget::Handler

=cut

use 5.014;
use warnings;
use utf8;

use Carp qw( cluck confess croak carp shortmess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch trim debug datadump );
use Para::Frame::L10N qw( loc );

use RDF::Base::List;
use RDF::Base::Arc;
use RDF::Base::Literal::Time qw( now );
use RDF::Base::Pred;
use RDF::Base::Resource::Change;
use RDF::Base::Arc::Lim;
use RDF::Base::Constants qw( $C_language $C_arc $C_class );

use RDF::Base::Utils qw( valclean parse_form_field_prop is_undef
                         arc_lock arc_unlock query_desig
                         parse_propargs aais );

=head1 DESCRIPTION

For parsing and acting on HTML forms and HTML widgets, or just the CGI
query.

=cut


##############################################################################

=head2 update_by_query

  $class->update_by_query( \%args )

Calls L</session_history_add> if base node is given.

Overall plan:

update_by_query maps through all parameters in the current request.
It sorts into 4 groups, depending on what the parameter begins with:

 1. Add / update properties  (arc/prop/image)
 2. Complemnt those props with second order atributes (row)
 3. Check if some props should be removed (check)
 4. Add new resources (newsubj)
 5. Let classes handle themselves

Returns: the number of changes

=head3 1. Add / update

Parameters beginning with arc_ or prop_

=head4 select

Used when there are several versions of an arc, to activate selected
version (by value) and remove the rest.  Eg: arc_select => 1234567
will activate arc 1234567 and remove all other versions of that arc.

Example tt-code:
[% hidden("version_${arc.id}", version.id);
   radio("arc_${arc.id}__pred_${arc.pred.name}", version.id,
         0,
	 {
	  id = version.id,
	 })
%]


=head4 files / images

Images are to be uploaded as a filefield, and are saved to the
"logos"-folder

The image can be scaled proportianally to fit within certain
max-dimensions in pixels by having parameters maxw and maxh.  A
typical image-parameter would be:

 arc_singular__file_image__pred_logo_small__maxw_400__maxh_300__row_12

Filenames are made of name (or id) on subj and a counter (first free
number).  Suffix is preserved.

TODO: Add possibility of using a row to set other filename.

=head4 parameter_in_value

The parameter_in_value is a way to to extract parameters from values.
Eg in select, you could use:

<select name="parameter_in_value">
  <option value="arc___subj_12335__pred_is=5412354">Set is for 12345</option>
  <option value="arc___subj_54321__pred_is=5412354">Set is for 54321</option>
</select>


=head3 2. Complemnt those props with second order atributes (row)

Parameters beginning with row_

This is for adding propertis with the arc as subj or obj, or the arcs
subj as subj or obj or the arcs obj as subj or obj.

row_#__subj_arc__...

row_#__subj_subj__...

row_#__subj_obj__...


=head3 4. Add new resources

To create a new resource and add arcs to it, the parameters should be
in the format "newsubj_$key__pred_$pred", where $key is used to group
parameters together.  $key can be prefixed with "main_".  At least one
$key should have the main-prefix set for the new resource to be
created.  $pred can be prefixed with "rev_".

Example1: Adding a new node if certain values are set

 Params
 newsubj_main_contact__pred_contact_next => 2006-10-05
 newsubj_contact__pred_is => C.contact_info.id
 newsubj_contact__pred_rev_contact_info => org.id

...where 'contact' is the key for the newsubj, regarding all with the
same key as the same node.  A new resource is created IF at least one
main-parameter is supplied (no 1 above).  There can be several
main-parameters.  If no main-parameter is set, the other
newsubj-parameters with that number are ignored.

=head3 5. Let classes handle themselves

=head4 Existing resources

Class-resources that wish to handle their own update_by_query can be
specified with:

 hidden('class_update_by_query', my_node.id)

Then that resource will be called by:

 my_node->class_update_by_query( $q );


=head4 New class resources

For new class-resources to be created, a key property can be specified
with:

 hidden('class_new_by_query', my_class.id)

Then that class will be called by:

 my_class->class_new_by_query( $q );

The class then has to check for it's own parameters to see if a new
resource is to be created or not etc.

=head4 Parameter naming-convention

To easily handle many classes etc at the same time, it is preferrable
if you follow those naming conventions:

 1. For existing class resources, prefix all parameters with
    class_[% class.label %]__subj_[% resource.id %]__
 2. For new class resources, prefix with
    class_[% class.label %]__newsubj_[% key %]__


=head3 Supported args are:

  res


=head3 Field props:

arc
desig
file
if
unless
is
lang
newsubj
parse
pred
revpred
row
select
scof
subj
type
vnode


=head4 lang

A language-code; Set the language on this value (as an arc to the value-node).

=head4 if

Examples:

  if_subj

  if_obj

  if_subj_obj

  if_12345

  if_12345_methodname

You may have multipple if arguments, in which case all must be true in
order to process the field.

subj : true if subj is not empty()

obj : true if obj is not empty()

12345 : looks up the node with given id. If it's an arc, we check if
it's active. If its a nother type of node, we check if its not empty.

12345_methodname : methodname must be a method that doesn't take any
arguments. It checks that the method returns a true value. Example of
methods are; submitted, inactive, active, old, etc.

=head4 unless

Works like L</if> but checks for falsehood instead.

=cut

  ;
sub update_by_query
{
    my( $class, $args_in ) = @_;
    my( $args_hash, $arclim, $res ) = parse_propargs($args_in);
    my $args = {%$args_hash};   # Shallow clone
    my $changes_prev = $res->changes;


#    debug "******** WIDGET HANDLER UPDATE BY QUERY";

    my $q = $Para::Frame::REQ->q;

    if ( $args->{'node'} )
    {
        $q->param('id', $args->{'node'}->id); # Just in case...
    }
    else
    {
        if ( my $id = $q->param('id') )
        {
            $args->{'node'} = RDF::Base::Resource->get($id);

            # Keep a history of updated nodes
            $args->{'node'}->session_history_add('updated');
        }
    }

    # Sort params
    my @arc_params;
    my @row_params;
    my @check_params;
    my @newsubj_params;

    foreach my $param_in_value ($q->param('parameter_in_value'))
    {
        if ( $param_in_value =~ /^(.*)=(.*)$/ )
        {
            debug "Extracting parameter: $1 = $2";
            $q->param($1, $2);
        }
    }

    foreach my $param ($q->param)
    {
        if ( $param =~ /^(arc|prop)_.*$/ )
        {
            # check_prop is used both for adding and removing arcs.
            # check_arc is only used for removing arcs. Thus, you can
            # not update the arc value if you also have a
            # corresponding check_arc_ field.
            #
            next if $q->param("check_$param"); #handled by check below
            push @arc_params, $param;
        }
        elsif ( $param =~ /^row_.*$/ )
        {
            push @row_params, $param;
        }
        elsif ( $param =~ /^check_(.*)/)
        {
            push @check_params, $param;
        }
        elsif ( $param =~ /^newsubj_.*$/ )
        {
            push @newsubj_params, $param;
        }
    }

    # Parse the arcs in several passes, until all is done

    # Some fields has an __if_... part that checks if the subj or obj
    # part exists. But those parts may only exist after other fields
    # has been processed. It may go on in several passes. We take care
    # of all if's by handling the fields several rounds, until we get
    # a round that didn't added more arcs, as seen by the $res object.

    my $fields_handled_delta = 0;
    my $fields_handled_count = $res->fields_count;
    do
    {
        arc_lock();
        do
        {
            debug 3, "----------------------";
            debug 3, "In field handling loop";
            debug 3, "Total fields handled: $fields_handled_count";
            debug 3, "Handled last lopp: $fields_handled_delta";

            foreach my $field (@arc_params)
            {
                if ( $field =~ /^arc_.*$/ )
                {
                    $class->handle_query_arc( $field, $args );
                }
                # Was previously only used for locations
                elsif ($field =~ /^prop_(.*?)/)
                {
                    $class->handle_query_prop( $field, $args );
                }
            }

            my $new_count = $res->fields_count;
            $fields_handled_delta = $new_count - $fields_handled_count;
            $fields_handled_count = $new_count;
            if ( debug > 2 )
            {
                debug 1, $res->sysdesig;
            }
        } while $fields_handled_delta > 0;

        arc_unlock();
        my $new_count = $res->fields_count;
        $fields_handled_delta = $new_count - $fields_handled_count;
        $fields_handled_count = $new_count;
        if ( debug > 2 )
        {
            debug 1, $res->sysdesig;
        }
    } while $fields_handled_delta > 0;

    foreach my $param (@row_params)
    {
        $class->handle_query_row( $param, $args );
    }

    foreach my $param (@check_params)
    {
        # $param alwas begins wich "check_". This check may not be
        # needed. But somthing might have removed the query param in
        # order to disable the check.
        next unless $q->param( $param );

        ### Remove all check_arc params that is ok. All check_arc
        ### params left now represent arcs that should be removed

        if ( $param =~ /^check_row_.*$/ )
        {
            # Check row is a copy of similar code above
            $class->handle_query_check_row( $param, $args );
        }
        elsif ($param =~ /^check_arc_(\d+)/)
        {
            my $arc_id = $1 or next;
            $class->handle_query_check_arc( $param, $arc_id, $args );
        }
        elsif ($param =~ /^check_prop_(.*)/)
        {
            my $pred_name = $1 or next;
            $class->handle_query_check_prop( $param, $pred_name, $args );
        }
        elsif ($param =~ /^check_revprop_(.*)/)
        {
            my $pred_name = $1 or next;
            $class->handle_query_check_revprop( $param, $pred_name, $args );
        }
        elsif ($param =~ /^check_node_(.*)/)
        {
            my $node_id = $1 or next;
            $class->handle_query_check_node( $param, $node_id, $args );
        }
        elsif ($param =~ /^check_require_(.*)/)
        {
            $class->handle_query_check_require( $param, $args );
        }
    }

    handle_query_newsubjs( $q, \@newsubj_params, $args );

    # Remove arcs on deathrow
    #
    # Arcs on deathrow do not count during inference.
    foreach my $arc ( $res->deathrow_list )
    {
        debug 3, "Arc $arc->{id} on deathwatch";
        $arc->{'disregard'} ++;
    }

    foreach my $arc ( $res->deathrow_list )
    {
        $arc->remove( $args );
    }

    foreach my $arc ( $res->deathrow_list )
    {
        # If they got removed, they will still have positive disregard
        # value
        $arc->{'disregard'} --;
        debug 3, "Arc $arc->{id} now at $arc->{'disregard'}";
    }

    # Clear out used query params
    # TODO: Also remove revprop_has_member ...
    $Para::Frame::REQ->change->queue_clear_params( @arc_params,
                                                   @row_params,
                                                   @check_params );

    return $res->changes - $changes_prev;
}


#########################################################################

=head2 handle_query_arc

  $class->handle_query_arc( $param, \%args )

Returns the number of changes

=cut

sub handle_query_arc
{
    my( $class, $field, $args ) = @_;

    my $valuerow = 1;
    foreach my $value ( $Para::Frame::REQ->q->param($field) )
    {
        my $key = $field . "__valuerow_" . $valuerow;
        unless ( $args->{'res'}->field_handled( $key ) )
        {
            $class->handle_query_arc_value( $field, $value, $args, $key );
        }
        $valuerow++;
    }

    return 1;
}

#########################################################################

=head2 handle_query_arc_value

  $n->handle_query_arc_value( $param, $value, \%args )

Default subj is $args->{'node'} or 'new_node'.

If this is a reverse arc, the subj will be handled as an obj.

Returns: the number of changes

=cut

sub handle_query_arc_value
{
    my( $class, $param, $value, $args, $key ) = @_;

#    Para::Frame::Logging->this_level(4);

    die "missing value" unless defined $value;

    my $R = RDF::Base->Resource;
    my $res = $args->{'res'};

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $site = $page->site;
    my $q = $req->q;

    my $arg = parse_form_field_prop($param);

    my $subj      = $arg->{'subj'}; # The subj of the prop
    my $pred_name = $arg->{'pred'}||''; # In case we should create the prop
    my $vnode     = $arg->{'vnode'};    # Value node, if existing
    my $rev       = $arg->{'revpred'}; # In case we should create the prop
    my $arc_id    = $arg->{'arc'}; # arc to update. Create arc if undef
    my $desig     = $arg->{'desig'}; # look up obj that has $value as $desig
    my $type      = $arg->{'type'};  # desig obj must be of this type
    my $scof      = $arg->{'scof'}; # desig obj must be a scof of this type
    my $parse     = $arg->{'parse'}; # how to parse the value
    my $rowno     = $arg->{'row'}; # rownumber for matching props with new/existing arcs
    my $if        = $arg->{'if'};  # Condition for update
    my $unless    = $arg->{'unless'}; # Condition for update

    my $lang	  = $arg->{'lang'};	# lang-code of value (set on value/obj)
    my $file	  = $arg->{'file'};	# "filetype" for upload-fields
    my $select	  = $arg->{'select'}; # for version-selection
    my $singular  = 0;

#    my $ ## TODO: Add extra "new"-alternative "None of the avobe"...

    if ( $arc_id and ($arc_id eq 'singular') )
    {
        $singular = 1;
        $arc_id = '';
    }


    if ( debug > 3 )
    {
        debug "handle_query_arc $arc_id";
        debug "  param $param = $value";
        debug "  subj : ".($subj||'');
        debug "  pred : ".($pred_name||($rev?'rev_'.$rev:''));
        debug "  type : ".($type||'');
        debug "  scof : ".($scof||'');
        debug "  desig: ".($desig||'');
        debug "  parse: ".($parse||'');
        debug "  sing : ".($singular);
    }


    if ( $subj )
    {
        unless( $subj =~ /^(\d+)$/ )
        {
            confess "Invalid subj part: $subj";
        }

        $subj = $R->get($subj);
        debug 2, "subj gave ".$subj->sysdesig;
    }
    elsif ( $arc_id )
    {
        # Getting subj from arc, later
    }
    else
    {
        $subj = $args->{'node'} || $R->get('new');
    }

    ### Check conditions
    #
    $if ||= [];
    unless( ref $if eq 'ARRAY' )
    {
        $if = [$if];
    }

    foreach my $cond ( @$if )
    {
        debug 2, "Checking condition if $cond";

        if ( $cond =~ /subj/ )
        {
            if ( $subj->empty )
            {
                debug 2, "Condition failed: $key";
                return 0;
            }
        }

        if ( $cond =~ /obj/ )
        {
            my $obj = $R->get( $value );
            unless( $obj )
            {
                debug 2, "Condition failed: $key (OBJ NOT FOUND)";
                return 0;
            }

            if ( $obj->empty )
            {
                debug 2, "Condition failed: $key";
                return 0;
            }
        }

        if ( $cond =~ /(\d+)(?:_([\w_]+))?/ )
        {
            if ( my $node = $R->get( $1 ) )
            {
                if ( my $meth = $2 )
                {
                    if ( $node->can($meth) )
                    {
                        unless( $node->$meth() )
                        {
                            debug 2, "Condition failed: $key";
                            return 0;
                        }
                    }
                    else
                    {
                        debug "Node $node->{id} can't do $meth";
                        return 0;
                    }
                }
                elsif ( $node->is_arc )
                {
                    unless( $node->active )
                    {
                        debug 2, "Condition failed: $key";
                        return 0;
                    }
                }
                elsif ( $node->empty )
                {
                    debug 2, "Condition failed: $key";
                    return 0;
                }
            }
            else
            {
                debug 2, "Condition failed: $key (OBJ NOT FOUND)";
                return 0;
            }
        }
    }

    $unless ||= [];
    unless( ref $unless eq 'ARRAY' )
    {
        $unless = [$unless];
    }

    foreach my $cond ( @$unless )
    {
        debug 2, "Checking condition unless $cond";

        if ( $cond =~ /subj/ )
        {
            unless( $subj->empty )
            {
                debug 2, "Condition failed: $key";
                return 0;
            }
        }

        if ( $cond =~ /obj/ )
        {
            my $obj = $R->get( $value );
            if ( $obj )
            {
                unless( $obj->empty )
                {
                    debug 2, "Condition failed: $key";
                    return 0;
                }
            }

        }

        if ( $cond =~ /(\d+)(?:_([\w_]+))?/ )
        {
            if ( my $node = $R->get( $1 ) )
            {
                if ( my $meth = $2 )
                {
                    if ( $node->can($meth) )
                    {
                        if ( $node->$meth() )
                        {
                            debug 2, "Condition failed: $key";
                            return 0;
                        }
                    }
                    else
                    {
                        debug "Node $node->{id} can't do $meth";
                        return 0;
                    }
                }
                elsif ( $node->is_arc )
                {
                    if ( $node->active )
                    {
                        debug 2, "Condition failed: $key";
                        return 0;
                    }
                }
                elsif ( not $node->empty )
                {
                    debug 2, "Condition failed: $key";
                    return 0;
                }
            }
        }
    }

    $res->set_field_handled($key);

    # Sanity check of value
    #
    if ( $value =~ /^RDF::Base::/ and not ref $value )
    {
        throw('validation', "Form gave faulty value '$value' for $param\n");
    }
#    elsif( ref $value )
#    {
#	throw('validation', "Form gave faulty value '$value' for $param\n");
#    }


    # reverse arc
    if ( $rev )
    {
        $pred_name = $rev;
        $rev = 1;
    }
    elsif ( $pred_name =~ /^rev_(.*)/ )
    {
        $pred_name = $1;
        $rev = 1;
    }


    return handle_select_version( $value, $arc_id, $q, $args )
      if ( $select and $select eq 'version' ); # activate arc-version and return


    # Value-resources given by literal id handled here
    #
    if ( $parse )
    {
        if ( $parse eq 'id' )
        {
            $value = $R->get($value);
        }
        else
        {
            confess "Parsetype $parse not recognized";
        }
    }

#    if( $type )
#    {
#	$type = $R->get($type)->find({is=>$C_class});
#    }
#
#    if( $scof )
#    {
#	$scof = $R->get($scof)->find({is=>$C_class});
#    }



    if ( $rowno )
    {
        $res->set_pred_id_by_row( $rowno, RDF::Base::Pred->get_by_label( $pred_name )->id );
    }

    # Only one ACTIVE prop with this pred and of this type
    if ( $singular and ref $subj ) # Skip if subj doesn't exist
    {
        my $args_active = aais($args,'active');

#	debug "$pred_name SINGULAR";

        # Sort out those of the specified type
        my $arcs;
        if ( $rev )
        {
            $arcs = $subj->revarc_list($pred_name, undef, aais($args_active,'explicit'));
        }
        else
        {
            $arcs = $subj->arc_list($pred_name, undef, aais($args_active,'explicit'));
        }

        if ( $type and  $arcs->size )
        {
            if ( $rev )
            {
                $arcs = $arcs->find({ subj => { is => $type } }, $args_active);
            }
            else
            {
                $arcs = $arcs->find({ obj => { is => $type } }, $args_active);
            }
        }

        if ( $scof and  $arcs->size )
        {
            if ( $rev )
            {
                $arcs = $arcs->find({ subj => { scof => $scof } }, $args_active);
            }
            else
            {
                $arcs = $arcs->find({ obj => { scof => $scof } }, $args_active);
            }
        }

        if ( $arcs->size > 1 )  # more than one
        {
            debug 3, "prop $pred_name had more than one value";

            # Keep the first arc found
            my @arclist = $arcs->as_array;
            my $arc = shift @arclist;
            $arc_id = $arc->id;

            debug "  keeping ".$arc->sysdesig;

            foreach my $arc ( @arclist )
            {
                debug "  removing ".$arc->sysdesig;
                $arc->remove( $args );
            }
        }
        elsif ( $arcs->size )   # Replace this arc
        {
            $arc_id = $arcs->get_first_nos->id;
            debug 3, "Updating existing arc $arc_id";
        }
        else
        {
            $arc_id = '';
        }
    }


    ############### File handling #####################################
    #
    # Todo: Move this to RDF::Base::Literal::File or similar
    #
    if ( $file and ref $subj )  # Skip if subj doesn't exist
    {
        debug "Got a fileupload, stated type: $file, value: $value";
        return 1 unless( $value );

        if ( $file eq "image" ) # Check image operations (scaling etc)
        {
            my $maxw = $arg->{'maxw'};
            my $maxh = $arg->{'maxh'};

            my $img_file = $req->uploaded($param)->tempfilename
              or throw('validation', "No tempfile found for $param");
            my $image = Image::Magick->new;
            my $error = $image->Read( $img_file );
            die "Failed to open image $img_file: $error" if $error;
            my $w = $image->Get('width');
            my $h = $image->Get('height');

            debug "Image is $w × $h";

            if ( $maxw < $w and $maxh < $h )
            {
                ($w, $h) = (($w/$h > $maxw/$maxh) ?
                            ($maxw, $h/($w/$maxw)) : ($w/($h/$maxh), $maxh));
            }
            elsif ( $maxw < $w ) # $maxh might be undef
            {
                ($w, $h) = ($maxw, $h/($w/$maxw));
            }
            elsif ( $maxh < $h ) # $maxw might be undef
            {
                ($w, $h) = ($w/($h/$maxh), $maxh);
            }

            $image->Scale( width => $w, height => $h );
            debug "Scaled to ". $image->Get('width') ." × ".
              $image->Get('height');
            $error = $image->Write($img_file);
            die "Failed to save image $img_file: $error" if $error;
        }

        my $filename_in = $value;
        my $suffix = "";

        if ( $filename_in =~ /\.([^\.]+)$/ )
        {
            $suffix = lc $1;
            debug "Suffix is $suffix";
        }

        my $dirbase = $Para::Frame::CFG->{'images_uploaded_scp'};
        unless( $dirbase )
        {
            die "images_uploaded_scp not defined in PF::CFG";
        }

        my $index = 0;

        if ( $dirbase =~ m{^//([^/]+)(.+)} )
        {
            my $host = $1;
            my $localdir = $2;
            my $username;
            if ( $host =~ /^([^@]+)@(.+)/ )
            {
                $username = $1;
                $host = $2;
            }

            local $SIG{CHLD} = 'DEFAULT';
            my $scp = Net::SCP->new({host=>$host, user=>$username});
            debug "Connected to $host as $username";


            while ( $scp->size( $localdir ."/". join('.', $subj->id, $index, $suffix)) )
            {
                debug "Found a file ". $dirbase ."/". join('.', $subj->id, $index, $suffix);
                $index++;
            }
            debug "SCP errstr: ". $scp->{errstr};
        }
        else
        {
            while ( stat( $dirbase ."/". join('.', $subj->id, $index, $suffix)) )
            {
                debug "Found a file ". $dirbase ."/". join('.', $subj->id, $index, $suffix);
                $index++;
            }
        }
        debug "We got to index: $index";

        my $filename_base = join( '.', $subj->id, $index, $suffix );

        my $destfile = $dirbase .'/'. $filename_base;

        $req->uploaded($param)->save_as($destfile,{username=>'rit'});
        debug "Saved file as $destfile";

        $value = $filename_base;
    }
    #
    #
    ###################################################################


    if ( $desig and length( $value ) ) # replace $value with the node id
    {
        debug 3, "    Set value to a $type with $desig $value";

        my $crit =
        {
         $desig => $value,
        };

        if ( $type )
        {
            $crit->{'is'} = $type;
        }

        if ( $scof )
        {
            $crit->{'scof'} = $scof;
        }

        $value = $R->find_one($crit, $args )->id;
        # Convert back to obj later. (We expect id)
    }


    # check old value
    my $arc;
    if ( $arc_id )
    {
        $arc = RDF::Base::Arc->get_by_id($arc_id);

        ### Set up subj and pred_name if missing
        $pred_name ||= $arc->pred->plain;

        # Will switch place later if reverse
        $subj ||= $rev ? $arc->obj : $arc->subj;
        $vnode ||= $arc->value_node;

#        debug "Subj set from arc";
    }


    # Only handles pred nodes
    my $pred = RDF::Base::Pred->get_by_label( $pred_name )
      or die("Can't get pred '$pred_name' from $param");
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
    if ( $rev )
    {
        $coltype = 'obj';
    }


    # Switch subj and value if this is a reverse arc

    if ( $rev )
    {
        if (length $value )
        {
            debug 3, "  Reversing arc update";

            # Using the same method for lookup as in not rev

            my $valtype = $pred->first_prop('domain',undef,['active']) || $R->get('resource');
            my $range_class = $valtype->instance_class;
            my $subjs = $range_class->find_by_string($value, {}, $args);

            if ( $type )
            {
                $subjs = $subjs->find({ is => $type }, $args);
            }
            if ( $scof )
            {
                $subjs = $subjs->find({ scof => $scof }, $args);
            }

#            debug "  Found ".$subjs->sysdesig;

            #### SWITCHING PLACE OF SUBJ/VALUE
            #
            $value = $subj;
            $subj = $subjs->find_one; # Expect only one value

            if ( debug > 3 )
            {
                debug sprintf "  New node : %s", query_desig($subj);
                debug sprintf "  New value: %s", query_desig($value);
            }

            if ( $arc and not $arc->subj->equals( $subj ) )
            {
                debug "  Arc subj changed";
                $res->add_to_deathrow( $arc );
                undef $arc;
            }

        }
        elsif ( $arc_id )
        {
            $res->add_to_deathrow( RDF::Base::Arc->get($arc_id) );
        }
        elsif ( not $arc_id and not length $value )
        {
            # nothing changed
            return 0;
        }
        else
        {
            die "not implemented";
        }
    }

    # Store subj in row info
    if ( $rowno )
    {
        $res->set_subj_id_by_row( $rowno, $subj->id );
    }

    if ( $arc and $arc->is_arc )
    {
        if ( $arc->pred->id != $pred_id )
        {
            die "Arcs pred differ from $param: ".$arc->sysdesig;
#	    $arc = $arc->set_pred( $pred_id, $args );
        }


        if ( debug > 1 )
        {
            debug "Will now update";
            debug $arc->sysdesig;

            debug "New value of arc will be $value";
            debug 1, query_desig($value);
            debug "-----";
        }


        ###########
        ########### SET VALUE
        ###########

        $arc = $arc->value->update_by_query_arc
          ({arc=>$arc,value=>$value},$args);


        # Store row info
        if ( $rowno )
        {
            $res->set_arc_id_by_row( $rowno, $arc_id );
        }

        # This arc has been taken care of
        debug 2, "Removing check_arc_${arc_id}";
        $q->delete("check_arc_${arc_id}");
    }
    else                        # create new arc
    {
        if ( length $value )
        {
            debug 3, "  Creating new property";
            debug 3, "  Value is $value" if not ref $value;
            debug 3, sprintf "  Value is %s", $value->sysdesig if ref $value;
            if ( $pred->objtype )
            {
                debug 3, "  Pred is of objtype";

                my $range_class = $pred->valtype->instance_class;

                # Support adding more than one obj value with ','
                #
                my @values;
                if ( ref $value )
                {
                    push @values, $value;
                }
                else
                {
                    push @values, split /\s*,\s*/, $value;
                }

                foreach my $val ( @values )
                {
#                    debug "NODE ".$args->{node}->sysdesig;
#                    debug "VALTYPE ".$pred->valtype->instance_class;
                    #die "fixme";
                    ### DEBUG: FIXME

                    ### Could use find_by_anything() with valtype. Should use the same route here as for rev

                    my $objs = $range_class->find_by_string($val, {}, $args);

                    unless( $rev )
                    {
                        if ( $type )
                        {
                            $objs = $objs->find({ is => $type }, $args);
                        }

                        if ( $scof )
                        {
                            $objs = $objs->find({ scof => $scof }, $args);
                        }
                    }

                    if ( $objs->size > 1 )
                    {
                        $req->session->route->bookmark;
                        my $home = $req->site->home_url_path;
                        my $uri = $page->url_path_slash;
                        $req->set_error_response_path("/alternatives.tt");
                        my $result = $req->result;

                        push @$objs, $R->get('new');

                        $result->{'info'}{'alternatives'} =
                        {
                         title => "Choose $pred_name",
                         text  => "More than node has the name '$val'",
                         alts => $objs,
                         rowformat => sub
                         {
                             my( $item ) = @_;

                             # TODO: create cusom label
                             my $label = $item->desig;

                             # Replace this value part with the selected
                             # object id
                             #
                             my $value_new = $value;
                             my $item_id = $item->id;
                             $value_new =~ s/$val/$item_id/;

                             my $args =
                             {
                              step_replace_params => $param,
                              $param => $value_new,
                              run => 'next_step',
                             };

                             if ( $item->empty )
                             {
                                 my $name_param = 'arc___subj_'. $item->id .'__pred_name';
                                 my $is_param = 'arc___subj_'. $item->id .'__pred_is';
                                 $args->{'step_add_params'} =
                                   [
                                    $name_param,
                                    $is_param,
                                   ];
                                 $args->{$name_param} = $val;
                                 debug "Type is $type from param $param";
                                 $args->{$is_param} = $type;
                                 if ( $type )
                                 {
                                     my $main_param = $param;
                                     $main_param =~ s/_type_.*_//;
                                     $main_param =~ s/__type_.*//;
                                     debug "$param transformed to $main_param";
                                     $args->{$param} = '';
                                     $args->{$main_param} = $item->id;
                                     push @{$args->{'step_add_params'}},
                                       $main_param;
                                 }

                                 return
                                   Para::Frame::Widget::jump("Create $type $val",
                                                             $uri, $args );
                             }
                             my $link = Para::Frame::Widget::forward( $label, $uri, $args );
                             my $tstr = $item->list('is', undef, aais($args,'direct'))->desig;
                             my $view =
                               Para::Frame::Widget::jump('visa',
                                                         $item->form_url->as_string,
                                                         {
                                                          tag_attr => {target => '_blank'},
                                                         }
                                                        );
                             return "$tstr $link - ($view)";
                         },
                         button =>
                         [
                          ['Go back', $req->referer_path(), 'skip_step'],
                         ],
                        };
                        $q->delete_all();
                        throw('alternatives', 'Specify an alternative');
                    }
                    elsif ( not $objs->size )
                    {
                        $req->session->route->bookmark;
                        my $home = $site->home_url_path;
                        $req->set_error_response_path('/confirm.tt');
                        my $result = $req->result;
                        $result->{'info'}{'confirm'} =
                        {
                         title => "Create $type $val?",
                         button =>
                         [
                          ['Yes', undef, 'node_update'],
                          ['Go back', undef, 'skip_step'],
                         ],
                        };

                        $q->delete_all();
                        $q->init({
                                  arc___pred_name => $val,
                                  prop_is	  => $type,
                                 });
                        throw('incomplete', "Node missing");
                    }

                    my $arc = RDF::Base::Arc->
                      create({
                              subj    => $subj->id,
                              pred    => $pred_id,
                              value   => $objs->get_first_nos,
                             }, $args );

                    # Store row info
                    if ( $rowno )
                    {
                        if ( $res->arc_id_by_row( $rowno ) )
                        {
                            throw('validation', "Row $rowno has more than one new value\n");
                        }
                        $res->set_arc_id_by_row( $rowno, $arc->id );
                    }
                }
            }
            else
            {
                if ( $lang )
                {
                    debug(1, "Making value-node with langcode $lang");
                    # TODO: This section could be simplified

                    my $language = $R->get({
                                            code => $lang,
                                            is   => $C_language,
                                           })
                      or die("Erronuous lang-code $lang");

                    my $value_node = RDF::Base::Literal::String->new( $value );
                    $value_node->node_set($vnode) if $vnode;
                    $subj->add({ $pred_name => $value_node }, $args);
                    $value_node->add({
                                      is_of_language => $language,
                                     }, $args);

                }
                else
                {
                    my $arc = RDF::Base::Arc->
                      create({
                              subj    => $subj->id,
                              pred    => $pred_id,
                              value   => $value,
                              value_node => $vnode,
                             }, $args );
                }
            }
        }
    }

    return 1;
}

###############################################################################

sub handle_select_version
{
    my( $value, $arc_id, $q, $args ) = @_;

    my $arc = RDF::Base::Arc->get( $arc_id )
      or confess("Couldn't get arc for selection from value: $value");

    # For really getting a list of version, we would have to use
    # common_id for arc_id instead of the version id that is given by
    # $arc->id()

    my @versions = $q->param( 'version_'. $arc_id );

    if ( debug > 1 )
    {
        debug "Selecting from arc: ". ($arc ? $arc->sysdesig : $value);
        debug " selecting version: $value";
        debug "List of versions: ". datadump( \@versions );
    }

    unless( $value eq 'deactivate' )
    {
        my $select_version = RDF::Base::Arc->get( $value );

        if ( $select_version->active )
        {
            debug "Already active version selected.";
        }
        elsif ( $select_version->submitted )
        {
            debug "Activating version: ". $select_version->sysdesig;
            $select_version->activate( {%$args, recursive=>1} );
        }
    }

    # Must be removed in reverse order. Earlier arcs may be refered to
    # by later arcs. They can't be removed before the later arcs
    # refering to them
    #
    foreach my $version_id (reverse sort @versions)
    {
        my $version = RDF::Base::Arc->get( $version_id );
        next if( $value ne 'deactivate' and $version->equals( $value ) );

        if ( $version->submitted )
        {
            $version->remove( {%$args, recursive=>1, arclim=>['new','submitted']} );
        }
    }

    debug "Selection done.";

    return 1;
}



#########################################################################

=head2 handle_query_prop

  $class->handle_query_prop( $param, \%args )

Return number of changes

=cut

sub handle_query_prop
{
    my( $class, $param, $args ) = @_;

    my $res = $args->{'res'};
    return if $res->field_handled( $param );
    $res->set_field_handled( $param );

    foreach my $value ( $Para::Frame::REQ->q->param($param) )
    {
        $class->handle_query_prop_value( $param, $value, $args );
    }

    return 1;
}

#########################################################################

=head2 handle_query_prop_value

  $class->handle_query_prop_value( $param, $value, \%args )

Return number of changes

TODO: translate this to a call to handle_query_arc

=cut

sub handle_query_prop_value
{
    my( $class, $param, $value, $args ) = @_;

    die "missing value" unless defined $value;

    $param =~ /^prop_(.*?)(?:__(.*))?$/;
    my $pred_name = $1;
    my $obj_pred_name = $2;

    my $req = $Para::Frame::REQ;
    my $page = $req->page;
    my $site = $page->site;
    my $q = $req->q;
    my $node = $args->{'node'};
    my $id = $node->id;

    if ( my $value = $value )   # If value is true
    {
        my $pred = RDF::Base::Pred->get( $pred_name ) or die "Can't find pred $pred_name\n";
        my $pred_id = $pred->id;
        my $coltype = $pred->coltype;
#	my $valtype = $pred->valtype;
        confess "$pred_name should be of obj type" unless $coltype eq 'obj';

        my( $objs );
        if ( $obj_pred_name )
        {
            $objs = RDF::Base::Resource->find({$obj_pred_name => $value}, $args);
        }
        else
        {
            $objs = RDF::Base::Resource->find_by_anything($value, $args);
        }

        if ( $objs->size > 1 )
        {
            my $home = $site->home_url_path;
            $req->session->route->bookmark;
            my $uri = $page->url_path_slash;
            $req->set_error_response_path("/alternatives.tt");
            my $result = $req->result;
            $result->{'info'}{'alternatives'} =
            {
             # TODO: Create cusom title and text
             title => "Välj $pred_name",
             alts => $objs,
             rowformat => sub
             {
                 my( $node ) = @_;
                 # TODO: create cusom label
                 my $label = $node->sysdesig($args);
                 my $args =
                 {
                  step_replace_params => $param,
                  $param => $node->sysdesig,
                  run => 'next_step',
                 };
                 my $link = Para::Frame::Widget::forward( $label, $uri, $args );
                 my $view = Para::Frame::Widget::jump('visa',
                                                      $node->form_url->as_string,
                                                     );
                 $link .= " - ($view)";
                 return $link;
             },
             button =>
             [
              ['Backa', $req->referer_path(), 'skip_step'],
             ],
            };
            $q->delete_all();
            throw('alternatives', loc("More than one node has the name '[_1]'", $value));
        }
        elsif ( not $objs->size )
        {
            throw('validation', "$value not found");
        }

        my $arc = RDF::Base::Arc->create({
                                          subj    => $id,
                                          pred    => $pred_id,
                                          value   => $objs->get_first_nos,
                                         }, $args );

        $q->delete( $param );   # We will not add the same value twice
    }

    return 1;
}

#########################################################################

=head2 handle_query_row

  $n->handle_query_row( $param, \%args )

Return number of changes

=cut

sub handle_query_row
{
    my( $class, $param, $args ) = @_;

    foreach my $value ( $Para::Frame::REQ->q->param($param) )
    {
        $class->handle_query_row_value( $param, $value, $args );
    }

    return 1;
}

#########################################################################

=head2 handle_query_row_value

  $class->handle_query_row_value( $param, $value, \%args )

Return number of changes

This sub is mainly about setting properties for arcs.  The
subjct is an arc id.  This can be used for saying that an arc is
inactive.

=cut

sub handle_query_row_value
{
    my( $class, $param, $value, $args ) = @_;

    die "missing value" unless defined $value;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $res = $args->{'res'};

    my $arg = parse_form_field_prop($param);

    my $pred_name = $arg->{'pred'}; # In case we should create the prop
    my $arc_id    = $arg->{'arc'}; # arc to update. Create arc if undef
    my $subj_id   = $arg->{'subj'}; # subj for this arc
    my $desig     = $arg->{'desig'}; # look up obj that has $value as $desig
    my $type      = $arg->{'type'};  # desig obj must be of this type
    my $rowno     = $arg->{'row'}; # rownumber for matching props with new/existing arcs
    my $lang	  = $arg->{'lang'}; # lang-code of value (set on value/obj)


    # Set node ... After checking $subj_id

    my $pred = RDF::Base::Pred->get( $pred_name );
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
#    my $valtype = $pred->valtype;
    if ( $coltype eq 'obj' )
    {
        $value = RDF::Base::Resource->get( $value );
    }

#    warn "Modify row $rowno\n";

    if ( $arc_id )
    {
        die "Why is arc_id defined?";
    }
    ;
    if ( $subj_id eq 'arc' )
    {
        # Refering to existing arc
        my $referer_arc_id = $res->arc_id_by_row($rowno);
        $subj_id = $referer_arc_id;

        ## Creating arc for nonexisting arc?
        if ( not $subj_id )
        {
            if ( length $value )
            {
                # Setup undef arc of right type. That is: In order for
                # us to setting the property for this arc, the arc
                # must exist, even if the arc has an undef value.

                my $arc_subj = $res->subj_id_by_row($rowno);
                my $arc_pred = $res->pred_id_by_row($rowno);
                my $subj = RDF::Base::Arc->create({
                                                   subj => $arc_subj,
                                                   pred => $arc_pred,
                                                  }, $args );
                $subj_id = $subj->id;
                $res->set_arc_id_by_row( $rowno, $subj_id );
            }
            else
            {
                # Nothing to do for this row
                next;
            }
        }
    }
    else
    {
        die "Not refering to arc?";
    }

    # Set node
    my $node;
    if ( $subj_id  and $subj_id =~ /^\d+$/ )
    {
        $node = RDF::Base::Resource->get($subj_id);
    }
    else
    {
        confess "subj param not optional";
    }


    # Find with arclim. Set if not found, as new
    my $arcs = RDF::Base::Resource->find({
                                          subj => $node,
                                          pred => $pred,
                                         },
                                         $args );

    if ( length $value )
    {
        my $arc;
        if ( $arc = pop @$arcs )
        {
            $arc = $arc->set_value( $value, $args );
        }
        else
        {
            $arc = RDF::Base::Arc->create({
                                           subj => $node,
                                           pred => $pred,
                                           value => $value,
                                          }, $args );
        }

        # Remove the subject (that is an arc) from deathrow
        $res->remove_from_deathrow( $arc->subj );

        # This arc has been taken care of
        debug  "Removing check_$param";
        $q->delete("check_$param");

    }

    # Remove all other arcs
    foreach my $arc (@$arcs )
    {
        $res->add_to_deathrow( $arc );
    }

    return 1;
}

#########################################################################

=head2 handle_query_check_row

  $class->handle_query_check_row( $param, \%args )

Return number of changes

=cut

sub handle_query_check_row
{
    my( $class, $param, $args ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $res = $args->{'res'};

    my $arg = parse_form_field_prop($param);

    my $pred_name = $arg->{'pred'}; # In case we should create the prop
    my $arc_id    = $arg->{'arc'}; # arc to update. Create arc if undef
    my $subj_id   = $arg->{'subj'}; # subj for this arc
    my $desig     = $arg->{'desig'}; # look up obj that has $value as $desig
    my $type      = $arg->{'type'};  # desig obj must be of this type
    my $rowno     = $arg->{'row'}; # rownumber for matching props with new/existing arcs
    my $lang	  = $arg->{'lang'}; # lang-code of value (set on value/obj)

    # Set node
    my $node;
    if ( $subj_id and $subj_id =~ /^\d+$/ )
    {
        $node = RDF::Base::Resource->get($subj_id);
    }
    else
    {
        $node = $args->{'node'};
    }

    if ( $arc_id )
    {
        die "Why is arc_id defined?";
    }
    ;

    # Refering to existing arc
    my $referer_arc_id = $res->arc_id_by_row($rowno);

    if ( $subj_id eq 'arc' )
    {
        $subj_id = $referer_arc_id;

        ## Creating arc for nonexisting arc?
        if ( not $subj_id )
        {
            # No arc present
            return 1;
        }
        else
        {
#	    warn "  Arc set to $subj_id for row $rowno\n";
        }
    }
    else
    {
        die "Not refering to arc? (@_)";
    }

    my $pred = RDF::Base::Pred->get( $pred_name );
    my $pred_id = $pred->id;

    # Find with arclim. Set if not found, as new
    my $arcs = RDF::Base::Arc->find({
                                     subj    => $subj_id,
                                     pred    => $pred_id,
                                    }, $args );
    # Remove found arcs
    foreach my $arc ( $arcs->as_array )
    {
        $arc->remove( $args );
    }

    return 1;
}

#########################################################################

=head2 handle_query_check_arc

  $class->handle_query_check_arc( $param, $arc_id, \%args )

Return number of changes

=cut

sub handle_query_check_arc
{
    my( $class, $param, $arc_id, $args ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    unless ( $q->param("arc_${arc_id}") )
    {
        $args->{'res'}->add_to_deathrow( RDF::Base::Arc->get($arc_id) );
    }

    return 0;
}

#########################################################################

=head2 handle_query_check_node

  $class->handle_query_check_node( $param, $node_id, \%args )

Return number of changes

=cut

sub handle_query_check_node
{
    my( $class, $param, $node_id, $args ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;


    unless ( grep { /^node_$node_id/ } $q->param )
    {
        my $node = RDF::Base::Resource->get( $node_id );
        debug "Removing node: ${node_id}";
        return $node->remove( $args );
    }
    debug "Saving node: ${node_id}. grep: ". grep( /^node_$node_id/, $q->param );

    return 1;
}

#########################################################################

=head2 handle_query_check_require

  $class->handle_query_check_require( $param, \%args )

Return number of changes

=cut

sub handle_query_check_require
{
    my( $class, $param, $args ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $R = RDF::Base->Resource;

    debug $param;
    debug query_desig($args);

    my $arg = parse_form_field_prop($param);

    my $node_id = $arg->{'subj'} || $args->{'node'};
    die "No node in $param" unless $node_id;
    my $node = $R->get( $node_id );

    my $pred_in = $arg->{'pred'} or die "No pred in $param";
    my $pred = RDF::Base::Pred->get_by_label($pred_in);

    my $scof;
    if ( my $scof_name = $arg->{'scof'} )
    {
        $scof = $R->get($scof_name);
    }

    my $type;
    if ( my $type_name = $arg->{'type'} )
    {
        $type = $R->get($type_name);
    }

    foreach my $arc ( $node->arc_list($pred, undef, $args )->as_array )
    {
        debug "  examining ".$arc->sysdesig;
        if ( $scof )
        {
            unless( $arc->value->scof($scof) )
            {
                debug "    failed ".$scof->desig;
                next;
            }
        }

        if ( $type )
        {
            unless( $arc->value->is($type) )
            {
                debug "    failed ".$scof->desig;
                next;
            }
        }

        return 1;
    }

    my $node_name = $node->desig;
    my $pred_name = $pred->plain;
    my $out = "$node_name is missing a property '$pred_name'";
    if ( $type or $scof )
    {
        $out .= " of the right type";
    }

    throw('validation', $out);
}

#########################################################################

=head2 handle_query_check_prop

  $class->handle_query_check_prop( $param, $pred_in, \%args )

=cut

sub handle_query_check_prop
{
    my( $class, $param, $pred_in, $args ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $pred = RDF::Base::Pred->get( $pred_in );
    my $pred_name = $pred->label;
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;
#    my $valtype = $pred->valtype;

    my $node = $args->{'node'};
    my $id = $node->id;

    debug 3, "Checking param $param ($pred_name)";


    # Remember the values this node has for the pred
    my %has_val;
    foreach my $val ( $node->list($pred_name, undef, $args)->as_array )
    {
        my $val_str = $val->is_literal ? $val->literal : $val->id;
        $has_val{$val_str} ++;
        debug 3, "  has previous value $val_str";
    }

    my %is_set;
    foreach my $value ( $q->param("prop_${pred_name}") )
    {
        $is_set{$value} ++;
        debug 3, "  has new value $value";
    }


    foreach my $val_key ( $q->param($param) )
    {
        my $value = $val_key;
        debug 3, "  handling check $value";
        if ( $coltype eq 'obj' )
        {
            $value = RDF::Base::Resource->get( $val_key );
        }

        # Remove rel
        if ( $has_val{$val_key} and not $is_set{$val_key} )
        {
            my $arcs = RDF::Base::Arc->find({
                                             subj    => $id,
                                             pred    => $pred_id,
                                             value   => $value,
                                            }, $args );

            foreach my $arc ( $arcs->as_array )
            {
                $arc->remove( $args );
            }
        }
        # Add rel
        elsif ( not $has_val{$val_key} and $is_set{$val_key} )
        {
            my $arc = RDF::Base::Arc->create({
                                              subj    => $id,
                                              pred    => $pred_id,
                                              value   => $value,
                                             }, $args );
        }
    }

    return 1;
}


#########################################################################

=head2 handle_query_check_revprop

  $n->handle_query_check_revprop( $param, $pred_name, \%args )

Return number of changes

=cut

sub handle_query_check_revprop
{
    my( $class, $param, $pred_name, $args ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $pred = RDF::Base::Pred->get( $pred_name );
    my $pred_id = $pred->id;
    my $coltype = $pred->coltype;

    my $node = $args->{'node'};
    my $id = $node->id;

    # Remember the values this node has for the pred
    my %has_val;
    foreach my $val ( $node->revlist($pred_name, undef, $args)->as_array )
    {
        my $val_str = $val->is_literal ? $val->literal : $val->id;
        $has_val{$val_str} ++;
    }

    my %is_set;
    foreach my $value ( $q->param("revprop_${pred_name}") )
    {
        $is_set{$value} ++;
    }

    foreach my $val_key ( $q->param($param) )
    {
        my $value = $val_key;
        if ( $coltype eq 'obj' )
        {
            $value = RDF::Base::Resource->get( $val_key );
        }

        # Remove rel
        if ( $has_val{$val_key} and not $is_set{$val_key} )
        {
            my $arcs = RDF::Base::Arc->find({
                                             subj    => $val_key,
                                             pred    => $pred_id,
                                             obj     => $id,
                                            }, $args);

            foreach my $arc ( $arcs->as_array )
            {
                $arc->remove( $args );
            }
        }
        # Add rel
        elsif ( not $has_val{$val_key} and $is_set{$val_key} )
        {
            my $arc = RDF::Base::Arc->create({
                                              subj    => $val_key,
                                              pred    => $pred_id,
                                              value   => $id,
                                             }, $args );
        }
    }

    return 1;
}


#########################################################################

=head2 handle_query_newsubjs

  handle_query_newsubjs( $q, $param, \%args )

Return number of changes

=cut

sub handle_query_newsubjs
{
    my( $q, $newsubj_params, $args ) = @_;

    my %newsubj;
    my %keysubjs;

    foreach my $param (@$newsubj_params)
    {
        my $arg = parse_form_field_prop($param);

        #debug "Newsubj param: $param: ". $q->param($param);
        if ( $arg->{'newsubj'} =~ m/^(main_)?(.*?)$/ )
        {
            next unless $q->param( $param );
            my $main = $1;
            my $no = $2;

            $keysubjs{$no} = 'True'
              if ( $main );
            debug " adding $no"
              if ( $main );

            $newsubj{$no} = {} unless $newsubj{$no};
            $newsubj{$no}{$arg->{'pred'}} = $q->param( $param );

            # Cleaning up newsubj-params to get a clean form...
            $q->delete($param);
        }
    }

    foreach my $ns (sort keys %keysubjs)
    {
        debug "Newsubj creating a node: ". datadump $newsubj{$ns};
        RDF::Base::Resource->create( $newsubj{$ns}, $args );
    }

    return 1;
}


#########################################################################

1;

=head1 SEE ALSO

L<RDF::Base>,
L<RDF::Base::Arc>,
L<RDF::Base::Pred>,
L<RDF::Base::List>,
L<RDF::Base::Search>,
L<RDF::Base::Literal::Time>

=cut
