package CROSBI;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;
use DBI;

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
	4		=> '',
	7		=> '',
	8		=> '',
	1003	=> '',
#	16		=> '',
	21		=> '',
	12		=> '',
#	1007	=> '',
	1016	=> '',
}};

=for sql

=cut

my $dbname = 'bibliografija';

my $dbh = DBI->connect("dbi:Pg:dbname=$dbname", '', '', {AutoCommit => 0});

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	my $tsquery = join(' & ', split(/\s+/,$query) );

	my $sql = qq{

select *
from casopis
inner join rad_ustanova using (id)
left outer join rad_napomena using (id)
left outer join rad_projekt using (id)
where sifra = ? and (
	   fti_au @@ to_tsquery(?)
	or fti_pr @@ to_tsquery(?)
)

	};

	my $sth = $dbh->prepare( $sql );

warn "XXX SQL = ",$sql;

#-- and naslov like ?

	$sth->execute(
		130, # FIXME ustanova
		$tsquery,
		$tsquery,
#		, '%' . $query . '%'
	);

	$self->{_sth} = $sth;
	my $hits = $sth->rows;

	warn "# [$tsquery] $hits hits\n";

	return $self->{hits} = $hits;
}


sub next_marc {
	my ($self,$format) = @_;

	$format ||= 'marc';

	my $sth = $self->{_sth} || die "no _sth";

	my $row = $sth->fetchrow_hashref;

	die "no row" unless $row;

	my $id = $row->{id} || die "no id";

	my $marc = MARC::Record->new;
	$marc->encoding('utf-8');

	my $leader = $marc->leader;

	warn "# leader [$leader]";
	#$leader =~ s/^(....).../$1na$biblevel/;
	$marc->leader( $leader );

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

# /srv/webpac2/conf/crosbi/2016-12-12/casopis-dbi2marc.pl

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

	$marc->add_fields(300,' ',' ',
		a => join(' ', $row->{stranica_prva}, $row->{stranica_zadnja}),
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

=for later
	$marc->add_fields(999,' ',' ',
		a => $row->{}
	);

=cut

#	diag "# hash ",dump($hash);
	diag "# marc\n", $marc->as_formatted;

	$self->save_marc( "$id.marc", $marc->as_usmarc );

	return $id;

}

1;
