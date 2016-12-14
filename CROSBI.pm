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
	1007		=> 'pti_pr:',
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

	die "need query" unless defined $query;

	my $table = lc $self->{database};
	$table =~ s/^crosbi-//g;

	my $sql = qq{

select *
from $table
inner join rad_ustanova using (id)
left outer join rad_napomena using (id)
left outer join rad_projekt using (id)
left outer join rad_godina using (id)
left outer join rad_podrucje using (id)
left outer join url using (id)
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

	my $sth = $self->{_sth} || die "no _sth";

	my $row = $sth->fetchrow_hashref;

	die "no row" unless $row;

	my $id = $row->{id} || die "no id";

	my $marc = MARC::Record->new;
	$marc->encoding('UTF-8');

	my $leader = $marc->leader;

# /srv/webpac2/conf/crosbi/2016-12-12/casopis-dbi2marc.pl

## LDR 05 - n - new
## LDR 06 - a - language material 
## LDR 07 - a - monographic component part 

	$leader =~ s/^(....)...(.+)/$1naa$2/;

## LDR 17 - Encoding level ; 7 - minimal level, u - unknown
## LDR 18 - i = isbd ; u = unknown

	$leader =~ s/^(.{17})..(.+)/$1uu$2/;

	$marc->leader( $leader );
	warn "# leader [$leader]";


### 008 - All materials

## 008 - 00-05 - Date entered on file 

	my $f008 = $1 . $2 . $3 if $row->{time_date} =~ m/\d\d(\d\d)-(\d\d)-(\d\d)/;

## 008 06 - Type of date/Publication status

	$f008 .= 's';

## 008 07-10 - Date 1

 	$f008 .= substr($row->{datum},0,4);

## 008 11-14 - Date 2 

	#$f008 .= '    ';

	$f008 .= ' ' x ( 15 - length($f008) ); # pad to 15 position
## 008 15-17 - Place of publication, production, or execution - ako nema 102, popunjava se s |
	$f008 .= 'xx ';

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

	$marc->add_fields(300,' ',' ',
		a => page_range('',$row->{stranica_prva},$row->{stranica_zadnja}),
		f => 'str.'
	);

	$marc->add_fields(363,' ',' ',
		a => $row->{volumen},
		b => $row->{broj},
		i => $row->{godina},
	);

# /data/FF/crosbi/2016-12-12/casopis-rad_napomena.sql

	$marc->add_fields(500,' ',' ',
		a => substr($row->{napomena}, 0, 9999), # XXX marc limit for one subfield is 4 digits in dictionary
	);

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

	$marc->add_fields(690,' ',' ',
		a => $row->{sifra}
	);


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

	$marc->add_fields(773,'0',' ',
		t => $row->{casopis},
		x => $row->{issn},
		g => "$row->{volumen} ($row->{godina}), $row->{broj} ;" . page_range(' str. ',$row->{stranica_prva}, $row->{stranica_zadnja}),
	);

	if ( my $file = $row->{datoteka} ) {
		$marc->add_fields(856,' ',' ',
			u => "http://bib.irb.hr/datoteka/$file",
		);
	};

	foreach my $name (qw( openurl url )) {
		next if ! $row->{$name};
		$marc->add_fields(856,' ',' ',
			u => $row->{$name},
		);
	}

	my @f942 = (
		c => 'CLA'
	);
	if ( $row->{status_rada} ) {
		push @f942, (
		f => 1,
		g => $row->{status_rada}
		);
	}
	push @f942, t => '1.01' if $row->{kategorija} =~ m/Znanstveni/;
	push @f942, t => '1.04' if $row->{kategorija} =~ m/Strucni/;

	$marc->add_fields(942,' ',' ',
		@f942,
		u => '1',
		z => join(' - ', $row->{kategorija}, $row->{vrsta_rada}),
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
