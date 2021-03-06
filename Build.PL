use Module::Build;

use warnings;
use strict;

my $build = Module::Build->new(
	module_name => 'Biblio::Z39.50',
	dist_version => '0.00',
	license     => 'perl',
	requires    => {
		'WWW::Mechanize' => '1.23',
		'MARC::Record' => '2.00',
		'Net::Z3950::SimpleServer',
	},
);

$build->create_build_script;
