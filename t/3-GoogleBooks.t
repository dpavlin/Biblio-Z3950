#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 7;

use_ok 'GoogleBooks';

ok( my $o = GoogleBooks->new(), 'new' );

ok( my $hits = $o->search( 'croatia' ), 'search' );
like $hits, qr/^\d+$/, "hits: $hits";

foreach ( 1 .. 3 ) {

	ok( my $marc = $o->next_marc, "next_marc $_" );
	diag $marc;

}
