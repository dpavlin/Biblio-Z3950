package Scraper;

use warnings;
use strict;

use WWW::Mechanize;

sub new {
    my ( $class, $database ) = @_;

	$database ||= $class;

    my $self = {
		mech => WWW::Mechanize->new(),
		database => $database,
	};
    bless $self, $class;
    return $self;
}

sub mech { $_[0]->{mech} }

sub save_marc {
	my ( $self, $id, $marc ) = @_;

	my $database = $self->{database};
	mkdir 'marc' unless -e 'marc';
	mkdir "marc/$database" unless -e "marc/$database";

	my $path = "marc/$database/$id";

	open(my $out, '>:utf8', $path) || die "$path: $!";
	print $out $marc;
	close($out);

	warn "# created $path ", -s $path, " bytes";

}

our $dump_nr = 1;

sub save_content {
	my $self = shift;
	my $path = "/tmp/$dump_nr.html";
	open(my $html, '>', $path);
	print $html $self->{mech}->content;
	close($html);
	warn "# save_content $path ", -s $path, " bytes";
	$dump_nr++;
}

1;
