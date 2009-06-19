#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 2;

use_ok 'COBISS';

ok( my $results = COBISS->search() );

