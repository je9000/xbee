#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';

use Device::XBee::API::Power;
use Data::Dumper;
use Data::Hexdumper qw/hexdump/;
use Device::SerialPort;

my $serial_port_device_path = '/dev/ttyU0';

my $serial_port_device = Device::SerialPort->new( $serial_port_device_path ) || die $!;
$serial_port_device->baudrate( 9600 );
$serial_port_device->databits( 8 );
$serial_port_device->stopbits( 1 );
$serial_port_device->parity( 'none' );
$serial_port_device->read_char_time( 0 );        # don't wait for each character
$serial_port_device->read_const_time( 1000 );    # 1 second per unfulfilled "read" call

my $api = Device::XBee::API::Power->new( { fh => $serial_port_device, packet_timeout => 5 } ) || die $!;
my $r;
my $arg = $ARGV[0];
die "Invalid parameters" unless defined $arg && $arg =~ m{^(?:1|0|R|toggle)$}i;
$arg = uc($arg);

if ( $arg eq 'TOGGLE' ) {
	$r = $api->switch_get( { dest_h => 1286656, dest_l => 1080058856 }, 1 );
	$r = $api->switch_set( { dest_h => 1286656, dest_l => 1080058856 }, 1, ( $r ? 0 : 1 ) );
} elsif ( $arg ne 'R' ) {
	$r = $api->switch_set( { dest_h => 1286656, dest_l => 1080058856 }, 1, $arg );
} else {
	$r = $api->switch_get( { dest_h => 1286656, dest_l => 1080058856 }, 1 );
}
exit $r;
