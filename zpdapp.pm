package zpdapp;

use strict;
use YAML;
use IO::Socket::UNIX;

use constant COM_SOCKET_PATH   => '/tmp/xbee_power';
use constant REPLY_SIZE_LENGTH => 8;

### Methods to aid clients

sub new {
    my ( $class, $options ) = @_;
    my $self = {};
    bless $self, $class;
    $self->{sock} = connect_to_zpd();
    return $self;
}

sub recv {
    my ( $self ) = @_;
    return sysread_zpd_reply( $self->{sock} );
}

sub send {
    my ( $self, $msg ) = @_;
    return syswrite( $self->{sock}, $msg );
}

sub socket {
    my ( $self ) = @_;
    return $self->{sock};
}

### Functions for both clients and servers

sub connect_to_zpd {
    return IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => COM_SOCKET_PATH ) || die $!;
}

sub make_zpd_reply {
    my ( $msg ) = @_;
    $msg = YAML::Dump( $msg );
    my $ml = length( $msg ) + 1;
    return sprintf( '%0' . REPLY_SIZE_LENGTH . "x\n%s\n", $ml, $msg );
}

sub syswrite_zpd_reply {
    my ( $fh, $msg ) = @_;
    return syswrite( $fh, make_zpd_reply( $msg ) );
}

sub sysread_zpd_reply {
    my ( $fh ) = @_;
    my $read = sysread_zpd_reply_raw( $fh );
    return undef unless defined $read;
    if (
        !defined eval {
            $read = YAML::Load( $read );
            die unless ref $read eq 'HASH';
            return 42;
        }
     )
    {
        return undef;
    }
    return $read;
}

sub sysread_zpd_reply_raw {
    my ( $fh ) = @_;
    my ( $read, $readsize );
    return undef unless sysread( $fh, $readsize, REPLY_SIZE_LENGTH + 1 ) == REPLY_SIZE_LENGTH + 1;
    return undef unless $readsize =~ /^[0-9a-fA-F]{8}\n$/s;
    chop( $readsize );
    $readsize = hex( $readsize );
    return undef unless sysread( $fh, $read, $readsize ) == $readsize;
    return undef unless $read =~ /\n\n\z/s;
    return $read;
}

1;
