#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 6;

use_ok 'COBISS';

ok( my $o = COBISS->new, 'new' );

ok( my $hits = $o->search( 'TI=book' ), 'search' );
diag "$hits results";

foreach ( 1 .. 3 ) {

ok( my $marc = $o->next_marc, "next_marc $_" );
diag $marc;

}
