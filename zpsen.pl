#!/usr/local/bin/perl

use warnings;
use strict;
use lib "/usr/local/lib/perl5/site_perl/5.8.9/";
use lib "/usr/local/lib/perl5/site_perl/5.8.9/mach";
#use lib '/root/xbee/';
use lib '.';

use Device::XBee::API::Power;
use Data::Dumper;
use Data::Hexdumper qw/hexdump/;

$Data::Dumper::Useqq = 1;

my $api = Device::XBee::API::Power->new( { device => "/dev/ttyU0", packet_timeout => 5 } ) || die $!;
my $r = $api->sensor_get( { dest_h => 1286656, dest_l => 1080058856 }, 1 );

warn Dumper $r;
while( 1 ) {
    $r = $api->rx();
    if ( $r ) { warn scalar localtime; warn Dumper $r };
}

