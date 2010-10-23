#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 6;

use_ok 'Aleph';

ok( my $o = Aleph->new, 'new' );

ok( my $hits = $o->search( 'WTI=linux' ), 'search' );
diag "$hits results";

foreach ( 1 .. 3 ) {

ok( my $marc = $o->next_marc, "next_marc $_" );
diag $marc;

}
