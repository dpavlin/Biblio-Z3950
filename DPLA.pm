package DPLA;

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

# http://dp.la/dev/wiki/Item_API
#
# Base Fields: Mapping to a set of common terms
# Field name 	Field description
# dpla.keyword 	Almost all of a record's fields get copied to this field
# dpla.title 	The title and/or subtitle of the item. Exact matching.
# dpla.title_keyword 	The title and/or subtitle of the item. Keyword matching.
# dpla.creator 	The creator(s), contributor(s), editor(s), etc. of the item. Exact matching
# dpla.creator_keyword 	The creator(s), contributor(s), editor(s), etc. of the item. Keyword matching
# dpla.date 	The item's date of publication.
# dpla.description 	The item's description. This often includes the item's Table of Contents. Exact matching.
# dpla.description_keyword 	The item's description. This often includes the item's Table of Contents. Keyword matching.
# dpla.subject 	A catchall for subject information. LCSH, Dewey, and other tag related fields are copied to this field. Exact matching.
# dpla.subject_keyword 	A catchall for subject information. LCSH, Dewey, and other tag related fields are copied to this field. Keyword matching.
# dpla.publisher 	The name of the publisher. Exact matching.
# dpla.language 	The primary language of the item. Exact matching.
# dpla.isbn 	The item's ISBN. Exact matching.
# dpla.oclc 	The item's OCLC identifier. Exact matching.
# dpla.lccn 	The item's LCCN. Exact matching.
# dpla.call_num 	The item's call number. Exact matching.
# dpla.content_link 	A link to the item's content. Exact matching.
# dpla.contributor 	The contributing partner. Exact matching.
# dpla.resource_type 	The resource's type. Common values include item and collection. Exact matching.

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
	4		=> 'dpla.title_keyword',
	7		=> 'dpla.isbn',
	8		=> 'dpla.keyword', # XXX fake
	1003	=> 'dpla.creator_keyword',
#	16		=> '',
	21		=> 'dpla.subject',
#	12		=> '',
#	1007	=> '',
	1016	=> 'dpla.keyword',

	RPN => {
		And => '&',
		Or  => '&',	# FIXME sigh, not really supported?
	},
	prefix_term => sub {
		my ( $prefix, $term ) = @_;
		return 'filter=' . $prefix . ':' . $term;
	}
}};

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	my $url = 'http://api.dp.la/v0.03/item/?' . $query;

diag "get $url";

	my $mech = $self->mech;

	$mech->get( $url );

	my $json = decode_json $mech->content;
	diag "# json = ", dump($json) if $debug;

	my $hits = 0;

	if ( exists $json->{num_found} ) {
		$hits = $json->{num_found};
	} else {
		diag "get't find num_found in ", $mech->content;
		return;
	}

diag "got $hits results";

	$self->{_json} = $json;

	return $self->{hits} = $hits;
}

sub next_marc {
	my ($self,$format) = @_;

	$format ||= 'marc';

	my $item = shift @{ $self->{_json}->{docs} };

	my $marc = MARC::Record->new;
	$marc->encoding('utf-8');

	my $fields; # empty marc

	foreach my $key ( sort keys %$item ) {
		my $v = $item->{$key};
		warn "# item ",dump( $key, $v ) if $debug;
		if ( $key =~ m/^(\d\d\d)(\w)$/ ) {
			my ($f,$sf) = ($1,$2);

			# XXX do magic and unroll into proper MARC record

			$v = [ $v ] unless ref $v eq 'ARRAY';

			if ( $fields ) {
				if ( $fields->[0]->[0] ne $f ) {
					$marc->add_fields( @$fields );
					warn "# add_fields ",dump($fields) if $debug;
					$fields = undef;
				}
			}
			foreach my $i ( 0 .. $#$v ) {
				$fields->[$i]->[0] = $f;
				$fields->[$i]->[1] = ' ';
				$fields->[$i]->[2] = ' ';
				push @{ $fields->[$i] }, $sf, $v->[$i];
			}

		} else {
			warn "# IGNORED: $key ", dump($item->{$key}), "\n";
		}
	}

	$marc->add_fields( @$fields );

	diag "# marc ", $marc->as_formatted;

	warn dump( $marc->as_usmarc );

	$self->mech->back; # return to search results for next page

	my $id = $item->{'dpla.id'};

	if ( ! $id ) {
			warn "no dpla.id in ",dump($item);
			return;
	}

	$self->save_marc( "$id.marc", $marc->as_usmarc );

	return $id;

}

1;
