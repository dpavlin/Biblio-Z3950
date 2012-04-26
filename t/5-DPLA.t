#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 29;

my $search = join(' ', @ARGV) || 'krleža';

use_ok 'DPLA';

ok( my $o = DPLA->new(), 'new' );

ok( my $hits = $o->search( $o->usemap->{prefix_term}->( 'dpla.keyword' => $search ) ), "search: $search" );
like $hits, qr/^\d+$/, "hits: $hits";

foreach ( 1 .. 25 ) { # > 20 to hit next page

	ok( my $marc = $o->next_marc, "next_marc $_" );
	diag $marc;

}
