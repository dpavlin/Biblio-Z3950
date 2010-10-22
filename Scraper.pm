package Scraper;

use warnings;
use strict;

use WWW::Mechanize;

binmode STDOUT, ':utf8';

sub new {
    my ( $class ) = @_;
    my $self = {
		mech => WWW::Mechanize->new(),
	};
    bless $self, $class;
    return $self;
}

