package Aleph;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;

use base 'Scraper';

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

# LCC - Klasifikacija Kongresne knjižnice 
# LCN - Signatura Kongresne knjižnice
# DDC - Deweyjeva klasifikacija 
# TIT - Naslovi 
# AUT - Autori 
# IMP - Impresum
# SUB - Predmetnice
# SRS - Nakladnička cjelina 
# LOC - Lokacija 
# WRD - Riječi 
# WTI - Riječi u polju naslova 
# WAU - Riječi u polju autora 
# WPE - Riječi u polju individualnog autora 
# WCO - Riječi u polju korporativnog autora 
# WME - Riječi u polju sastanka 
# WUT - Riječi u polju jedinstvenog naslova 
# WPL - Riječi u polju mjesta izdavanja 
# WPU - Riječi u polju nakladnika 
# WSU - Riječi u polju predmetnica 
# WSM - Riječi u predmetnicama MeSH-a 
# WST - Riječi u polju status
# WGA - Riječi u geografskim odrednicama 
# WYR - Godina izdavanja

sub usemap {{
	4		=> 'WTI',
	1003	=> 'WTI',
	16		=> 'CU',
	21		=> 'SU',
#	12		=> '',
#	1007	=> '',
#	1016	=> '',
}};


sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	my $url = 'http://161.53.240.197:8991/F?RN=' . rand(1000000000);
	# fake JavaScript code on page which creates random session

diag "get $url";

	my $mech = $self->{mech} || die "no mech?";
	$mech->get( $url );

diag "advanced search";

	$mech->follow_link( url_regex => qr/find-c/ );

diag "submit search $query";

	$mech->submit_form(
		fields => {
			'ccl_term' => $query,
		},
	);

	my $hits = 0;
	if ( $mech->content =~ m{ukupno\s+(\d+).*do\s+(\d+)}s ) {
		$hits = $1;
		$hits = $2 if $2 && $2 < $1; # correct for max. results
	} else {
		diag "get't find results in ", $mech->content;
		return;
	}

diag "got $hits results, get first one";

	$mech->follow_link( url_regex => qr/set_entry=000001/ );

diag "in MARC format";

	$mech->follow_link( url_regex => qr/format=001/ );

	return $hits;
}


sub next_marc {
	my ($self,$format) = @_;

	my $mech = $self->{mech} || die "no mech?";

print $mech->content;

	if ( $mech->content =~ m{Zapis\s+(\d+)}s ) {

		my $nr = $1;

diag "parse $nr";

		my $marc = MARC::Record->new;

		my $html = $mech->content;
		my $hash;

		sub field {
			my ( $f, $v ) = @_;
			$v =~ s/\Q&nbsp;\E/ /gs;
warn "# $f\t$v\n";
			$hash->{$f} = $v;
			my ($i1,$i2) = (' ',' ');
			($i1,$i2) = ($2,$3) if $f =~ s/^(...)(.)?(.)?/$1/;
			my @sf = split(/\|/, $v);
			shift @sf;
			@sf = map { s/^(\w)\s+//; { $1 => $_ } } @sf;
diag "sf = ", dump(@sf);
			$marc->add_fields( $f, $i1, $i2, @sf ) if $f =~ m/^\d+$/;
		}

		$html =~ s|<tr>\s*<td class=td1 id=bold[^>]*>(.+?)</td>\s*<td class=td1>(.+?)</td>|field($1,$2)|ges;
		diag dump($hash);

		my $id = $hash->{SYS} || die "no SYS";

		my $path = "marc/$id.$format";

		open(my $out, '>:utf8', $path);
		print $out $marc->as_usmarc;
		close($out);

		diag "created $path ", -s $path, " bytes";

#		diag $marc->as_formatted;

		$nr++;

		die if $nr == 3; # FIXME

		$mech->follow_link( url_regex => qr/set_entry=0*$nr/ );

		return $marc->as_usmarc;
	} else {
		die "can't fetch COMARC format from ", $mech->content;
	}

}

1;
