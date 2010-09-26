package Rit::Base::Action::plugin_Blog_add_comment;

use 5.010;
use strict;
use warnings;

use Para::Frame::L10N qw( loc );
use Para::Frame::Utils qw( throw debug );

use Rit::Base::Utils qw( parse_propargs parse_query_props parse_form_field_prop );
use Rit::Base::Constants qw( $C_plugin_blog_post );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my( $args, $arclim, $res ) = parse_propargs('auto');

    my $name      = $q->param('name')      || '';
    my $has_email = $q->param('has_email') || '';
    my $message   = $q->param('message')   || '';

    my $captcha = $req->site->captcha;

    my $length = length($message);
    throw('validation', "För långt meddelande ($length av 500)")
      if( length($message) > 500 );
    throw('validation', "Felaktig kontrollsträng: ". $captcha->{error})
      if( not $captcha->is_valid );

    $q->delete('name'     );
    $q->delete('has_email');
    $q->delete('message'  );

    my $R = Rit::Base->Resource;

    my $id = $q->param('id');
    my $post = $R->get( $id );

    my( $args, $arclim, $res ) = parse_propargs('auto');
    $post->add_comment( $name, $has_email, $message, $args );
    $res->autocommit({ activate => 1 });

    return "Comment added.";
}

1;
