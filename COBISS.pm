package COBISS;

use warnings;
use strict;

use WWW::Mechanize;
use MARC::Record;
use Data::Dump qw/dump/;

binmode STDOUT, ':utf8';

sub new {
    my ( $class ) = @_;
    my $self = {};
    bless $self, $class;
    return $self;
}


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
# @attr 1=8 isbn-issn 
# @attr 1=7 isbn-issn 
# @attr 1=4 title 
# @attr 1=1003 author 
# @attr 1=16 dewey 
# @attr 1=21 subject-holding 
# @attr 1=12 control-no 
# @attr 1=1007 standard-id 
# @attr 1=1016 any

sub usemap {{
	8		=> 'BN',	# FIXME check
	7		=> 'SN',	# FIXME check
	4		=> 'TI',
	1003	=> 'TI',
	16		=> 'CU',
	21		=> 'SU',
#	12		=> '',
#	1007	=> '',
#	1016	=> '',

}};

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	my $url = 'http://cobiss.izum.si/scripts/cobiss?ukaz=GETID&lani=en';

diag "get $url";

	my $mech = $self->{mech} = WWW::Mechanize->new();
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
		$hits = $1;
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

		my $comarc = $1;
		my $nr = $2;
		my $id = $3;

diag "fetch_marc $nr [$id] $format";

		$comarc =~ s{</?b>}{}gs;
		$comarc =~ s{<font[^>]*>}{<s>}gs;
		$comarc =~ s{</font>}{<e>}gs;

		open(my $out, '>:utf8', "comarc/$id");
		print $out $comarc;
		close($out);

		print $comarc;

		my $marc = MARC::Record->new;

		foreach my $line ( split(/[\r\n]+/, $comarc) ) {

			if ( $line !~ s{^(\d\d\d)([01 ])([01 ])}{} ) {
				diag "SKIP: $line";
			} else {
				our @f = ( $1, $2, $3 );
				$line .= "<eol>";

				if ( $format eq 'unimarc' ) {

					diag dump(@f), "line: $line";
					sub sf_uni {
						warn "sf ",dump(@_);
						push @f, @_;
					}
					$line =~ s{<s>(\w)<e>([^<]+)\s*}{sf_uni($1, $2)}ges;
					diag "f:", dump(@f), " left: |$line|";
					$marc->add_fields( @f );

				} elsif ( $format eq 'usmarc' ) {

					my ( $f, $i1, $i2 ) = @f;

					our $out = {};

					sub sf_us {
						my ($f,$sf,$v) = @_;
						if ( my $m = $cobiss_marc21->{$f}->{$sf} ) {
							push @{ $out->{ $m->[0] } }, ( $m->[1], $v );
						}
						return;
					}
					$line =~ s{<s>(\w)<e>([^<]+)\s*}{sf_us($f,$1, $2)}ges;

					diag "converted marc21 ",dump( $out );

					foreach my $f ( keys %$out ) {
						$marc->add_fields( $f, $i1, $i2, @{ $out->{$f} } );
					}
				}
			}
		}

		my $path = "marc/$id.$format";

		open($out, '>:utf8', $path);
		print $out $marc->as_usmarc;
		close($out);

		diag "created $path ", -s $path, " bytes";

		diag $marc->as_formatted;

		$nr++;
		$mech->follow_link( url_regex => qr/rec=$nr/ );

		return $marc->as_usmarc;
	} else {
		die "can't fetch COMARC format from ", $mech->content;
	}

}

1;
