#!/usr/local/bin/perl

use warnings;
use strict;
use IO::Select;
use IO::Socket::UNIX;

use constant USERLAND_COM_SOCKET => '/tmp/xbee_power';
use constant REPLY_SIZE_LENGTH => 8;

my $sock = IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => USERLAND_COM_SOCKET ) || die $!;
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
            die unless sysread( $sock, $read, REPLY_SIZE_LENGTH + 1 );
            die unless $read =~ /^[0-9a-fA-F]{8}\n$/s;
            chomp($read);
            die unless sysread( $sock, $read, hex($read) );
            print $read;
            exit 0 if $init_command;
        } else { die "??"; }
    }
}
