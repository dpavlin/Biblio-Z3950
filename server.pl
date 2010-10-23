#!/usr/bin/perl

use warnings;
use strict;

use Net::Z3950::SimpleServer;
use Net::Z3950::OID;
use Data::Dumper;
use COBISS;
use Aleph;

my $databases = {
	'COBISS' => 'COBISS',
	'NSK01'  => 'Aleph',
	'NSK10'  => 'Aleph',
	'ZAG01'  => 'Aleph',
};

my $max_records = 3; # XXX configure this
my $max_result_sets = 10;

sub diag {
	print "# ", @_, $/;
}

sub InitHandle {
    my $this    = shift;
    my $session = {};

    $this->{HANDLE}   = $session;
    $this->{IMP_NAME} = "Biblio Z39.50";
    $this->{IMP_VER}  = "0.2";
    $session->{SETS}  = {};
}

sub SearchHandle {
    my $this    = shift;

diag "SearchHandle ",Dumper($this);

    my $session = $this->{HANDLE};
    my $rpn     = $this->{RPN};
    my $query;

	my $database = uc $this->{DATABASES}->[0];
	my $module = $databases->{$database};
	if ( ! defined $module ) {
        $this->{ERR_CODE} = 108;
		warn $this->{ERR_STR} = "$database NOT FOUND in available databases: " . join(" ", keys %$databases);
		return;
	}

	my $from = $module->new( $database );

diag "using $module for $database ", Dumper( $from );

	eval { $query = $rpn->{query}->render( $from->usemap ); };
	warn "ERROR: $@" if $@;
    if ( $@ && ref($@) ) {    ## Did someone/something report any errors?
        $this->{ERR_CODE} = $@->{errcode};
        $this->{ERR_STR}  = $@->{errstr};
        return;
    }

diag "search for $query";

    my $setname  = $this->{SETNAME};
    my $repl_set = $this->{REPL_SET};
diag "SETNAME $setname REPL_SET $repl_set";
    my $hits;
    unless ( $hits = $from->search( $query ) ) {
		warn $this->{ERR_STR} = "no results for $query";
        $this->{ERR_CODE} = 108;
        return;
    }
diag "got $hits hits";
    my $rs   = {
        lower => 1,
        upper => $hits < $max_records ? $max_records : $hits,
        hits  => $hits,
		from => $from,
		results => [ undef ], # we don't use 0 element
		database => $database,
    };
    my $sets = $session->{SETS};

    if ( defined( $sets->{$setname} ) && !$repl_set ) {
        $this->{ERR_CODE} = 21;
        return;
    }
    if ( scalar keys %$sets >= $max_result_sets ) {
        $this->{ERR_CODE} = 112;
        $this->{ERR_STR}  = "Max number is $max_result_sets";
        return;
    }
    $sets->{$setname} = $rs;
    $this->{HITS} = $session->{HITS} = $hits;
    $session->{QUERY} = $query;
}

sub FetchHandle {
    my $this     = shift;
    my $session  = $this->{HANDLE};
    my $setname  = $this->{SETNAME};
    my $req_form = $this->{REQ_FORM};
    my $offset   = $this->{OFFSET};
    my $sets     = $session->{SETS};
    my $hits     = $session->{HITS};
    my $rs;
    my $record;

    if ( !defined( $rs = $sets->{$setname} ) ) {
        $this->{ERR_CODE} = 30;
        return;
    }
    if ( $offset > $hits ) {
        $this->{ERR_CODE} = 13;
        return;
    }

    $this->{BASENAME} = "HtmlZ3950";

	my $format =
		$req_form eq Net::Z3950::OID::xml()     ? 'xml' :
		$req_form eq Net::Z3950::OID::unimarc() ? 'unimarc' :
		$req_form eq Net::Z3950::OID::usmarc()  ? 'marc' : # XXX usmarc -> marc
		undef;

	if ( ! $format ) {
		warn "ERROR: $req_form format not supported";
        $this->{ERR_CODE} = 239; ## Unsupported record format
        $this->{ERR_STR}  = $req_form;
        return;
	}

	$this->{REP_FORM} = $req_form;

	my $from = $rs->{from} || die "no from?";
	# fetch records up to offset
	while(  $#{ $rs->{results} } < $offset ) {
		push @{ $rs->{results} }, $from->next_marc;
		warn "# rs result ", $#{ $rs->{results} },"\n";
	}

	my $id = $rs->{results}->[$offset] || die "no id for record $offset in ",Dumper( $rs->{results} );

	my $path = 'marc/' . $rs->{database} . "/$id.$format";
	if ( ! -e $path ) {
		warn "ERROR: $path not found";
		## Unsupported record format
        $this->{ERR_CODE} = 239;
        $this->{ERR_STR}  = $req_form;
        return;
    }

	{
		open(my $in, '<', $path) || die "$path: $!";
		local $/ = undef;
		my $marc = <$in>;
		close($in);
		$this->{RECORD} = $marc;
	}


    if ( $offset == $hits ) {
        $this->{LAST} = 1;
    }
    else {
        $this->{LAST} = 0;
    }
}

sub CloseHandle {
    my $this = shift;
}

my $z = new Net::Z3950::SimpleServer(
    INIT   => \&InitHandle,
    SEARCH => \&SearchHandle,
    FETCH  => \&FetchHandle,
    CLOSE  => \&CloseHandle
);
$z->launch_server( $0, @ARGV );

package Net::Z3950::RPN::And;

sub render {
	my ($this,$usemap) = @_;
    my $this = shift;
    return $this->[0]->render() . ' AND ' . $this->[1]->render();
}

package Net::Z3950::RPN::Or;

sub render {
    my $this = shift;
    return $this->[0]->render() . ' OR ' . $this->[1]->render();
}

package Net::Z3950::RPN::AndNot;

sub render {
    my $this = shift;
    return $this->[0]->render() . ' AND NOT ' . $this->[1]->render();
}

package Net::Z3950::RPN::Term;

use Data::Dump qw(dump);
use COBISS;

sub render {
	my ($this,$usemap) = @_;

	die "no usemap" unless $usemap;

warn "# render ", dump($this);
warn "# usemap ", dump($usemap);

    my $attributes = {};
    my $prefix     = "";
    foreach my $attr ( @{ $this->{attributes} } ) {
        my $type  = $attr->{attributeType};
        my $value = $attr->{attributeValue};
        $attributes->{$type} = $value;
    }
    if ( defined( my $use = $attributes->{1} ) ) {
        if ( defined( my $field = $usemap->{$use} ) ) {
            $prefix = $field;
        }
        else {
			warn "FIXME add $use in usemap  ",dump( $usemap );
            die { errcode => 114, errstr => $use }; ## Unsupported use attribute
        }
    }
    if ( defined( my $rel = $attributes->{2} ) )
    {    ## No relation attributes supported
        if ( $rel != 3 ) {
            die { errcode => 117, errstr => $rel };
        }
    }
    if ( defined( my $pos = $attributes->{3} ) )
    {    ## No position attributes either
        if ( $pos != 3 ) {
            die { errcode => 119, errstr => $pos };
        }
    }
    if ( defined( my $struc = $attributes->{4} ) ) {    ## No structure
        if ( ( $struc != 1 ) && ( $struc != 2 ) ) {
            die { errcode => 118, errstr => $struc };
        }
    }
    if ( defined( $attributes->{5} ) ) {                ## No truncation
        die { errcode => 113, errstr => 5 };
    }
    my $comp = $attributes->{6};
    if ($prefix) {
        if ( defined($comp) && ( $comp >= 2 ) ) {
            $prefix = "all$prefix= ";
        }
        else {
            $prefix = "$prefix=";
        }
    }

    my $q = $prefix . $this->{term};
	print "# q: $q\n";
	return $q;
}

