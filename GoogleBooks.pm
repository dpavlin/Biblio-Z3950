package GoogleBooks;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;
use JSON::XS;

use base 'Scraper';

my $debug = $ENV{DEBUG} || 0;

sub diag {
	warn "# ", @_, $/;
}

# based on http://code.google.com/apis/books/docs/v1/using.html#PerformingSearch
#
# https://www.googleapis.com/books/v1/volumes?q=search+terms
#
# This request has a single required parameter:
#
# q - Search for volumes that contain this text string. There are special keywords you can specify in the search terms to search in particular fields, such as:
#     intitle: Returns results where the text following this keyword is found in the title.
#     inauthor: Returns results where the text following this keyword is found in the author.
#     inpublisher: Returns results where the text following this keyword is found in the publisher.
#     subject: Returns results where the text following this keyword is listed in the category list of the volume.
#     isbn: Returns results where the text following this keyword is the ISBN number.
#     lccn: Returns results where the text following this keyword is the Library of Congress Control Number.
#     oclc: Returns results where the text following this keyword is the Online Computer Library Center number.
#

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
	4		=> 'intitle:',
	7		=> 'isbn:',
	8		=> 'isbn:', # FIXME?
	1003	=> 'inauthor:',
#	16		=> '',
	21		=> 'subject:',
	12		=> 'lccn:',
#	1007	=> '',
	1016	=> '',
}};

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	my $url = 'https://www.googleapis.com/books/v1/volumes?q=' . $query;

diag "get $url";

	my $mech = $self->{mech} || die "no mech?";
	$mech->get( $url );

	my $json = decode_json $mech->content;
	diag "# json = ", dump($json) if $debug;

	my $hits = 0;

	if ( exists $json->{items} ) {
		$hits = $#{ $json->{items} } + 1;
	} else {
		diag "get't find results in ", $mech->content;
		return;
	}

diag "got $hits results, get first one";

	$self->{_json} = $json;
	$self->{_json_item} = 0;

	return $self->{hits} = $hits;
}


our ( $hash, $marc );

sub next_marc {
	my ($self,$format) = @_;

	$format ||= 'marc';

	my $item = $self->{_json}->{items}->[ $self->{_json_item}++ ];

	warn "# item = ",dump($item) if $debug;

	my $id = $item->{id} || die "no id";

	$marc = MARC::Record->new;
	$marc->encoding('utf-8');

	if ( my $vi = $item->{volumeInfo} ) {

		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

		$marc->add_fields('008',sprintf("%02d%02d%02ds%04d%25s%-3s",
				$year % 100, $mon + 1, $mday, substr($vi->{publishedDate},0,4), ' ', $vi->{language}));

		if ( ref $vi->{industryIdentifiers} eq 'ARRAY' ) {
			foreach my $i ( @{ $vi->{industryIdentifiers} } ) {
				if ( $i->{type} =~ m/ISBN/i ) {
					$marc->add_fields('020',' ',' ','a' => $i->{identifier} )
				} else {
					$marc->add_fields('035',' ',' ','a' => $i->{identifier} )
				}
			}
		}

		my $first_author;
		if ( ref $vi->{authors} eq 'ARRAY' ) {
			$first_author = shift @{ $vi->{authors} };
			$marc->add_fields(100,'0',' ','a' => $first_author );
			$marc->add_fields(700,'0',' ','a' => $_ ) foreach @{ $vi->{authors} };
		}

		$marc->add_fields(245, ($first_author ? '1':'0') ,' ',
			'a' => $vi->{title},
			$vi->{subtitle} ? ( 'b' => $vi->{subtitle} ) : (),
		);

		if ( exists $vi->{publisher} or exists $vi->{publishedDate} ) {
			$marc->add_fields(260,' ',' ',
				$vi->{publisher} ? ( 'b' => $vi->{publisher} ) : (),
				$vi->{publishedDate} ? ( 'c' => $vi->{publishedDate} ) : ()
			);
		}

		$marc->add_fields(300,' ',' ','a' => $vi->{pageCount} . 'p.' ) if $vi->{pageCount};
		
		$marc->add_fields(520,' ',' ','a' => $vi->{description} ) if $vi->{description};

 		if ( ref $vi->{categories} eq 'ARRAY' ) {
			$marc->add_fields(650,' ','4','a' => $_ ) foreach @{ $vi->{categories} };
		}

		if ( exists $vi->{imageLinks} ) {

			$marc->add_fields(856,'4','2',
				'3'=> 'Image link',
				'u' => $vi->{imageLinks}->{smallThumbnail},
				'x' => 'smallThumbnail',
			) if exists $vi->{imageLinks}->{smallThumbnail};
			$marc->add_fields(856,'4','2',
				'3'=> 'Image link',
				'u' => $vi->{imageLinks}->{thumbnail},
				'x' => 'thumbnail',
			) if exists $vi->{imageLinks}->{thumbnail};

		} # if imageLinks

		$marc->add_fields(856,'4','2',
			'3'=> 'Info link',
			'u' => $vi->{infoLink},
		);
		$marc->add_fields(856,'4','2',
			'3'=> 'Show reviews link',
			'u' => $vi->{showReviewsLink},
		);

		my $leader = $marc->leader;
		warn "# leader [$leader]";
		$leader =~ s/^(....).../$1nam/;
		$marc->leader( $leader );

	} else {
		warn "ERROR: no volumeInfo in ",dump($item);
	}

	$marc->add_fields( 856, ' ', ' ', 'u' => $item->{accessInfo}->{webReaderLink} );
#	$marc->add_fields( 520, ' ', ' ', 'a' => $item->{searchInfo}->{textSnippet} ); # duplicate of description

#	diag "# hash ",dump($hash);
	diag "# marc ", $marc->as_formatted;

	$self->save_marc( "$id.marc", $marc->as_usmarc );

	return $id;

}

1;
