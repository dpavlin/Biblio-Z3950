#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 5;

my $search = join(' ', @ARGV) || 'denis bratko';

use_ok 'CROSBI';

ok( my $o = CROSBI->new(), 'new' );

ok( my $hits = $o->search( $search ), "search: $search" );
like $hits, qr/^\d+$/, "hits: $hits";

diag "SQL", $o->{sql};

foreach ( 1 .. $hits ) {

	ok( my $marc = $o->next_marc, "next_marc $_" );
	diag $marc;

}
