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
    my $self    = shift;
    my $session = {};

    $self->{HANDLE}   = $session;
    $self->{IMP_NAME} = "Biblio Z39.50";
    $self->{IMP_VER}  = "0.2";
    $session->{SETS}  = {};
}

sub SearchHandle {
    my $self    = shift;

diag "SearchHandle ",Dumper($self);

    my $session = $self->{HANDLE};
    my $rpn     = $self->{RPN};
    my $query;

	my $database = uc $self->{DATABASES}->[0];
	my $module = $databases->{$database};
	if ( ! defined $module ) {
        $self->{ERR_CODE} = 108;
		warn $self->{ERR_STR} = "$database NOT FOUND in available databases: " . join(" ", keys %$databases);
		return;
	}

	my $from = $module->new( $database );

diag "using $module for $database ", Dumper( $from );

	eval { $query = $rpn->{query}->render( $from->usemap ); };
	warn "ERROR: $@" if $@;
    if ( $@ && ref($@) ) {    ## Did someone/something report any errors?
        $self->{ERR_CODE} = $@->{errcode};
        $self->{ERR_STR}  = $@->{errstr};
        return;
    }

diag "search for $query";

    my $setname  = $self->{SETNAME};
    my $repl_set = $self->{REPL_SET};
diag "SETNAME $setname REPL_SET $repl_set";
    my $hits;
    unless ( $hits = $from->search( $query ) ) {
		warn $self->{ERR_STR} = "no results for $query";
        $self->{ERR_CODE} = 108;
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
        $self->{ERR_CODE} = 21;
        return;
    }
    if ( scalar keys %$sets >= $max_result_sets ) {
        $self->{ERR_CODE} = 112;
        $self->{ERR_STR}  = "Max number is $max_result_sets";
        return;
    }
    $sets->{$setname} = $rs;
    $self->{HITS} = $session->{HITS} = $hits;
    $session->{QUERY} = $query;
}

sub FetchHandle {
    my $self     = shift;
    my $session  = $self->{HANDLE};
    my $setname  = $self->{SETNAME};
    my $req_form = $self->{REQ_FORM};
    my $offset   = $self->{OFFSET};
    my $sets     = $session->{SETS};
    my $hits     = $session->{HITS};
    my $rs;
    my $record;

    if ( !defined( $rs = $sets->{$setname} ) ) {
        $self->{ERR_CODE} = 30;
        return;
    }
    if ( $offset > $hits ) {
        $self->{ERR_CODE} = 13;
        return;
    }

    $self->{BASENAME} = $rs->{database};

	my $format =
		$req_form eq Net::Z3950::OID::xml()     ? 'xml' :
		$req_form eq Net::Z3950::OID::unimarc() ? 'unimarc' :
		$req_form eq Net::Z3950::OID::usmarc()  ? 'marc' : # XXX usmarc -> marc
		undef;

	if ( ! $format ) {
		warn "ERROR: $req_form format not supported";
        $self->{ERR_CODE} = 239; ## Unsupported record format
        $self->{ERR_STR}  = $req_form;
        return;
	}

	$self->{REP_FORM} = $req_form;

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
        $self->{ERR_CODE} = 239;
        $self->{ERR_STR}  = $req_form;
        return;
    }

	{
		open(my $in, '<', $path) || die "$path: $!";
		local $/ = undef;
		my $marc = <$in>;
		close($in);
		$self->{RECORD} = $marc;
	}


    if ( $offset == $hits ) {
        $self->{LAST} = 1;
    }
    else {
        $self->{LAST} = 0;
    }
}

sub CloseHandle {
    my $self = shift;
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
	my ($self,$usemap) = @_;
    return $self->[0]->render($usemap) . ' AND ' . $self->[1]->render($usemap);
}

package Net::Z3950::RPN::Or;

sub render {
	my ($self,$usemap) = @_;
    return $self->[0]->render($usemap) . ' OR ' . $self->[1]->render($usemap);
}

package Net::Z3950::RPN::AndNot;

sub render {
	my ($self,$usemap) = @_;
    return $self->[0]->render($usemap) . ' AND NOT ' . $self->[1]->render($usemap);
}

package Net::Z3950::RPN::Term;

use Data::Dump qw(dump);
use COBISS;

sub render {
	my ($self,$usemap) = @_;

	die "no usemap" unless $usemap;

warn "# render ", dump($self);
warn "# usemap ", dump($usemap);

    my $attributes = {};
    my $prefix     = "";
    foreach my $attr ( @{ $self->{attributes} } ) {
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

    my $q = $prefix . $self->{term};
	print "# q: $q\n";
	return $q;
}

