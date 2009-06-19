package COBISS;

use warnings;
use strict;

use WWW::Mechanize;
use MARC::Record;

binmode STDOUT, ':utf8';

my $cobiss_marc21 = {
	'010' => { a => [ '020', 'a' ] },
	 200  => {
			a => [  245 , 'a' ],
			f => [  245 , 'f' ],
	},
	 205  => { a => [  250 , 'a' ] },
	 210  => {
		a => [  250 , 'a' ],
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
		$comarc =~ s{<font[^>]*>}{<s>}gs;
		$comarc =~ s{</font>}{<e>}gs;

		print $comarc;

		my $marc = MARC::Record->new;

		foreach my $line ( split(/[\r\n]+/, $comarc) ) {
			our @f;

			if ( $line !~ s{(\d\d\d)([01 ])([01 ])}{} ) {
				warn "SKIP: $line\n";
			} else {
				$line .= "<eol>";

				@f = ( $1, $2, $3 );
				sub sf { warn "sf",@_,"|",@f; push @f, @_; }
				$line =~ s{<s>(\w)<e>([^<]+)\s*}{sf($1, $2)}ges;
				warn "# f:", join(' ', @f), " left:|$line|\n";
				$marc->add_fields( @f );
			}
		}

		open(my $out, '>:utf8', 'out.marc');
		print $out $marc->as_usmarc;
		close($out);

		warn $marc->as_formatted;

		return $comarc;
	} else {
		die "can't fetch COMARC format from ", $mech->content;
	}

}

1;
