package Rit::Base::Widget::Plugins;

use strict;
use warnings;

use Template::Constants;

use Para::Frame::Reload;

use Rit::Base::Widget;
use Rit::Base::Utils qw( parse_propargs );

sub new
{
    confess "deprecated";

    return bless {}, $_[0];
}

sub fetch
{
    my ($self, $name, $args, $context) = @_;

    warn "Looking for plugin $name\n";

    $self->{ FACTORY } ||=
    {
     wub => sub
     {
	 my( $context ) = shift;
	 return sub
	 {
	     my( $pred, $args_in ) = @_;
	     my( $args ) = parse_propargs($args_in);
	     $args->{'context'} = $context;
	     return Rit::Base::Widget::wub($pred, $args);
	 }
     },
     wub_area => sub
     {
	 my( $context ) = shift;
	 return sub
	 {
	     my( $pred, $args_in ) = @_;
	     my( $args ) = parse_propargs($args_in);
	     $args->{'context'} = $context;
	     return Rit::Base::Widget::wub_area($pred, $args);
	 }
     },
    };

    my $factory = $self->{ FACTORY }{$name};

    unless( $factory )
    {
	return (undef, Template::Constants::STATUS_DECLINED);
    }

    return  &$factory($context, @$args);
}


1;
