#  $Id$  -*-cperl-*-
package Rit::Base::Constants;

=head1 NAME

Rit::Base::Constants

=cut

use strict;
use Carp qw( croak cluck );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

#use Para::Frame::Reload;
use Para::Frame::Utils qw( debug datadump );

use Rit::Base;

our %Constant; # The initiated constants
our $AUTOLOAD;
our @Initlist; # Constants to export then the DB is online

sub import
{
    my $class = shift;

    my $callpkg = caller();
    no strict 'refs'; # Symbolic refs

    my $temp = bless{NOT_INITIALIZED=>1};

    foreach my $const ( @_ )
    {
	$const =~ /^\$C_(\w+)/ or croak "malformed constant: $const";
	debug "Package $callpkg imports $1";

	if( $Rit::dbix )
	{
	    my $obj = $class->get($1);
	    *{"$callpkg\::C_$1"} = \ $obj;
	}
	else
	{
	    push @Initlist, ["$callpkg\::C_$1", $1];

	    # Temporary placeholder
	    *{"$callpkg\::C_$1"} = \ $temp;
	}
    }
}

sub new ()
{
    return bless {};
}

sub get
{
    my( $this, $label ) = @_;

    unless( $Constant{$label} )
    {
#	debug "Initiating constant $label";
	my $sth = $Rit::dbix->dbh->prepare(
		  "select sub from constant where label=?");
	$sth->execute( $label );
	my( $id ) = $sth->fetchrow_array;
	$sth->finish;

	unless( $id )
	{
	    croak "Constant $label doesn't exist";
	}

	$Constant{$label} = Rit::Base::Resource->get( $id );
    }

    # TODO: Handle resetting of the given nodes

    return $Constant{$label};
}

sub init
{
    my( $class ) = @_;
    no strict 'refs'; # Symbolic refs
    foreach my $export (@Initlist)
    {
	my $obj = $class->get($export->[1]);
	*{$export->[0]} = \ $obj;
    }
}


######################################################################

=head2 add

  Rit::Base::Constants->add( $label, $node )

Adds a constant to the database.

=cut

sub add
{
    my( $class, $label, $node ) = @_;

    die "Constant labels cannot start with 'C_'"
      if $label =~ /^C_/;

    $Rit::dbix->commit;
    eval
    {
	$Rit::dbix->dbh->do("INSERT INTO constant (label,sub,updated_by) values (?,?,?)",
			    {}, $label, $node->id, $Para::Frame::REQ->user->id);
    };

    if( $@ )
    {
	if( $Rit::dbix->dbh->state eq 23505 )
	{
	    $Rit::dbix->rollback;
	}
	else
	{
	    die $@;
	}
    }
}


######################################################################

AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD =~ /DESTROY$/;
#    debug "Autoloading constant $AUTOLOAD";
    return  $Constant{$AUTOLOAD} || Rit::Base::Constants->get($AUTOLOAD);
}

1;
