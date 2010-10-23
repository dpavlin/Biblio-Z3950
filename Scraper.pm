package Scraper;

use warnings;
use strict;

use WWW::Mechanize;

sub new {
    my ( $class ) = @_;
    my $self = {
		mech => WWW::Mechanize->new(),
	};
    bless $self, $class;
    return $self;
}

sub save_marc {
	my ( $self, $id, $marc ) = @_;

	my $database = ref $self;
	mkdir 'marc' unless -e 'marc';
	mkdir "marc/$database" unless -e "marc/$database";

	my $path = "marc/$database/$id";

	open(my $out, '>:utf8', $path) || die "$path: $!";
	print $out $marc;
	close($out);

	warn "# created $path ", -s $path, " bytes";

}

1;
