#  $Id$  -*-cperl-*-
package Rit::Base::Pred;
#=====================================================================
#
# DESCRIPTION
#   Ritbase Resource Pred class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005-2006 Avisita AB.  All Rights Reserved.
#
#=====================================================================

=head1 NAME

Rit::Base::Pred

=cut

use Carp qw( cluck confess carp croak );
use Data::Dumper;
use strict;
use Time::HiRes qw( time );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( throw debug );
use Para::Frame::Reload;

use Rit::Base::List;
use Rit::Base::Utils qw( cache_update valclean translate is_undef );
use Rit::Base::String;


### Inherit
#
use base qw( Rit::Base::Resource );


#### INIT

our $special_id =
{
 id     => -1,
 score  => -2,
 random => -3,
 desig  => -4,
 'loc'   => -5,
 plain  => -6,
};

our $special_label = { reverse %$special_id };

=head1 DESCRIPTION

Represents preds.

Inherits from L<Rit::Base::Resource>.

=cut




#########################################################################
################################  Constructors  #########################

=head1 Constructors

These can be called with the class name or any arc object.

=cut

#######################################################################

=head2 find

  $p->find()

  $p->find( $label )

  $p->find( $key => $value )

  $p->find({ $key1 => $value1, $key2 => $value2, ... })

With no params, returns a L<Rit::Base::List> with all predicates.

With one param, returns a L<Rit::Base::List> with the
L<Rit::Base::Pred> object with that label.

For the params as key/value pair, look up all predicates that matches
all the given properties.  The only supported content for the keys are
L</label> and L</valtype>.

Returns: a L<Rit::Base::List>

=cut

sub find
{
    my( $this, $props, $default ) = @_;
    my $class = ref($this) || $this;

    my $recs;

    if( $props )
    {
	unless( ref $props )
	{
	    if( defined $default )
	    {
		$props = { $props => $default };
	    }
	    else
	    {
		$props = { 'label' => $props };
	    }
	    $default = undef;
	}

	# Special case for label lookup
	if( my $label = $props->{'label'} )
	{
	    my $pred = $Rit::Base::Cache::PredId{ $label };
	    my $preds;
	    if( $pred )
	    {
		$preds = Rit::Base::List->new([$pred]);
	    }
	    else
	    {
		$preds = $class->find_by_label( $label );
		$pred = $preds->[0];
		unless( $pred )
		{
		    return $preds;
		}
		$Rit::Base::Cache::PredId{ $label } = $pred->id;
	    }


	    # Narrow the serach for the rest of the props
	    if( scalar(keys %$props) > 2 )
	    {
		# Do not modify the $props given as argument
		my %newprops = %$props;
		delete $newprops{'label'};
		return $preds->find(\%newprops);
	    }
	    return $preds;
	}


	my( @values, @parts );

	if( $props->{'valtype'} )
	{
	    push @parts, "valtype=?";
	    my $val = $props->{'valtype'};
	    $val = $val->literal;
	    push @values, $val;
	    delete $props->{'valtype'};
	}

	if( scalar %$props )
	{
	    die "not implemented: ".join(', ', keys %$props);
	}

	if( $default )
	{
	    die "not implemented";
	}

	my $and_part = join " and ", @parts;
	my $st = "select * from reltype where $and_part";
	my $sth = $Rit::dbix->dbh->prepare($st);
	$sth->execute(@values);
	$recs = $sth->fetchall_arrayref({});
	$sth->finish;
    }
    else
    {
	$recs = $Rit::dbix->select_list('from reltype order by label');
    }

    my @preds;
    foreach my $rec (@$recs)
    {
	push @preds, $class->get_by_rec( $rec );
    }

    return Rit::Base::List->new( \@preds );
}

#######################################################################

=head2 create

  $p->create(\%props)

Creates a new predicate and stores it in the DB.

The supported properties are:

id: Defaults to the next free node id value

label: See L</label>. Mandatory

valtype: See L</valtype>. Mandatory

comment: Sets a comment. Optional

domain_is: Optional

domain_scof: Optional

range_is: Optional

range_scof: Optional

TODO: Implement the domain and range

Returns: The created object.

=cut

sub create
{
    my( $this, $props, $changes_ref ) = @_;
    my $class = ref($this) || $this;

    my $req = $Para::Frame::REQ;
    my $dbix = $Rit::dbix;

    my( @fields, @values );
    my $rec = {};


    ##################### id
    if( $props->{'id'} )
    {
	$rec->{'id'}  = $props->{'id'};
    }
    else
    {
	$rec->{'id'}  = $dbix->get_nextval('node_seq');
    }
    push @fields, 'id';
    push @values, $rec->{'id'};


    ##################### label
    if( $props->{'label'} )
    {
	$rec->{'label'}  = $props->{'label'};
    }
    else
    {
	throw('action', "Label missing");
    }
    push @fields, 'label';
    push @values, $rec->{'label'};


    ##################### valtype
    if( $props->{'valtype'} )
    {
	$rec->{'valtype'}  = $props->{'valtype'};
    }
    else
    {
	throw('action', "valtype missing");
    }
    push @fields, 'valtype';
    push @values, $rec->{'valtype'};


    ##################### Optional properties
    foreach my $key (qw(comment))
    {
	if( $props->{$key} )
	{
	    $rec->{$key}  = $props->{$key};
	    $rec->{$key}  = $rec->{$key}->plain if ref $rec->{$key};

	    push @fields, $key;
	    push @values, $rec->{$key};
	}
    }

    ##################### Optional properties
    foreach my $key (qw(domain_is domain_scof range_is range_scof))
    {
	if( $props->{$key} )
	{
	    $rec->{$key}  = Rit::Base::Resource->get( $props->{$key} )->id;

	    push @fields, $key;
	    push @values, $rec->{$key};
	}
    }

    #####################

    my $fields_part = join ",", @fields;
    my $values_part = join ",", map "?", @fields;

    my $st = "insert into reltype ($fields_part) values ($values_part)";
    my $sth = $dbix->dbh->prepare($st);
    $sth->execute( @values );



    my $pred = $class->get_by_rec( $rec );

#    # TODO: Make this a constant
#    my $predicate_class = Rit::Base::Resource->get({
#						    name => 'predicate',
#						    is => 'class',
#						   });
#    $pred->add({ is => $predicate_class });



    $$changes_ref ++ if $changes_ref; # increment changes

    cache_update;

    return $pred;
}



#########################################################################
################################  Accessors  ############################

=head1 Accessors

=cut

#######################################################################

=head2 id

  $p->id

An id of the node, not conflicting with any other
L<Rit::Base::Resource>.

Returns: An integer

=cut

sub id
{
    my( $pred ) = @_;

    return $pred->{'id'};
}

#######################################################################

=head2 name

  $p->name

Returns: The name of the predicate as a L<Rit::Base::String> object

=cut

sub name
{
    my( $pred ) = @_;

    confess "not an obj: $pred" unless ref $pred;
    return new Rit::Base::String $pred->{'name'};
}

#######################################################################

=head2 value

Same as L</name>

=cut

sub value
{
    $_[0]->name;
}

#######################################################################

=head2 plain

  $p->plain

Same as C<$p->name->plain>

Returns: The name as a scalar string

=cut

sub plain
{
    $_[0]->{'name'};
}

#######################################################################

=head2 syskey

  $p->syskey

Returns a unique predictable id representing this object, as a scalar
string

=cut

sub syskey
{
    return sprintf("pred:%d", shift->{'id'});
}


#######################################################################

=head2 valtype

  $p->valtype()

  $p->valtype( $subj )

  $p->valtype( $props )

Find the valtype of a predicate. If called with $subj or a ref to a
hash of properties, find the valtype for a value property.

Returns: The valtype as a scalar string

=cut

sub valtype
{
    my( $pred, $subj ) = @_;

    my $valtype = $pred->{'valtype'};

#    debug "Getting valtype for $pred->{id} with subj $subj->{id} and valtype $valtype\n";

    if( $valtype eq "value" )
    {
	if( $subj )
	{
	    if( not UNIVERSAL::isa($subj,'Rit::Base::Resource') )
	    {
		# Ugly hack. Fix the source of the problem instead!
		my $dv = $subj->{'datatype'};
		unless( $dv )
		{
		    confess "Called coltype with strange subj: ".Dumper($subj);
		}
#		debug "  from $dv name\n";
		$valtype = $dv->name->literal;
#		debug "  Datatype for value is $valtype\n";
	    }
	    elsif( my $dv = $subj->first_prop('datatype') )
	    {
#		debug "  from $dv->{id} name\n";
		$valtype = $dv->name->literal;
#		debug "  Datatype for value is $valtype\n";
	    }
	    else
	    {
#		croak "No datatype found";
		confess "No datatype found for subj $subj->{'id'}: ".Dumper($subj->first_prop('datatype'))." with pred ".$pred->name;
	    }
	}
	else
	{
#	    croak "valtype value requires knowledge of subj";
	    confess "valtype value requires knowledge of subj";
	}
    }

    return $valtype;
}

#######################################################################

=head2 set_valtype

  $p->set_valtype( $value )

Sets the valtype of the predicate to C<$value> and updates the DB.

The C<$value> must be a scalar string.

Returns: The C<$value>

=cut

sub set_valtype
{
    my( $pred, $value ) = @_;

    if( defined $value )
    {
	return $value if $value eq $pred->{'valtype'};

	$pred->{'valtype'} = $value;

	my $dbh = $Rit::dbix->dbh;

	my $sth = $dbh->prepare("update reltype set valtype=? where id=?");
	$sth->execute($value, $pred->id);
    }

    return $pred->{'valtype'};
}


#######################################################################

=head2 objtype

  $p->objtype()

  $p->objtype( $subj )

  $p->objtype( \%props )

Returns true if the L</coltype> the value is 'obj'.  This will not
return true if the real value is a literal resource, unless the
literal resource has a value that is a node.

Calls L</coltype> with the given params.

Returns: 1 or 0

=cut

sub objtype
{
    return shift->coltype(@_) eq 'obj' ? 1 : 0;
}


#######################################################################

=head2 coltype

  $p->coltype()

  $p->coltype( $subj )

  $p->coltype( \%props )

Can be called with a subject node or a ref to a hash of properties.
These are used to find the datatype of a value property.

TODO: Put this in the DB

The retuned value will be one of C<valint>, C<obj>, C<valtext>,
C<valdate>, C<valfloat>.

Returns: A scalar string

=cut

sub coltype
{
    my( $pred, $subj ) = @_;

    # valtype value is note cached
    unless( $pred->{'coltype'} )
    {
#	warn "Calling valtype for $pred\n";
	my $valtype = $pred->valtype( $subj );

#	debug "valtype == $valtype\n"; ### DEBUG
	my $coltype;
	if   ( $valtype eq "id"       ){ $coltype="valint"  }
	elsif( $valtype eq "score"    ){ $coltype="valint"  }
	elsif( $valtype eq "random"   ){ $coltype="valint"  }
	elsif( $valtype eq "obj"      ){ $coltype="obj"     }
	elsif( $valtype eq "int"      ){ $coltype="valint"  }
	elsif( $valtype eq "text"     ){ $coltype="valtext" }
	elsif( $valtype eq "textbox"  ){ $coltype="valtext" }
	elsif( $valtype eq "date"     ){ $coltype="valdate" }
	elsif( $valtype eq "password" ){ $coltype="valtext" }
	elsif( $valtype eq "bool"     ){ $coltype="valint"  }
	elsif( $valtype eq "zipcode"  ){ $coltype="valtext" }
	elsif( $valtype eq "phone"    ){ $coltype="valtext" }
	elsif( $valtype eq "url"      ){ $coltype="valtext" }
	elsif( $valtype eq "file"     ){ $coltype="valtext" }
	elsif( $valtype eq "email"    ){ $coltype="valtext" }
	elsif( $valtype eq "float"    ){ $coltype="valfloat"}
	else
	{
	    confess "valtype $valtype not recognized";
	}

	if( $valtype eq "value" )
	{
	    return $coltype;
	}
	else
	{
	    $pred->{'coltype'} = $coltype;
	}
    }

#    warn "coltype is $pred->{'coltype'}\n";
    return $pred->{'coltype'};
}

#########################################################################
################################  Public methods  #######################


=head1 Public methods

=cut

#######################################################################

=head2 find_set

  $Pred->find_set( \%criterions, \%default, \$counter )

  $Pred->find_set( \%criterions, \%default )

  $Pred->find_set( \%criterions )

Searches for a pred matching the criterions.

If non is found; creates it.

For each default, if the pred doesn't has the property, sets it with
the given value.

The counter is a scalar ref to a number that is incremented if there
was a change made.

Exceptions:

  alternatives : Flera preds matchar kriterierna

Returns:

  The predicate object

Example:

  use Rit::Base::Constants qw( $C_business $C_certificate );
  Rit::Base::Pred->find_set(
    {
      label => 'can_have_cert',
    },
    {
       valtype => 'obj',
       comment => "Business of this type can have certs of this type",
       domain_scof => $C_business,
       range_scof  => $C_certificate,
    });


=cut

sub find_set  # Find the one matching pred or create one
{
    my( $this, $props, $default, $changes_ref ) = @_;

    my $DEBUG = 0;

    my $preds = $this->find( $props );
    $default ||= {};

    if( $preds->[1] )
    {
	my $result = $Para::Frame::REQ->result;
	$result->{'info'}{'alternatives'}{'alts'} = $preds;
	$result->{'info'}{'alternatives'}{'query'} = $props;
	throw('alternatives', "Flera preds matchar kriterierna");
    }
    unless( $preds->[0] )
    {
	foreach my $pred ( keys %$default )
	{
	    $props->{$pred} ||= $default->{$pred};
	}
	warn "Will now create pred with: ".Dumper($props) if $DEBUG;
	$$changes_ref ++ if $changes_ref; # increment changes
	return $this->create($props);
    }

    my $pred = $preds->[0];
    return $pred;
}


#######################################################################

=head2 is_pred

Is this a pred? Yes.

Returns: 1

=cut

sub is_pred { 1 };


#########################################################################
################################  Private methods  ######################

=head2 find_by_label

=cut

sub find_by_label
{
    my( $this, $label, $no_list ) = @_;
    my $class = ref($this) || $this;

#    warn "New pred $label\n"; ### DEBUG

    $label = $label->literal if ref $label;
    $label or confess "get_by_label got empty label";

    # Special properties
    if( $label =~ /^(id|score|random)$/ )
    {
	return $class->get_by_rec({
				   label   => $1,
				   valtype => $1,
				   id      => $special_id->{$1},
				  });
    }
    if( $label =~ /^(desig|loc|plain)$/ )
    {
	return $class->get_by_rec({
				   label   => $1,
				   valtype => 'text',
				   id      => $special_id->{$1},
				  });
    }

    my $sql = 'select * from reltype where ';

    if( $label =~ /^-?\d+$/ )
    {
	return $this->get_by_label( $special_label->{$label} );
    }
    else
    {
	$sql .= 'label = ?';
    }

    my $req = $Para::Frame::REQ;

    my $sth = $Rit::dbix->dbh->prepare($sql);
    $sth->execute($label);
    my $rec = $sth->fetchrow_hashref;
    $sth->finish;

    if( $no_list )
    {
	if( $rec )
	{
	    return $class->get_by_rec( $rec );
	}
	else
	{
	    return is_undef;
	}
    }
    else
    {
	if( $rec )
	{
	    return Rit::Base::List->new([$class->get_by_rec( $rec )]);
	}
	else
	{
	    return Rit::Base::List->new([]);
	}
    }
}


#######################################################################

=head2 get_by_label

=cut

sub get_by_label
{
    my( $node ) = shift->find_by_label($_[0], 1);

    if( $node )
    {
	return $node;
    }
    else
    {
	confess "No such predicate: @_\n";
    }
}


#######################################################################

=head2 init

=cut

sub init
{
    my( $pred, $rec ) = @_;

    my $id = $pred->{'id'};
    unless( $rec )
    {
	if( $id < 0 ) # Special pred not stored in db
	{
	    croak "Pred init misses a rec for negative id";
	}

	my $sth_id = $Rit::dbix->dbh->prepare("select * from reltype where id = ?")
	  or die;
	$sth_id->execute($id);
	$rec = $sth_id->fetchrow_hashref;
	$sth_id->finish;
	$rec or confess "Predicate '$id' not found";
    }

    $pred->{'name'}         = $rec->{'label'};
    $pred->{'valtype'}      = $rec->{'valtype'};
    $pred->{'comment'}      = $rec->{'comment'};
    $pred->{'domain_is'}    = $rec->{'domain_is'};
    $pred->{'domain_scof'}  = $rec->{'domain_scof'};
    $pred->{'range_is'}     = $rec->{'range_is'};
    $pred->{'range_scof'}   = $rec->{'range_scof'};

    foreach my $key (qw(domain_is domain_scof range_is range_scof))
    {
	if( $rec->{$key} )
	{
	    $pred->{$key} = Rit::Base::Resource->get( $rec->{$key} );
	}
    }

    return $pred;
}

#######################################################################

1;

=head1 SEE ALSO

L<Rit::Base>,
L<Rit::Base::Resource>,
L<Rit::Base::Arc>,
L<Rit::Base::List>,
L<Rit::Base::Search>

=cut
