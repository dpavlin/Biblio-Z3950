#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 3;

use_ok 'COBISS';

ok( my $search = COBISS->search( 'TI=book' ), 'search' );

ok( my $marc = COBISS->fetch_marc, 'fetch_marc' );
