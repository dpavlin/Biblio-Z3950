#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 3;

use_ok 'Aleph';

ok( my $search = Aleph->search( 'WTI=linux' ), 'search' );

ok( my $marc = Aleph->next_marc, 'next_marc' );
