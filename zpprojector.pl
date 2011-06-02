#!/usr/local/bin/perl

use warnings;
use strict;
use lib "/usr/local/lib/perl5/site_perl/5.8.9/";
use lib "/usr/local/lib/perl5/site_perl/5.8.9/mach";
use lib '/root/xbee/';

use Device::XBee::API::Power;
use Data::Dumper;
use Data::Hexdumper qw/hexdump/;

my $api = Device::XBee::API::Power->new( { device => "/dev/ttyU0", packet_timeout => 5 } ) || die $!;
my $r;

$r = $api->switch_set( { dest_h => 1286656, dest_l => 1080058845 }, 2, 5 );
exit $r;
