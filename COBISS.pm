package COBISS;

use warnings;
use strict;

use WWW::Mechanize;

sub search {

	my $url = 'http://cobiss.izum.si/scripts/cobiss?ukaz=GETID&lani=en';

warn "# get $url\n";

	my $mech = WWW::Mechanize->new();
	$mech->get( $url );

warn "# got session\n";

	$mech->follow_link( text_regex => qr/union/ );

warn "# submit search\n";

	$mech->submit_form(
		fields => {
			'SS1' => 'Krleza',
		},
	);

	my $hits = 1;
	if ( $mech->content =~ m{hits:\s*<b>\s*(\d+)\s*</b>}s ) {
		$hits = $1;
	} else {
		warn "get't find results in ", $mech->content;
	}

warn "# got $hits results, get first one\n";

	$mech->follow_link( url_regex => qr/ukaz=DISP/ );

warn "# in COMARC format\n";

	$mech->follow_link( url_regex => qr/fmt=13/ );

	my $comarc;

	if ( $mech->content =~ m{<pre>\s*(.+1\..+?)\s*</pre>}s ) {
		my $comarc = $1;
		$comarc =~ s{</?b>}{}gs;
		$comarc =~ s{<(/?font)[^>]*>}{<sf>}gs;

		print $comarc;

		return $comarc;
	} else {
		die "can't fetch COMARC format from ", $mech->content;
	}

}

1;
