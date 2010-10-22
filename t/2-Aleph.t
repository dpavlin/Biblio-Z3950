#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 4;

use_ok 'Aleph';

ok( my $o = Aleph->new, 'new' );

ok( my $hits = $o->search( 'WTI=linux' ), 'search' );
diag "$hits results";

ok( my $marc = $o->next_marc, 'next_marc' );
diag $marc;
