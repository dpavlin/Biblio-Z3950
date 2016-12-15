#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 11;

my $search = join(' ', @ARGV) || 'fti_au:denis bratko';

use_ok 'CROSBI';

ok( my $o = CROSBI->new(), 'new' );

foreach my $database ( qw( CROSBI-CASOPIS CROSBI-PREPRINT CROSBI-RKNJIGA ) ) {
	diag $o->{database} = $database;

ok( my $hits = $o->search( $search ), "search: $search" );
like $hits, qr/^\d+$/, "hits: $hits";

diag "SQL", $o->{sql};

$hits = 3 unless $ENV{DEBUG};

foreach ( 1 .. $hits ) {

	ok( my $marc = $o->next_marc, "next_marc $o->{database} $_" );
	diag $marc;

}

} # database

