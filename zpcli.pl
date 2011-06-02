#!/usr/local/bin/perl

use warnings;
use strict;
use IO::Select;
use IO::Socket::UNIX;

use constant USERLAND_COM_SOCKET => '/tmp/xbee_power';

my $sock = IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => USERLAND_COM_SOCKET ) || die $!;
print "Connected!\n";
my $stdin = IO::Handle->new_from_fd(fileno(STDIN), 'r') || die $!;
my $sel = IO::Select->new( $sock, $stdin );
$|++;

while( my @ready = $sel->can_read() ) {
    foreach my $r ( @ready ) {
        my $read;
        if ( $r == $stdin ) {
            $read = <$stdin>;
            die unless $read;
            syswrite( $sock,  $read )
        } elsif ( $r == $sock ) {
            die unless sysread( $sock, $read, 1024 );
            print $read;
        } else { die "??"; }
    }
}
