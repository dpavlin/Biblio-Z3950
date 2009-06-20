package COBISS;

use warnings;
use strict;

use WWW::Mechanize;
use MARC::Record;
use File::Slurp;

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

our $mech = WWW::Mechanize->new();
our $hits;

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

our $usemap = {
	8		=> 'BN',	# FIXME check
	7		=> 'SN',	# FIXME check
	4		=> 'TI',
	1003	=> 'TI',
	16		=> 'CU',
	21		=> 'SU',
#	12		=> '',
#	1007	=> '',
#	1016	=> '',

};

sub usemap {
	my $f = shift || die;
	$usemap->{$f};
}

sub search {
	my ( $self, $query ) = @_;

	die "need query" unless defined $query;

	my $url = 'http://cobiss.izum.si/scripts/cobiss?ukaz=GETID&lani=en';

diag "# get $url";

	$mech->get( $url );

diag "# got session";

	$mech->follow_link( text_regex => qr/union/ );

diag "# switch to advanced form (select)";

	$mech->follow_link( url_regex => qr/mode=3/ );

diag "# submit search $query";

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

diag "# got $hits results, get first one";

	$mech->follow_link( url_regex => qr/ukaz=DISP/ );

diag "# in COMARC format";

	$mech->follow_link( url_regex => qr/fmt=13/ );
}


sub fetch_marc {
	my ($self) = @_;

	my $comarc;

	if ( $mech->content =~ m{<pre>\s*(.+?(\d+\.)\s+ID=(\d+).+?)\s*</pre>}s ) {

		my $comarc = $1;
		my $nr = $2;
		my $id = $3;

diag "# fetch_marc $nr [$id]";

		$comarc =~ s{</?b>}{}gs;
		$comarc =~ s{<font[^>]*>}{<s>}gs;
		$comarc =~ s{</font>}{<e>}gs;

		write_file "comarc/$id", $comarc;

		print $comarc;

		my $marc = MARC::Record->new;

		foreach my $line ( split(/[\r\n]+/, $comarc) ) {
			our @f;

			if ( $line !~ s{^(\d\d\d)([01 ])([01 ])}{} ) {
				diag "SKIP: $line";
			} else {
				$line .= "<eol>";

				@f = ( $1, $2, $3 );
				sub sf { push @f, @_; }
				$line =~ s{<s>(\w)<e>([^<]+)\s*}{sf($1, $2)}ges;
				diag "# f:", join('|', @f), " left: |$line|";
				$marc->add_fields( @f );
			}
		}

		open(my $out, '>:utf8', "marc/$id");
		print $out $marc->as_usmarc;
		close($out);

		diag $marc->as_formatted;

		return $marc->as_usmarc;
	} else {
		die "can't fetch COMARC format from ", $mech->content;
	}

}

1;
