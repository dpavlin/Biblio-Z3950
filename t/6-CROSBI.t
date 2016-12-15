#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 21;

my $search = join(' ', @ARGV) || 'fti_au:denis bratko';

use_ok 'CROSBI';

ok( my $o = CROSBI->new(), 'new' );

foreach my $database ( qw( CROSBI-CASOPIS CROSBI-PREPRINT CROSBI-RKNJIGA CROSBI-ZBORNIK ) ) {
	diag $o->{database} = $database;

ok( my $hits = $o->search( $search ), "search: $search" );
like $hits, qr/^\d+$/, "hits: $hits";

diag "SQL", $o->{sql};

$hits = 3 if $hits > 3 && ! $ENV{DEBUG};

foreach ( 1 .. $hits ) {

	ok( my $marc = $o->next_marc, "next_marc $o->{database} $_" );
	diag $marc;

}

} # database

