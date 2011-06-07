package zpd_lib;

use strict;
use YAML;

use constant COM_SOCKET_PATH => '/tmp/xbee_power';
use constant REPLY_SIZE_LENGTH => 8;

sub make_zpd_reply {
    my ( $msg ) = @_;
    $msg = YAML::Dump( $msg );
    my $ml = length( $msg ) + 1;
    return sprintf( '%0' . zpd_lib::REPLY_SIZE_LENGTH . "x\n%s\n", $ml, $msg );
}

sub syswrite_zpd_reply {
    my ( $fh, $msg ) = @_;
    return syswrite( $fh, make_zpd_reply( $msg ) );
}

sub sysread_zpd_reply {
    my ( $fh ) = @_;
    my $read = sysread_zpd_reply_raw( $fh );
    return undef unless defined $read;
    if ( eval {
        $read = YAML::Load( $read );
        42;
    } != 42 ) {
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
