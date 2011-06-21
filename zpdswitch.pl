#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';
use zpdapp;

my $zpd = zpdapp->new();

my $r;
my $arg = $ARGV[0];
die "Invalid parameters" unless defined $arg && $arg =~ m{^(?:1|0|R|toggle)$}i;
$arg = uc($arg);

if ( $arg eq 'TOGGLE' ) {
    $r = $zpd->send_recv( "switch frontdoor id 1" );
    $r = $r->{power}->{switch_data} ? 0 : 1;
    $r = $zpd->send_recv( "switch frontdoor id 1 value $r" );
    $r = $r->{power}->{switch_data};
} elsif ( $arg ne 'R' ) {
    $r = $zpd->send_recv( "switch frontdoor id 1 value $arg" );
    $r = $r->{power}->{switch_data};
} else {
    $r = $zpd->send_recv( "switch frontdoor id 1" );
    $r = $r->{power}->{switch_data};
}
exit $r;
