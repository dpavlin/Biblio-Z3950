package COBISS;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;

use base 'Scraper';

my $cobiss_marc21 = {
	'010' => { a => [ '020', 'a' ] },
	 200  => {
			a => [  245 , 'a' ],
			f => [  245 , 'f' ],
	},
	 205  => { a => [  250 , 'a' ] },
	 210  => {
		a => [  260 , 'a' ],
		c => [  260 , 'b' ],
		d => [  260 , 'c' ],
	},
	215 => {
		a => [  300 , 'a' ],
		c => [  300 , 'b' ],
		d => [  300 , 'c' ],
	},
	700 => {
		a => [  100 , 'a' ],
	},
};

sub diag {
	print "# ", @_, $/;
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


# AU=	Autor - osoba
# CB=	Autor - korporacija
# CL=	Zbirka
# CP=	Mesto sast./dod. nazivu korp.
# PP=	Mesto izdanja
# PU=	Izdavač
# PY=	Godina izdanja
# P2=	Zaključna godina izdanja
# TI=	Naslov
# TO=	Naslov originala
# BN=	ISBN
# SN=	ISSN uz članak
# SP=	ISSN
# PN=	Predmetna odrednica - lično ime
# CS=	Predm. odred. - naziv korporacije
# DU=	Slobodno oblikovane predm. odred.
# SU=	Predmetne odrednice - sve
# AC=	Kod za vrstu autorstva
# CC=	Kod za vrstu sadržaja
# CO=	Zemlja/regija izdavanja
# FC=	Šifra organizacije
# LA=	Jezik teksta
# LC=	Kod za književni oblik
# LO=	Jezik izvornog dela
# TA=	Kod za predviđene korisnike
# TD=	Tipologija dok./dela
# UC=	UDK za pretraživanje
# KW=	Ključne reči

sub usemap {{
	7		=> 'BN',	# FIXME check
	8		=> 'SP',	# FIXME check
	4		=> 'TI',
	1003	=> 'AU',
	16		=> 'CU',
	21		=> 'SU',
#	12		=> '',
#	1007	=> '',
#	1016	=> '',

}};

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

#	my $url = 'http://cobiss.izum.si/scripts/cobiss?ukaz=GETID&lani=en';
	my $url = 'http://www.cobiss.ba/scripts/cobiss?ukaz=GETID&lani=en';

diag "get $url";

	my $mech = $self->{mech} || die "no mech?";

	my $hits;
	$mech->get( $url );

diag "got session";

	$mech->follow_link( text_regex => qr/union/ );

diag "switch to advanced form (select)";

	$mech->follow_link( url_regex => qr/mode=3/ );

diag "submit search $query";

	$mech->submit_form(
		fields => {
			'SS1' => $query,
		},
	);

	$hits = 0;
	if ( $mech->content =~ m{hits:\s*<b>\s*(\d+)\s*</b>}s ) {
		$self->{hits} = $hits = $1;
	} else {
		diag "get't find results in ", $mech->content;
		return;
	}

diag "got $hits results, get first one";

	$mech->follow_link( url_regex => qr/ukaz=DISP/ );

diag "in COMARC format";

	$mech->follow_link( url_regex => qr/fmt=13/ );

	return $hits;
}


sub next_marc {
	my ($self,$format) = @_;

	my $mech = $self->{mech} || die "no mech?";

	$format ||= 'unimarc';

	die "unknown format: $format" unless $format =~ m{(uni|us)marc};

	my $comarc;

	if ( $mech->content =~ m{<pre>\s*(.+?(\d+)\.\s+ID=(\d+).+?)\s*</pre>}s ) {

		my $markup = $1;
		my $nr = $2;
		my $id = $3;

diag "fetch $nr [$id] $format";

		$markup =~ s{</?b>}{}gs;
		$markup =~ s{<font[^>]*>}{<s>}gs;
		$markup =~ s{</font>}{<e>}gs;

		$markup =~ s/[\r\n]+\s{5}//gs; # join continuation lines

		$self->save_marc( "$id.xml", $markup );

		my $marc = MARC::Record->new;
		my $comarc = MARC::Record->new;

		foreach my $line ( split(/[\r\n]+/, $markup) ) {

			if ( $line !~ s{^(\d\d\d)([01 ])([01 ])}{} ) {
				diag "SKIP: $line";
			} else {
				$line .= "<eol>";

				my ( $f, $i1, $i2 ) = ( $1, $2, $3 );

				our $marc_map = undef;
				our $comarc_map = undef;
				our $ignored = undef;

				sub sf_parse {
					my ($f,$sf,$v) = @_;

					$v =~ s/\s+$//;

					push @{ $comarc_map->{ $f } }, ( $sf, $v );
					if ( my $m = $cobiss_marc21->{$f}->{$sf} ) {
						push @{ $marc_map->{ $m->[0] } }, ( $m->[1], $v );
					} else {
						$ignored->{$f}++;
					}
					return ''; # fix warning
				}
				my $l = $line;
				$l =~ s{<s>(\w)<e>([^<]+)}{sf_parse($f,$1, $2)}ges;

				diag "[$format] $line -> ",dump( $comarc_map, $marc_map ) if $comarc_map;

				foreach my $f ( keys %$comarc_map ) {
					$comarc->add_fields( $f, $i1, $i2, @{ $comarc_map->{$f} } );
				}

				foreach my $f ( keys %$marc_map ) {
					$marc->add_fields( $f, $i1, $i2, @{ $marc_map->{$f} } );
				}
			}
		}

		$self->save_marc( "$id.marc", $marc->as_usmarc );
		$self->save_marc( "$id.unimarc", $comarc->as_usmarc );
		diag $marc->as_formatted;

		if ( $nr < $self->{hits} ) {
			warn "# fetch next result";
			$nr++;
			$mech->follow_link( url_regex => qr/rec=$nr/ );
		} else {
			warn "# no more results";
		}

		return $id;
	} else {
		die "can't fetch COMARC format from ", $mech->content;
	}

}

1;
