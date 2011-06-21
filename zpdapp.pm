package zpdapp;

use strict;
use YAML;
use IO::Socket::UNIX;
use IO::Select;

use constant COM_SOCKET_PATH   => '/tmp/xbee_power';
use constant REPLY_SIZE_LENGTH => 8;

### Methods to aid clients

sub new {
    my ( $class, $options ) = @_;
    my $self = {};
    bless $self, $class;
    if ( ref $options ne 'HASH' ) { $options = {}; }
    $self->{sock} = connect_to_zpd();
    $self->{recv_timeout} = $options->{recv_timeout} || 20;
    $self->{recv_queue} = [];
    return $self;
}

sub recv {
    my ( $self ) = @_;
    if ( scalar( @{ $self->{recv_queue} } > 0 ) ) {
        return shift @{ $self->{recv_queue} };
    }
    return $self->recv_no_queue();
}

sub recv_no_queue {
    my ( $self ) = @_;
    return sysread_zpd_reply( $self->{sock} );
}

sub send_recv {
    my ( $self, $msg ) = @_;
    return unless $self->send( $msg );   
    my $id_packet = $self->recv_no_queue();
    while( my $r = $self->recv_no_queue() ) {
        if ( $r->{request_id} == $id_packet->{tx_id} ) {
            return $r;
        } else {
            push @{ $self->{recv_queue} }, $r;
        }
    }
}

sub send {
    my ( $self, $msg ) = @_;
    return syswrite( $self->{sock}, $msg . "\n" );
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
    my ( $fh, $read_timeout ) = @_;
    my ( $read, $readsize );
    my $timeout = $read_timeout || undef;
    my $start_ts = time();

    my $sel = IO::Select->new( $fh ) || die $!;
    if ( !$sel->can_read( $timeout ) ) {
        die "Packet read timeout";
    }
    return undef unless sysread( $fh, $readsize, REPLY_SIZE_LENGTH + 1 ) == REPLY_SIZE_LENGTH + 1;
    return undef unless $readsize =~ /^[0-9a-fA-F]{8}\n$/s;
    chop( $readsize );
    $readsize = hex( $readsize );

    if ( $timeout ) {
        $timeout = $read_timeout - ( time() - $start_ts );
        if ( $timeout < 1 ) { die "Packet read timeout"; }
    }
    if ( !$sel->can_read( $timeout ) ) {
        die "Packet read timeout";
    }
    return undef unless sysread( $fh, $read, $readsize ) == $readsize;
    return undef unless $read =~ /\n\n\z/s;
    return $read;
}

1;
