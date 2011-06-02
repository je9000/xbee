package zpapp;

use strict;
use IO::Socket::UNIX;
use YAML;

use constant USERLAND_COM_SOCKET => '/tmp/xbee_power';
use constant REPLY_SIZE_LENGTH => 8;

sub new {
    my ( $class, $options ) = @_;
    my $self = {};
    bless $self, $class;
    $self->{sock} = IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => USERLAND_COM_SOCKET ) || die $!;
    return $self;
}

sub read_bytes {
    my ( $self, $bytes_to_read ) = @_;
    my $bytes_read_so_far = 0;
    my $read_so_far = '';
    while ( $bytes_read_so_far < $bytes_to_read ) {
        my $read;
        my $r = sysread( $self->{sock}, $read, $bytes_to_read - $bytes_read_so_far );
        if ( $r <= 0 ) { return undef; }
        $read_so_far .= $read;
        $bytes_read_so_far += $r;
    }
    return $read_so_far;
}

sub read_event {
    my ( $self ) = @_;
    my $r = $self->read_bytes( REPLY_SIZE_LENGTH );
    return undef unless $r;
    return undef unless $r =~ /^[\da-f]+\n$/si; 
    chomp($r);
    $r = hex( $r );
    return undef unless $r;
    $r = $self->read_bytes( $r );
    return YAML::Load( $r );
}

sub send_command {
    my ( $self, $command ) = @_;
    if ( $command !~ /\n$/s ) { $command .= "\n"; }
    return syswrite( $self->{sock}, $command );
}

1;
