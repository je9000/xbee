package Device::XBee::API::Power;

use strict;
use Device::XBee::API qw/:xbee_flags/;
use base qw/Device::XBee::API/;

use constant XBEE_POWER_VERSION => 1;
use constant XBEE_POWER_PACKET_TYPE_PING =>          0;
use constant XBEE_POWER_PACKET_TYPE_HELLO =>         1;
use constant XBEE_POWER_PACKET_TYPE_SENSOR_QUERY =>  2;
use constant XBEE_POWER_PACKET_TYPE_SWITCH_ACTION => 3;
use constant XBEE_POWER_PACKET_TYPE_QUERY =>         4;
use constant XBEE_POWER_PACKET_TYPE_ERROR =>         5;
use constant XBEE_POWER_PACKET_TYPE_PONG =>          6;
use constant XBEE_POWER_PACKET_TYPE_SENSOR_DATA =>   7;
use constant XBEE_POWER_PACKET_TYPE_SWITCH_DATA =>   8;

use constant XBEE_POWER_PACKET_ID_ACK_BIT_MASK => 0x80;
use constant XBEE_POWER_PACKET_ID_NO_ACK => 0;
use constant XBEE_POWER_PACKET_ID_MAX => 127;

use constant XBEE_POWER_SWITCH_ACTION_READ => 0x52; # 'R'
use constant XBEE_POWER_SWITCH_ACTION_ON   => 1;
use constant XBEE_POWER_SWITCH_ACTION_OFF  => 0;

use constant DEFAULT_RETRY_COUNT  => 5;

sub new {
    my ( $class, $options ) = @_;

    my %myopts;

    if ( exists $options->{async} ) {
        $myopts{async} = 1;
        delete $options->{async};
    }

    if ( exists $options->{retry_count} ) {
        $myopts{retry_count} = $options->{retry_count};
        delete $options->{retry_count};
    }

    my $self = $class->SUPER::new( $options );
    foreach my $k ( keys( %myopts ) ) {
        $self->{$k} = $myopts{$k};
    }

    if ( !$self->{retry_count} ) {
        $self->{retry_count} = DEFAULT_RETRY_COUNT;
    }

    $self->{in_flight_power_ids} = {};
    return $self;
}

sub __make_acked_id {
    my ( $id ) = @_;
    return $id | XBEE_POWER_PACKET_ID_ACK_BIT_MASK;
}

sub __make_unacked_id {
    my ( $id ) = @_;
    return $id ^ XBEE_POWER_PACKET_ID_ACK_BIT_MASK;
}

sub free_power_id {
    my ( $self, $id ) = @_;
    delete $self->{in_flight_power_ids}->{$id};
}

# Sometimes remote nodes will reply multiple times to a query. I assume it's
# because they don't get the ACK so they know their reply made it. We could
# detect this based on previously issued power IDs but we don't now. The risk
# is if the same ID gets re-used, a re-ACK to a previous message might be
# mistakenly associated with a newer message.
sub alloc_power_id {
    my ( $self ) = @_;
    my $id;
    do {
        # We use the MSB to indicate an "ack", so we can only use the bottom 7
        # bits for the power id. 0 is also reserved for special use, so we
        # generate a number between 1 and 127.
        $id = int( rand( 127 ) ) + 1;
    } while ( $self->{in_flight_power_ids}->{$id} );
    $self->{in_flight_power_ids}->{$id} = 1;

    return $id;
}

sub tx {
    my $self = shift;
    return $self->SUPER::tx(@_);
}

sub rx {
    my ( $self, $rx ) = @_;
    my @u;
    my $power_data;

    $rx = $self->SUPER::rx( $rx );

    if (
        ( !$rx )
     || ( ref $rx ne 'HASH' )
     || ( $rx->{api_type} != XBEE_API_TYPE__ZIGBEE_RECEIVE_PACKET )
     || ( length( $rx->{data} ) < 1 )
    ) {
        return $rx;
    }

    @u = unpack( 'C', $rx->{data} );
    $rx->{power} = { version => $u[0] };
    if ( $rx->{power}->{version} != XBEE_POWER_VERSION ) { return $rx; }

    my $p = $rx->{power}; # Easier to type.

    @u = unpack( 'CCCa*', $rx->{data} );
    $p->{type} = $u[1];
    $p->{id} = $u[2];

    $power_data = $u[3];

    if ( $p->{type} == XBEE_POWER_PACKET_TYPE_SWITCH_DATA ) {
        @u = unpack( 'CC', $power_data );
        $p->{switch_id} = $u[0];
        $p->{switch_data} = $u[1];

    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_SENSOR_DATA ) {
        @u = unpack( 'Cn', $power_data );
        $p->{sensor_id} = $u[0];
        $p->{sensor_data} = unpack( 's', pack( 'S', $u[1] ) );

    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_HELLO ) {
        @u = unpack( 'CC', $power_data );
        $p->{switch_count} = $u[0];
        $p->{sensor_count} = $u[1];
        # Re-use this variable. Ew.
        $u[0] = substr( $power_data, 2 );
        if ( $u[0] ) {
            @u = split( /\0/, $u[0] );
            $p->{system_name} = $u[0];
            $p->{switch_names} = [ split( /\x1/, $u[1] ) ];
            $p->{sensor_names} = [ split( /\x1/, $u[2] ) ];
        }

    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_ERROR ) {
        @u = unpack( 'C', $power_data );
        $p->{error} = $u[0];

    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_SENSOR_QUERY ) {
        @u = unpack( 'C', $power_data );
        $p->{sensor_id} = $u[0];

    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_SWITCH_ACTION ) {
        @u = unpack( 'CC', $power_data );
        $p->{switch_id} = $u[0];
        $p->{switch_action} = $u[1];

    # Nothing to do for these
    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_PING ) {
    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_PONG ) {
    } elsif ( $p->{type} == XBEE_POWER_PACKET_TYPE_QUERY ) {

    }
    return $rx;
}

sub wait_for_reply {
    my ( $self, $power_id ) = @_;
    my @rx_queue;
    my $rx;
    while(1) {
        $rx = $self->rx();
        if ( !$rx ) { return undef; }
        if (
            ( !$rx->{power} )
         || ( !exists $rx->{power}->{type} )
         || ( $rx->{power}->{id} != __make_acked_id( $power_id ) )
        ) {
            push @rx_queue, $rx;
        } else {
            last;
        }
    }
    if ( @rx_queue ) { $self->unshift_rx( \@rx_queue ); }
    return $rx;
}

sub query {
    my ( $self, $endpoint ) = @_;
    my $rx;
    my $id = $self->alloc_power_id();
    my $i = 0;

    RETRY_TRANSMIT:
    do {
        if ( $i++ > $self->{retry_count} ) { return undef; };
        $rx = $self->tx( $endpoint, pack( 'CCC', XBEE_POWER_VERSION, XBEE_POWER_PACKET_TYPE_QUERY, $id ), $self->{async} );
        if ( $self->{async} ) {
            return $id if $rx;
            return undef;
        }
    } while ( !$rx );

    $rx = $self->wait_for_reply( $id );
    if ( !$rx ) { goto RETRY_TRANSMIT; }
    return $rx;
}

sub ping {
    my ( $self, $endpoint ) = @_;
    my $rx;
    my $id = $self->alloc_power_id();
    my $i = 0;

    RETRY_TRANSMIT:
    do {
        if ( $i++ > $self->{retry_count} ) { return undef; };
        $rx = $self->tx( $endpoint, pack( 'CCC', XBEE_POWER_VERSION, XBEE_POWER_PACKET_TYPE_PING, $id ), $self->{async} );
        if ( $self->{async} ) {
            return $id if $rx;
            return undef;
        }
    } while ( !$rx );

    $rx = $self->wait_for_reply( $id );
    if ( !$rx ) { goto RETRY_TRANSMIT; }
    return $rx->{power}->{type} == XBEE_POWER_PACKET_TYPE_PONG ? 1 : undef;
}

sub switch_set {
    my ( $self, $endpoint, $switch, $newval ) = @_;
    my $rx;
    my $id = $self->alloc_power_id();
    my @rx_queue;
    my $i = 0;

    RETRY_TRANSMIT:
    do {
        if ( $i++ > $self->{retry_count} ) { return undef; };
        $rx = $self->tx( $endpoint, pack( 'CCCCC', XBEE_POWER_VERSION, XBEE_POWER_PACKET_TYPE_SWITCH_ACTION, $id, $switch, $newval ), $self->{async} );
        if ( $self->{async} ) {
            return $id if $rx;
            return undef;
        }
    } while ( !$rx );

    $rx = $self->wait_for_reply( $id );
    if ( !$rx ) { goto RETRY_TRANSMIT; }
    return undef if $rx->{power}->{type} != XBEE_POWER_PACKET_TYPE_SWITCH_DATA;
    return $rx->{power}->{switch_data};
}

sub switch_get {
    my ( $self, $endpoint, $switch ) = @_;
    return $self->switch_set( $endpoint, $switch, XBEE_POWER_SWITCH_ACTION_READ );
}

sub sensor_get {
    my ( $self, $endpoint, $sensor ) = @_;
    my $rx;
    my $id = $self->alloc_power_id();
    my @rx_queue;
    my $i = 0;

    RETRY_TRANSMIT:
    do {
        if ( $i++ > $self->{retry_count} ) { return undef; };
        $rx = $self->tx( $endpoint, pack( 'CCCC', XBEE_POWER_VERSION, XBEE_POWER_PACKET_TYPE_SENSOR_QUERY, $id, $sensor ), $self->{async} );
        if ( $self->{async} ) {
            return $id if $rx;
            return undef;
        }
    } while ( !$rx );

    $rx = $self->wait_for_reply( $id );
    if ( !$rx ) { goto RETRY_TRANSMIT; }
    return undef if $rx->{power}->{type} != XBEE_POWER_PACKET_TYPE_SENSOR_DATA;
    return $rx->{power}->{sensor_data};
}

1;
