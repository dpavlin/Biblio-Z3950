package AlephTR;

use warnings;
use strict;

use MARC::Record;
use Data::Dump qw/dump/;

use base 'Scraper';

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
	4		=> 'WTI=',
	7		=> 'ISBN=',
	8		=> 'ISSN=',
	1003	=> 'AUT=',
	16		=> 'DDC=',
	21		=> 'SUB=',
	12		=> 'LCN=',
#	1007	=> '',
	1016	=> 'WRD=',
}};

our $session_id;

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	$session_id ||= int rand(1000000000);
	# FIXME allocate session just once
	my $url = 'http://mksun.mkutup.gov.tr/F?RN=' . $session_id . '&func=find-c-0';
	# fake JavaScript code on page which creates random session

diag "advanced search $url";

	my $mech = $self->{mech} || die "no mech?";
	$mech->get( $url );

diag "submit search [$query]";

	$mech->submit_form(
		fields => {
			'ccl_term' => $query,
		},
	);

	my $hits = 0;
	if ( $mech->content =~ m{Toplam\s+(\d+)} ) { # FIXME Many results in Crotian
		$hits = $1;
	} else {
		diag "get't find results in ", $mech->content;
		return;
	}

diag "got $hits results, get first one";

	$mech->follow_link( url_regex => qr/set_entry=000001/ );

diag "in MARC format";

	$mech->follow_link( url_regex => qr/format=001/ );

	return $self->{hits} = $hits;
}


our ( $hash, $marc );

sub next_marc {
	my ($self,$format) = @_;

	$format ||= 'marc';

	my $mech = $self->{mech} || die "no mech?";

#warn "## ", $mech->content;

	if ( $mech->content =~ m{kay.ttan\s+(\d+)}s ) {

		my $nr = $1;

warn "parse $nr";

		$marc = MARC::Record->new;
		$marc->encoding('utf-8');
		$hash = {};

		my $html = $mech->content;

#diag $html;

		sub field {
			my ( $f, $v ) = @_;
			$v =~ s/\Q&nbsp;\E/ /gs;
			$v =~ s/\s+$//gs;
warn "## $f\t[$v]\n";
			$hash->{$f} = $v;

			if ( $f eq 'LDR' ) {
				$marc->leader( $v );
				return;
			}

			if ( $f =~ m/\D/ ) {
				warn "$f not numeric!";
				return;
			}

			if ( $v !~ s/^\|// ) { # no subfields
				$marc->add_fields( $f, $v );
warn "## ++ ", dump( $f, $v );
				return;
			}

			my ($i1,$i2) = (' ',' ');
			($i1,$i2) = ($2,$3 || ' ') if $f =~ s/^(...)(.)(.)?/$1/;
			my @sf = split(/\|/, $v);
			@sf = map { s/^(\w)\s+//; { $1 => $_ } } @sf;
#warn "## sf = ", dump(@sf);
			$marc->add_fields( $f, $i1, $i2, @sf );
warn "## ++ ", dump( $f, $i1, $i2, @sf );
		}

		$html =~ s|<tr>\s*?<td[^>]*class=td1[^>]*>(.+?)</td>\s*?<td class=td1>(.+?)</td>\s*</tr>|field($1,$2)|ges;
		diag "# hash ",dump($hash);
		diag "# marc ", $marc->as_formatted;

		my $id = $hash->{SYS} || die "no SYS";

		$self->save_marc( "$id.marc", $marc->as_usmarc );

		if ( $nr < $self->{hits} ) {
			$nr++;
			diag "follow link to next record $nr";
			$mech->follow_link( url_regex => qr/set_entry=0*$nr/ );
		}

		return $id;
	} else {
		die "can't fetch " . __PACKAGE__ . " format from ", $mech->content;
	}

}

1;
