use Module::Build;

use warnings;
use strict;

my $build = Module::Build->new(
	module_name => 'Z3950::HTML::Scraper',
	dist_version => '0.00',
	license     => 'perl',
	requires    => {
		'WWW::Mechanize' => '1.23',
		'MARC::Record' => '2.00',
	},
);

$build->create_build_script;
