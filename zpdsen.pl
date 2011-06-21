#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';
use zpdapp;

my $zpd = zpdapp->new();

while(1) {
    my $r = $zpd->send_recv( "sensor frontdoor id 2" );
    print scalar(localtime), " - ", $r->{power}->{sensor_data}, "\n";
    sleep(1);
}
