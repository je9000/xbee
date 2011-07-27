#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';
use zpdapp;

my $zpd = zpdapp->new();

my $r = $zpd->send_recv( "switch projector id 2 value 5" );
exit $r->{power}->{switch_data};
