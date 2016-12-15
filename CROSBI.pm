package CROSBI;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;
use DBI;
use utf8;

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
# @attr 1=16 dewey (godina)
# @attr 1=21 subject-holding 
# @attr 1=12 control-no 
# @attr 1=1007 standard-id 
# @attr 1=1016 any

sub usemap {{
	4		=> 'fti_pr:',
	7		=> 'fti_pr:',
	8		=> 'fti_pr:',
	1003		=> 'fti_au:',
	16		=> 'fti_pr:',
	21		=> 'fti_pr:',
	12		=> 'fti_pr:',
	1007		=> 'fti_pr:',
	1016		=> 'fti_au,fti_pr:',
}};

=for sql

=cut

my $dbname = 'bibliografija';
my @and;
my @exec;

sub search {
	my ( $self, $query ) = @_;

	utf8::decode( $query );
	warn "QUERY",dump( $query );

	die "ERROR need query" unless defined $query;

	$query =~ s/^\s+//;
	$query =~ s/\s+$//;

	my $table = lc $self->{database};
	$table =~ s/^crosbi-//g;

	$self->{_table} = $table;

	my $sql = qq{

select
	$table.*
	,ARRAY( select napomena from rad_napomena where rad_napomena.id = $table.id ) as rad_napomena
	,ARRAY( select projekt from rad_projekt where rad_projekt.id = $table.id ) as rad_projekt
	,ARRAY( select datum from rad_godina where rad_godina.id = $table.id ) as rad_godina
	,ARRAY( select sifra from rad_podrucje where rad_podrucje.id = $table.id ) as rad_podrucje
	,ARRAY( select url from url where url.id = $table.id ) as url
from $table
inner join rad_ustanova using (id) -- sifra
	};

	@and = ( qq{ rad_ustanova.sifra = ? } );
	@exec =  ( 130 ); # FIXME ustanova

		sub parse_fti {
			my $query = shift;
			warn "## parse_fti [$query]";
			my $fti;
			if ( $query =~ s/^(fti_.+):// ) {
				$fti = $1;
			} else {
				warn "INVALID QUERY no fti_xxx: [$query]";
			}

			my $tsquery = join(' & ', split(/\s+/,$query) );

			my @or;
			foreach my $f ( split(/,/,$fti) ) {
				push @or, "$f @@ to_tsquery(?)";
				push @exec, $tsquery;
			};
			push @and, "( " . join(" or ", @or) . ")";
		}

	if ( $query =~ / AND / ) {
		foreach my $and ( split(/ AND /, $query) ) {
			parse_fti $and;
		}
	} elsif ( $query =~ m/fti_.+:/ ) {
		parse_fti $query;
	} else { # no " AND " in query
		my $tsquery = join(' & ', split(/\s+/,$query) );
		push @and, "( fti_au @@ to_tsquery(?) or fti_pr @@ to_tsquery(?) )";
		push @exec, $tsquery,  $tsquery;
	}


	$sql .= "where " . join(" and ", @and);

warn "XXX SQL = ",$sql, dump( @exec );

	my $dbh = DBI->connect_cached("dbi:Pg:dbname=$dbname", '', '', {AutoCommit => 0});

	my $sth = $dbh->prepare( $sql );

	$sth->execute( @exec );

	my $hits = $sth->rows;

	$self->{_sth} = $sth;

	warn "# [$query] $hits hits\n";

	return $self->{hits} = $hits;
}

my $langrecode008 = {
        'bugarski' => 'bul',
	'Češki' => 'cze',
	'češki' => 'cze',
        'ENG' => 'eng',
        'Esperanto' => 'epo',
        'FRA' => 'fra',
        'GER' => 'ger',
        'HRV' => 'hrv',
        'ITA' => 'ita',
	'Japanski' => 'jpn',
        'Latinski' => 'lat',
        'mađarski' => 'hun',
	'Madžarski' => 'hun',
        'Makedonski' => 'mac',
        'nizozemski' => 'dut',
        'Poljski' => 'pol',
        'poljski' => 'pol',
        'Portugalski' => 'por',
        'portugalski' => 'por',
        'RUS' => 'rus',
        'Rumunjski' => 'rum',
        'rumunjski' => 'rum',
        'rusinski' => 'sla',
        'slovački' => 'slo',
	'slovenski' => 'slv',
        'SLV' => 'slv',
        'SPA' => 'spa',
        'Srpski' => 'srp',
        'srpski' => 'srp',
        'Turski' => 'tur',
        'turski' => 'tur',
        'ukrajinski' => 'ukr',
        'HRV-ENG' => 'mul',
        'HRV-GER' => 'mul',
	'hrvatsko-francuski' => 'mul',
} ;

sub next_marc {
	my ($self,$format) = @_;

	$format ||= 'marc';

	my $sth = $self->{_sth} || die "ERROR no _sth";
	my $row = $sth->fetchrow_hashref;

	warn "## row = ",dump($row) if $ENV{DEBUG};

	warn "ERROR: no row" unless $row;

	my $id = $row->{id} || die "ERROR no id";

	my $marc = MARC::Record->new;
	$marc->encoding('UTF-8');

	my $leader = $marc->leader;

# /srv/webpac2/conf/crosbi/2016-12-12/casopis-dbi2marc.pl

## LDR 05 - n - new
## LDR 06 - a - language material 
## LDR 07 - a - monographic component part 

	$leader =~ s/^(.....)...(.+)/$1naa$2/;

## LDR 17 - Encoding level ; 7 - minimal level, u - unknown
## LDR 18 - i = isbd ; u = unknown

	$leader =~ s/^(.{17})..(.+)/$1ui$2/;

	$marc->leader( $leader );
	warn "# leader [$leader]";


### 008 - All materials

## 008 - 00-05 - Date entered on file 

	my $f008 = $1 . $2 . $3 if $row->{time_date} =~ m/\d\d(\d\d)-(\d\d)-(\d\d)/;

## 008 06 - Type of date/Publication status

	$f008 .= 's';

## 008 07-10 - Date 1

 	$f008 .= substr( $row->{rad_godina}->[0] ,0,4);

## 008 11-14 - Date 2 

	#$f008 .= '    ';

	$f008 .= ' ' x ( 15 - length($f008) ); # pad to 15 position
## 008 15-17 - Place of publication, production, or execution - ako nema 102, popunjava se s |
	$f008 .= 'xx ';

## 008 29 - Conference publication
	$f008 .= ' ' x ( 29 - length($f008) );
	$f008 .= $self->{_table} eq 'zbornik' ? '1' : '0';

## 008 35-37 - Language
	$f008 .= ' ' x ( 35 - length($f008) ); # pad to 35 position
	if ( my $lng = $langrecode008->{ $row->{jezik} } ) {
		$f008 .= $lng;
	} else {
		warn "INFO unknown jezik [$row->{jezik}] insert into langrecode008!";
		#$f008 .= '   ';
	}
	$f008 .= ' ' x ( 38 - length($f008) );
## 008 38 - Modified record
	$f008 .= '|';
## 008 39 - Cataloging source - d (other)
	$f008 .= 'd';

	warn "# 008 ",length($f008);
	
	$marc->add_fields('008', $f008); # FIXME - mglavica check


	if ( my $doi = $row->{doi} ) {

		$marc->add_fields('024','7',' ',
			2 => 'doi',
			a => $doi,
		);

	}

### 035$

## marc 035a - System Number 
## polje moze  sadrzavati slova i razmake
## moguc problem u pretrazivanju ako ima zagrade, kako bi trebalo po standardu

	$marc->add_fields('035',' ',' ',
		a => join('', '(CROSBI)', $row->{id})
	);

### 040
## za sve je isti

	$marc->add_fields('040',' ',' ',
		'a' => 'HR-ZaFF',
		'b' => 'hrv',
		'c' => 'HR-ZaFF',
		'e' => 'ppiak'
	);

### 041 - indikatori
# i1=0 - Item not a translation/does not include a translation
# i1=1 - Item is or includes a translation
# i1=' ' - No information provided

### 041
# ponovljivo potpolje (041a) - marc_repeatable_subfield
# koristi se kad ima vise od jednog jezika, ili kad se radi o prijevodu

	$marc->add_fields('041',' ',' ', map {
		( a => lc($_) )
	} split(/-/, $row->{jezik}));


### 080
### 245 indikatori
## i1 = 0 zza anonimne publikacije, i1 = 1 ako postoji 700 ili 710
## i2 = pretpostavlja se na temelju clana na pocetku naslova i jezika

	my ( $first_author, $authors ) = split(/ ;\s*/,$row->{autori});

	$marc->add_fields(100,'1',' ','a' => $first_author );



	my $naslov = $row->{naslov}; # XXX title?

	my $i2 =
		$naslov =~ m/^Eine /				? 5 :
		$naslov =~ m/(Die|Das|Der|Ein|Les|Los|The) /	? 4 :
		$naslov =~ m/^(Um|Un|An|La|Le|Lo|Il) /		? 3 :
		$naslov =~ m/^(A|L) /				? 2 :
		$naslov =~ m/^L'/				? 2 :
								  0;

	$marc->add_fields(245,'1',$i2,
		'a' => $naslov . ' /',
		'c' => $row->{autori} . '.',
	);

	$marc->add_fields(246,'3',' ',
		'i' => 'Naslov na engleskom:',
		'a' => $row->{title}
	);

	sub page_range {
		my ( $prefix, $from, $to ) = @_;
		my $out;
		if ( $from ) {
			$out = $prefix . $from;
			$out .= '-' . $to if $to;
		}
		return $out;
	}

	# fake date for Koha import
	$marc->add_fields(260,' ',' ',
		c => $row->{godina},
	);

	$marc->add_fields(300,' ',' ',
		a => page_range('',$row->{stranica_prva},$row->{stranica_zadnja}),
		f => 'str.'
	);

	$marc->add_fields(363,' ',' ',
		a => $row->{volumen},
		b => $row->{broj},
		i => $row->{godina},
	) if $row->{volumen};

# /data/FF/crosbi/2016-12-12/casopis-rad_napomena.sql

	foreach my $napomena ( @{ $row->{rad_napomena} } ) {
		$marc->add_fields(500,' ',' ',
			a => substr($napomena, 0, 9999), # XXX marc limit for one subfield is 4 digits in dictionary
		);
	}

	$marc->add_fields(520,' ',' ',
		a => substr($row->{sazetak}, 0, 9999)
	);


	if ( $row->{rad_projekt} ) {
		$marc->add_fields(536,' ',' ',
			a => 'Projekt MZOS',
			f => 'projekt',
		);
	}

	$marc->add_fields(546,' ',' ',
		a => $row->{jezik}
	);

	foreach my $v ( @{ $row->{rad_podrucje} } ) {
		$marc->add_fields(690,' ',' ',
			a => $v,
		);
	}


	$marc->add_fields(693,' ',' ',
		a => $row->{kljucne_rijeci},
		1 => 'hrv',
		2 => 'crosbi',
	);
	$marc->add_fields(693,' ',' ',
		a => $row->{key_words},
		1 => 'eng',
		2 => 'crosbi',
	);

	if ( $row->{autori} =~ m/ ; / ) {
		my @a = split(/ ; /, $row->{autori});
		shift @a; # skip first
		$marc->add_fields(700,'1',' ',
			a => $_,
			4 => 'aut'
		) foreach @a;
	}

	sub combine {
		my $out = '';
		my $last_delimiter = '';
		while(@_) {
			my $value = shift @_;
			my $delimiter = shift @_;
			my ( $before,$after ) = ( '', '' );
			( $before, $value, $after ) = @$value if ( ref $value eq 'ARRAY' );
			$out .= $last_delimiter . $value if $value;
			$last_delimiter = $delimiter || last;
		}
		warn "### [$out]";
		return $out;
	}
			

	if ( $self->{_table} =~ m/(casopis|preprint)/ ) {

	$marc->add_fields(773,'0',' ',
		t => $row->{casopis},
		x => $row->{issn},
#		g => "$row->{volumen} ($row->{godina}), $row->{broj} ;" . page_range(' str. ',$row->{stranica_prva}, $row->{stranica_zadnja}),
		g => combine( $row->{volumen}, ' ', [ '(', $row->{godina}, ')' ], ', ', $row->{broj}, ' ;', page_range(' str. ',$row->{stranica_prva}, $row->{stranica_zadnja}) ),
	);

	} elsif ( $self->{_table} =~ m/rknjiga/ ) {

	# rknjiga-dbi2marc.pl
	$marc->add_fields(773,'0',' ',
		t => $row->{knjiga},
#		d => "$row->{grad} : $row->{nakladnik}, $row->{godina}",
		d => combine( $row->{grad}, ' : ', $row->{nakladnik}, ', ', $row->{godina} ),
		k => $row->{serija},
		h => $row->{ukupno_stranica},
		n => $row->{uredink},
		z => $row->{isbn},
		g => page_range('str. ',$row->{stranica_prva}, $row->{stranica_zadnja}),
	);

	} elsif ( $self->{_table} =~ m/zbornik/ ) {

	# zbornik-dbi2marc.pl
	$marc->add_fields(773,'0',' ',
		t => $row->{skup},
#		d => "$row->{grad} : $row->{nakladnik}, $row->{godina}",
		d => combine( $row->{grad}, ' : ', $row->{nakladnik}, ', ', $row->{godina} ),
		k => $row->{serija},
		h => $row->{ukupno_stranica},
		n => $row->{uredink},
		z => $row->{isbn},
		g => page_range('str. ',$row->{stranica_prva}, $row->{stranica_zadnja}),
	);

	} else {
		die "ERROR: 773 undefined in row ",dump($row);
	}


	if ( my $file = $row->{datoteka} ) {
		$marc->add_fields(856,' ',' ',
			u => "http://bib.irb.hr/datoteka/$file",
		);
	};


	$marc->add_fields(856,' ',' ',
		u => $row->{openurl},
	) if $row->{openurl};

	foreach my $url ( @{ $row->{url} } ) {
		$marc->add_fields(856,' ',' ',
			u => $url,
		);
	}

	my $f942c = {
		casopis  => 'CLA',
		preprint => 'PRE',
		rknjiga  => 'POG',
		zbornik  => 'RZB',
	};

	my @f942 = (
		c => $f942c->{ $self->{_table} } || die "ERROR no table $self->{_table} in ".dump($f942c),
	);

	if ( $row->{status_rada} ) {
		push @f942, (
		f => 1,
		g => $row->{status_rada}
		);
	}

	if ( $self->{_table} =~ m/(casopis|preprint)/ ) {

		if ( $row->{kategorija} =~ m/Znanstveni/ ) {
			push @f942, t => '1.01'
		} elsif ( $row->{kategorija} =~ m/Strucni/ ) {
			push @f942, t => '1.04';
		} else {
			warn "ERROR kategorija $row->{kategorija}";
		}

	} elsif ( $self->{_table} =~ m/rknjiga/ ) {

		if ( $row->{kategorija} =~ m/Znanstveni/ ) {
			push @f942, t => '1.16.1';
		} elsif ( $row->{kategorija} =~ m/Pregledni/ ) {
			push @f942, t => '1.16.2';
		} elsif ( $row->{kategorija} =~ m/Strucni/ ) {
			push @f942, t => '1.17';
		} else {
			warn "ERROR kategorija $row->{kategorija}";
		}

	} elsif ( $self->{_table} =~ m/zbornik/ ) {

		push @f942, v => $row->{vrst_recenzije};

	} else {
		die "ERROR _table $self->{_table}";
	}

	$marc->add_fields(942,' ',' ',
		@f942,
		u => '1',
		z => join(' - ', grep { defined $_ } ($row->{kategorija}, $row->{vrst_sudjelovanja}, $row->{vrsta_rada})),
	);

=for later
	$marc->add_fields(999,' ',' ',
		a => $row->{}
	);

=cut

#	diag "# hash ",dump($hash);
	diag "# marc\n", $marc->as_formatted if $ENV{DEBUG};

	$self->save_marc( "$id.marc", $marc->as_usmarc );

	return $id;

}

1;
