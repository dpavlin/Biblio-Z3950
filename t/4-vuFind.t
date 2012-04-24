#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 29;

my $search = join(' ', @ARGV) || 'croatia';

use_ok 'vuFind';

ok( my $o = vuFind->new(), 'new' );

ok( my $hits = $o->search( $search ), "search: $search" );
like $hits, qr/^\d+$/, "hits: $hits";

foreach ( 1 .. 25 ) { # > 20 to hit next page

	ok( my $marc = $o->next_marc, "next_marc $_" );
	diag $marc;

}
