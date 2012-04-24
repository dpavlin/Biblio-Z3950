package vuFind;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;
use JSON::XS;
use Encode;

use base 'Scraper';

my $debug = $ENV{DEBUG} || 0;

sub diag {
	warn "# ", @_, $/;
}

# Koha Z39.50 query:
#
# Bib-1 @and @and @and @and @and @and @and @or
# @attr 1=4 title 
# @attr 1=7 isbn
# @attr 1=8 issn 
# @attr 1=1003 author 
# @attr 1=16 dewey 
# @attr 1=21 subject-holding 
# @attr 1=12 control-no 
# @attr 1=1007 standard-id 
# @attr 1=1016 any

sub usemap {{
	4		=> 'title',
	7		=> 'isn',
	8		=> 'isn',
	1003	=> 'author',
#	16		=> '',
	21		=> 'subject',
#	12		=> '',
#	1007	=> '',
	1016	=> 'all',
}};

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	# http://catalog.hathitrust.org/Search/Home?lookfor=croatia%20AND%20zagreb&type=title
	my $url = 'http://catalog.hathitrust.org/Search/Home?lookfor=' . $query;

diag "get $url";

	$self->mech->get( $url );

	my $hits = 0;

	if ( $self->mech->content =~ m{of\s*<span class="strong">(\d+)</span>\s*Results for}s ) {
		$hits = $1;
	} else {
		diag "get't find results in ", $self->mech->content;
		return;
	}

diag "got $hits results";

	foreach my $link ( $self->mech->find_all_links( url_regex => qr{/Record/\d+} ) ) {
		push @{ $self->{records} }, $link->url;
	}

	return $self->{hits} = $hits;
}


sub next_marc {
	my ($self,$format) = @_;

	$format ||= 'marc';

	my $url = shift @{ $self->{records} };

	my $id = $1 if $url =~ m{Record/(\d+)};

	$self->mech->get( $url . '.mrc' );

	my $marc = decode('utf-8', $self->mech->content );

	$self->save_marc( "$id.marc", $marc );

	return $id;

}

1;
