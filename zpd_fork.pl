#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';
use Device::XBee::API::Power;
use Data::Dumper;
use Data::Hexdumper qw/hexdump/;
use Device::SerialPort;
use Socket qw/AF_UNIX PF_UNSPEC SOCK_STREAM/;
use IO::Select;

my $serial_port_device_path = '/dev/ttyU0';

socketpair( my $serial_proxy_fork, my $serial_proxy_main, AF_UNIX, SOCK_STREAM, PF_UNSPEC ) || die $!;
my $serial_proxy_pid = fork();
if ( !defined $serial_proxy_pid ) { die "Failed to fork: $!"; }

# This fork proxies for the serial port.
if ( !$serial_proxy_pid ) {
    close( $serial_proxy_main );

    my $serial_port_device = Device::SerialPort->new( $serial_port_device_path ) || die $!;
    $serial_port_device->baudrate( 9600 );
    $serial_port_device->databits( 8 );
    $serial_port_device->stopbits( 1 );
    $serial_port_device->parity( 'none' );
    $serial_port_device->read_char_time( 0 );        # don't wait for each character
    $serial_port_device->read_const_time( 1000 );    # 1 second per unfulfilled "read" call

    my $sel = IO::Select->new( $serial_proxy_fork, $serial_port_device->{FD} ) || die $!;
    MAIN_PROXY_LOOP: while( my @ready = $sel->can_read() ) {
        foreach my $r ( @ready ) {
            my $read;
            # Stuff from the proxy goes right out to the serial port.
            if ( $r == $serial_proxy_fork ) {
                sysread( $serial_proxy_fork, $read, 1024 ) || last MAIN_PROXY_LOOP;
                $serial_port_device->write( $read );
            # Stuff from the read proxy goes to the main.
            } elsif ( $r == $serial_port_device->{FD} ) {
                ( my $count, $read ) = $serial_port_device->read( 1 );
                last unless $count;
                syswrite( $serial_proxy_fork, $read, 1 ) || last MAIN_PROXY_LOOP;
            } else {
                die "Who are you?";
            }
        }
    }
    exit(1);
}
close( $serial_proxy_fork );

my $api = Device::XBee::API::Power->new( { fh => $serial_proxy_main } ) || die $!;
$|++;
my $x = 0;

$Data::Dumper::Useqq=1;
$api->discover_network();
warn Dumper($api->known_nodes());

while ( 1 ) {
    #    xbee_tx( XBEE_API_BROADCAST_ADDR_H, XBEE_API_BROADCAST_ADDR_L, XBEE_API_BROADCAST_NA_UNK_ADDR, "a" );
    #die unless $api->tx( { dest_h => 1286656, dest_l => 1080058845 }, 'a' );
    #next unless $api->tx( { dest_h => 1286656, dest_l => 1080058856 }, 'a' x 40 );
    #next unless $api->tx( { dest_h => 1286656, dest_l => 1080058856 }, pack( 'CCCCC', 1, 3, 1, 1, $ARGV[0] ? 1 : 0 ) );
    my $rx = $api->ping( { dest_h => 1286656, dest_l => 1080058856 } );
    if ( $rx ) {
        print "!";
    #    warn "got response! " . hexdump( $rx->{data} );
    } else { print "."; }
    sleep(1);
}

