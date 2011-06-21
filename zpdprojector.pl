#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';
use zpdapp;

my $zpd = zpdapp->new();

my $r = $zpd->send_recv( "switch frontdoor id 1 value 5" );
return $r->{power}->{switch_data};
