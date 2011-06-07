#!/usr/local/bin/perl

use warnings;
use strict;
use IO::Select;
use IO::Socket::UNIX;
use lib '.';
use zpd_lib;

my $sock = IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => zpd_lib::COM_SOCKET_PATH ) || die $!;
print "Connected!\n";
my $stdin = IO::Handle->new_from_fd(fileno(STDIN), 'r') || die $!;
my $sel = IO::Select->new( $sock, $stdin );
$|++;

my $init_command;
if ( @ARGV ) {
    $init_command = join( ' ', @ARGV );
    print $sock $init_command . "\n";
}

while( my @ready = $sel->can_read() ) {
    foreach my $r ( @ready ) {
        my $read;
        if ( !defined $init_command && $r == $stdin ) {
            $read = <$stdin>;
            die unless $read;
            syswrite( $sock,  $read )
        } elsif ( $r == $sock ) {
            $read = zpd_lib::sysread_zpd_reply_raw( $r );
            if ( !defined $read ) {
                print "!!! Read error";
            } else {
                print $read;
            }
            exit 0 if $init_command;
        } else { die "??"; }
    }
}
