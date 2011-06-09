package Device::XBee::API;

use strict;

require Exporter;
our ( @ISA, @EXPORT_OK, %EXPORT_TAGS );

our $VERSION = 0.3;

use constant 1.01;
use constant XBEE_API_TYPE__MODEM_STATUS                             => 0x8A;
use constant XBEE_API_TYPE__AT_COMMAND                               => 0x08;
use constant XBEE_API_TYPE__AT_COMMAND_QUEUE_PARAMETER_VALUE         => 0x09;
use constant XBEE_API_TYPE__AT_COMMAND_RESPONSE                      => 0x88;
use constant XBEE_API_TYPE__REMOTE_COMMAND_REQUEST                   => 0x17;
use constant XBEE_API_TYPE__REMOTE_COMMAND_RESPONSE                  => 0x97;
use constant XBEE_API_TYPE__ZIGBEE_TRANSMIT_REQUEST                  => 0x10;
use constant XBEE_API_TYPE__EXPLICIT_ADDRESSING_ZIGBEE_COMMAND_FRAME => 0x11;
use constant XBEE_API_TYPE__ZIGBEE_TRANSMIT_STATUS                   => 0x8B;
use constant XBEE_API_TYPE__ZIGBEE_RECEIVE_PACKET                    => 0x90;
use constant XBEE_API_TYPE__ZIGBEE_EXPLICIT_RX_INDICATOR             => 0x91;
use constant XBEE_API_TYPE__ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR       => 0x92;
use constant XBEE_API_TYPE__XBEE_SENSOR_READ_INDICATOR_              => 0x94;
use constant XBEE_API_TYPE__NODE_IDENTIFICATION_INDICATOR            => 0x95;

use constant XBEE_API_TYPE_TO_STRING => {
    0x8A => 'MODEM_STATUS',
    0x08 => 'AT_COMMAND',
    0x09 => 'AT_COMMAND_QUEUE_PARAMETER_VALUE',
    0x88 => 'AT_COMMAND_RESPONSE',
    0x17 => 'REMOTE_COMMAND_REQUEST',
    0x97 => 'REMOTE_COMMAND_RESPONSE',
    0x10 => 'ZIGBEE_TRANSMIT_REQUEST',
    0x11 => 'EXPLICIT_ADDRESSING_ZIGBEE_COMMAND_FRAME',
    0x8B => 'ZIGBEE_TRANSMIT_STATUS',
    0x90 => 'ZIGBEE_RECEIVE_PACKET',
    0x91 => 'ZIGBEE_EXPLICIT_RX_INDICATOR',
    0x92 => 'ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR',
    0x94 => 'XBEE_SENSOR_READ_INDICATOR_',
    0x95 => 'NODE_IDENTIFICATION_INDICATOR',
};

use constant XBEE_API_BROADCAST_ADDR_H          => 0x00;
use constant XBEE_API_BROADCAST_ADDR_L          => 0xFFFF;
use constant XBEE_API_BROADCAST_NA_UNKNOWN_ADDR => 0xFFFE;

{
    my @xbee_flags = map { /::([^:]+)$/; $1 }
     grep( /^Device::XBee::API::XBEE_API_/, keys( %constant::declared ) );

    @ISA       = ( 'Exporter' );
    @EXPORT_OK = ( @xbee_flags );

    %EXPORT_TAGS = ( 'xbee_flags' => [@xbee_flags], );
}

=head1 NAME

Device::XBee::API - Object-oriented Perl interface to Digi XBee module API
mode.

=head1 EXAMPLE

A basic example:

 use Device::SerialPort;
 use Device::XBee::API;
 use Data::Dumper;
 my $serial_port_device = Device::SerialPort->new( '/dev/ttyU0' ) || die $!;
 $serial_port_device->baudrate( 9600 );
 $serial_port_device->databits( 8 );
 $serial_port_device->stopbits( 1 );
 $serial_port_device->parity( 'none' );
 $serial_port_device->read_char_time( 0 );        # don't wait for each character
 $serial_port_device->read_const_time( 1000 );    # 1 second per unfulfilled "read" call

 my $api = Device::XBee::API->new( { fh => $serial_port_device } ) || die $!;
 die "Failed to transmit" unless $api->tx(
    { sh => 0, sl => 0 },
    'hello world!'
 );
 my $rx = $api->rx();
 die Dumper($rx);

=head1 SYNOPSIS

Device::XBee::API is a module designed to encapsulate the Digi XBee API in
object-oriented Perl. This module expects to communicate with an XBee module
using the API firmware via a serial (or serial over USB) device.

This module is currently a work in progress and thus the API may change in the
future.

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=head1 CONSTANTS

A single set of constants, ':xbee_flags', can be imported. These constants
all represent various XBee flags, such as packet types and broadcast addresses.
See the XBee datasheet for details. The following constants are available:

 XBEE_API_TYPE__MODEM_STATUS
 XBEE_API_TYPE__AT_COMMAND
 XBEE_API_TYPE__AT_COMMAND_QUEUE_PARAMETER_VALUE
 XBEE_API_TYPE__AT_COMMAND_RESPONSE
 XBEE_API_TYPE__REMOTE_COMMAND_REQUEST
 XBEE_API_TYPE__REMOTE_COMMAND_RESPONSE
 XBEE_API_TYPE__ZIGBEE_TRANSMIT_REQUEST
 XBEE_API_TYPE__EXPLICIT_ADDRESSING_ZIGBEE_COMMAND_FRAME
 XBEE_API_TYPE__ZIGBEE_TRANSMIT_STATUS
 XBEE_API_TYPE__ZIGBEE_RECEIVE_PACKET
 XBEE_API_TYPE__ZIGBEE_EXPLICIT_RX_INDICATOR
 XBEE_API_TYPE__ZIGBEE_IO_DATA_SAMPLE_RX_INDICATOR
 XBEE_API_TYPE__XBEE_SENSOR_READ_INDICATOR_
 XBEE_API_TYPE__NODE_IDENTIFICATION_INDICATOR
 
 XBEE_API_BROADCAST_ADDR_H
 XBEE_API_BROADCAST_ADDR_L
 XBEE_API_BROADCAST_NA_UNKNOWN_ADDR
 
 XBEE_API_TYPE_TO_STRING

The above should be self explanatory (with the help of the datasheet). The
constant "XBEE_API_TYPE_TO_STRING" is a hashref keyed by the numeric id of the
packet type with the value being the constant name, to aid in debugging.

=head1 METHODS

=head2 new

Object constructor. Accepts a single parameter, a hashref of options. The
following options are recognized:

=head3 fh

Required. The filehandle to be used to communicate with. This object can be a
standard filehandle (that can be accessed via sysread() and syswrite()), or a
Device::SerialPort object.

=head3 packet_timeout

Optional, defaults to 20. Amount of time (in seconds) to wait for a read to
complete. Smaller values cause the module to wait less time for a packet to be
received by the XBee module. Setting this value too low will cause timeouts to
be reported in situations where the network is "slow".

When using standard filehandles, the timeout is implemented via alarm(). When
using a Device::SerialPort object, the timeout is done via Device::SerialPort's
read() method, and will expect the object to be configured with a
read_char_time of 0 and a read_const_time of 1000.

=head3 node_forget_time

If a node has not been heard from in this time, it will be "forgotten" and
removed from the list of known nodes. Defaults to one hour. See L<known_nodes>
for details.

=cut

sub new {
    my ( $class, $options ) = @_;
    my $self = {};

    die "Missing file handle!" unless $options->{'fh'};

    $self->{packet_wait_time}      = $options->{packet_timeout} || 20;
    $self->{node_forget_time}      = $options->{node_forget_time} || 60 * 60;
    $self->{in_flight_uart_frames} = {};
    $self->{known_nodes}           = {};
    $self->{rx_queue}              = [];
    $self->{port}                  = $options->{'fh'};

    bless $self, $class;
    return $self;
}

sub read_bytes {
    my ( $self, $to_read ) = @_;
    die unless $to_read;
    my $chars   = 0;
    my $buffer  = '';
    my $timeout = $self->{packet_wait_time};

    if ( ref $self->{port} eq 'Device::SerialPort' ) {
        while ( $timeout > 0 ) {
            my ( $count, $saw ) = $self->{port}->read( $to_read );    # will read _up to_ 255 chars
            if ( $count > 0 ) {
                $chars += $count;
                $buffer .= $saw;
                if ( $chars >= $to_read ) { return $buffer; }
            } else {
                $timeout--;
            }
        }
    } else {
        my $read;
        eval {
            $SIG{ALRM} = sub { die "a\n"; };
            while ( $to_read > 0 ) {
                alarm( $timeout );
                my $c = sysread( $self->{port}, $read, $to_read );
                if ( $c ) {
                    $buffer .= $read;
                    $to_read -= $c;
                } else {
                    alarm( 0 );
                    return undef;
                }
            }
            alarm( 0 );
        };
        if ( !$@ ) { return $buffer; }
    }
    return undef;
}

sub read_packet {
    my ( $self ) = @_;
    my $d;

    do {
        $d = $self->read_bytes( 1 );
        return undef if !defined $d;
    } while ( $d ne "\x7E" );

    $d = $self->read_bytes( 2 );
    my ( $packet_data_length ) = unpack( 'n', $d );

    $d = $self->read_bytes( $packet_data_length + 1 );
    die unless $d;
    $packet_data_length--;
    my ( $packet_api_id, $packet_data, $packet_checksum ) = unpack( "Ca[$packet_data_length]C", $d );
    my $validate_checksum = $packet_api_id + $packet_checksum;
    for ( my $i = 0; $i < $packet_data_length; $i++ ) {
        $validate_checksum += unpack( 'c', substr( $packet_data, $i, 1 ) );
    }

    if ( ( $validate_checksum & 0xFF ) != 0xFF ) {
        warn "Invalid checksum!";
        return undef;
    }

    return ( $packet_api_id, $packet_data );
}

sub parse_at_nd_response {
    my ( $self, $r ) = @_;
    (
        $r->{my},
        $r->{sh},
        $r->{sl},
        $r->{ni},
        $r->{parent_network_address},
        $r->{device_type},
        # This byte is reserved, so ignore it. If we restore it, be careful because
        # upper layers also have an element named 'status'.
        undef,    #$r->{status},
        $r->{profile_id},
        $r->{manufacturer_id},
    ) = unpack( 'nNNZ*nCCnna*', $r->{data} );
}

sub parse_at_command_response {
    my ( $self, $api_data ) = @_;

    my @u = unpack( 'Ca[2]Ca*', $api_data );

    my $r = {
        frame_id             => $u[0],
        command              => $u[1],
        status               => $u[2],
        data                 => $u[3],
        is_ok                => $u[2] == 0,
        is_error             => $u[2] == 1,
        is_invalid_command   => $u[2] == 2,
        is_invalid_parameter => $u[2] == 3,
    };

    if ( $r->{command} eq 'ND' ) {
        $self->parse_at_nd_response( $r );
    } else {
        if ( length( $r->{data} ) == 1 ) {
            $r->{data_as_int} = unpack( 'C', $r->{data} );
        } elsif ( length( $r->{data} ) == 2 ) {
            $r->{data_as_int} = unpack( 'n', $r->{data} );
        } elsif ( length( $r->{data} ) == 4 ) {
            $r->{data_as_int} = unpack( 'N', $r->{data} );
        }
    }

    return $r;
}

sub free_frame_id {
    my ( $self, $id ) = @_;
    delete $self->{in_flight_uart_frames}->{$id};
}

# id 0 is special, don't allocate it. I don't know if we should die here or
# return 0 on failure...
sub alloc_frame_id {
    my ( $self ) = @_;
    my $start_id = int( rand( 255 ) ) + 1;
    my $id = $start_id;
    while (1) {
        if ( !exists $self->{in_flight_uart_frames}->{$id} ) {
            $self->{in_flight_uart_frames}->{$id} = 1;
            return $id;
        }
        $id++;
        if ( $id > 255 ) { $id = 1; }
        if ( $id == $start_id ) {
            die "Unable to allocate frame id!";
        }
    }
}

sub parse_packet {
    my ( $self, $api_id, $api_data, $dont_free_id ) = @_;
    my @u;
    my $r;

    if ( $api_id == XBEE_API_TYPE__AT_COMMAND_RESPONSE ) {
        $r = $self->parse_at_command_response( $api_data );

    } elsif ( $api_id == XBEE_API_TYPE__MODEM_STATUS ) {
        @u = unpack( 'C', $api_data );
        $r = {
            status            => $u[1],
            is_hardware_reset => $u[1] == 1,
            is_wdt_reset      => $u[1] == 2,
            is_associated     => $u[1] == 3,
            is_disassociated  => $u[1] == 4,
            is_sync_lost      => $u[1] == 5,
            is_coord_realign  => $u[1] == 6,
            is_coord_start    => $u[1] == 7,
        };

    } elsif ( $api_id == XBEE_API_TYPE__ZIGBEE_RECEIVE_PACKET ) {
        @u = unpack( 'NNnCa*', $api_data );
        # sh sl and na are named to match the fields in a network discovery AT
        # packet response
        $r = {
            sh              => $u[0],
            sl              => $u[1],
            na              => $u[2],
            options         => $u[3],
            data            => $u[4],
            is_ack          => $u[3] & 0x01,
            is_broadcast    => ( $u[3] & 0x02 ? 1 : 0 ),
        };
    } elsif ( $api_id == XBEE_API_TYPE__ZIGBEE_TRANSMIT_STATUS ) {
        @u = unpack( 'CnCCC', $api_data );
        $r = {
            frame_id         => $u[0],
            remote_na        => $u[1],
            tx_retry_count   => $u[2],
            delivery_status  => $u[3],
            discovery_status => $u[4]
        };
    } elsif ( XBEE_API_TYPE_TO_STRING->{$api_id} ) {
        warn "No code to handle this packet: " . XBEE_API_TYPE_TO_STRING->{$api_id};
    } else {
        warn "Got unknown packet type: $api_id";
    }

    if ( !$dont_free_id && $r->{frame_id} ) {
        $self->free_frame_id( $r->{frame_id} );
    }
    $r->{api_type} = $api_id;
    $r->{api_data} = $api_data;

    $self->_add_known_node( $r );
    return $r;
}

sub send_packet {
    my ( $self, $api_id, $data ) = @_;
    my $xbee_data = "\x7E" . pack( 'nC', length( $data ) + 1, $api_id );
    my $checksum = $api_id;

    for ( my $i = 0; $i < length( $data ); $i++ ) {
        $checksum += unpack( 'C', substr( $data, $i, 1 ) );
    }
    $checksum = pack( 'C', 0xFF - ( $checksum & 0xFF ) );

    if ( ref $self->{port} eq 'Device::SerialPort' ) {
        $self->{port}->write( $xbee_data . $data . $checksum );
    } else {
        syswrite( $self->{port}, $xbee_data . $data . $checksum );
    }
}

=head2 at

Send an AT command to the module. Accepts two parameters, the first is the AT
command name (as two-character string), and the second is the expected data
for that command (if any). See the XBee datasheet for a list of supported AT
commands and expected data for each.

Returns the frame ID sent for this packet. This method does not wait for a
reply from the XBee, as the expected reply is dependent on the AT command sent.
To retrieve the reply (if any), call rx().

=cut

sub at {
    my ( $self, $command, $data ) = @_;
    $data = '' unless $data;
    my $frame_id = $self->alloc_frame_id();
    $self->send_packet( XBEE_API_TYPE__AT_COMMAND, pack( 'C', $frame_id ) . $command . $data );
    return $frame_id;
}

=head2 tx

Sends a transmit request to the XBee. Accepts two parameters, the first is the
endpoint address and the second the data to be sent.

Endpoint addresses should be specified as a hashref containing the following
keys:

=over 4

=item sl

The high 32-bits of the destination address.

=item sl

The low 32-bits of the destination address.

=item dest_na

The destination network address.

=back

The meaning of these addresses can be found in the XBee datasheet. Note: In
the future, a Device::XBee::API::Node object will be an acceptable parameter.

Return values depend on calling context. In scalar context, true or false will
be returned representing transmission acknowledgement by the remote XBee
device. In array context, the first return value is the delivery status (as
set in the transmit status packet and documented in the datasheet), and the
second is the actual transmit status packet (as a hashref) itself.

No retransmissions will be attempted by this module, but the XBee
device itself will likely attempt retransmissions as per its configuration (and
subject to whether or not the packet was a "broadcast").

=cut

# API is goofy here. If called in scalar context, returns true or false if the
# packet was transmitted. If called in array context, returns the delivery
# status and the transmit status packet as an array. Note: the actual delivery
# status uses 0 (or false) to indicate success.
sub tx {
    my ( $self, $tx, $data ) = @_;
    my @my_rx_queue;
    if ( !$tx && !$data ) { die "Invalid parameters"; }
    if ( !defined $tx && defined $data ) {
        $tx = {};
    } elsif ( ref $tx ne 'HASH' ) {
        $data = $tx;
        $tx   = {};
    }

    if ( ( $tx->{sh} && !$tx->{sl} ) || ( !$tx->{sh} && $tx->{sl} ) ) { die "Invalid parameters"; }

    if ( !defined $tx->{na} ) { $tx->{na} = XBEE_API_BROADCAST_NA_UNKNOWN_ADDR; }
    if ( !defined $tx->{sh} ) {
        $tx->{sh} = XBEE_API_BROADCAST_ADDR_H;
        $tx->{sl} = XBEE_API_BROADCAST_ADDR_L;
    }

    my $frame_id = $self->alloc_frame_id();
    my $tx_req =
     pack( 'CNNnCC', $frame_id, $tx->{sh}, $tx->{sl}, $tx->{na}, 0, ( $tx->{broadcast} ? 0x8 : 0 ) );
    $self->send_packet( XBEE_API_TYPE__ZIGBEE_TRANSMIT_REQUEST, $tx_req . $data );
    my $rx;

    # Wait until we get the send result message.
    $rx = $self->rx_frame_id( $frame_id );
    return undef unless defined $rx;

    # Wonky return API.
    if ( wantarray ) {
        return ( $rx->{delivery_status}, $rx );
    } else {
        if ( $rx->{delivery_status} == 0 ) {
            return 1;
        } else {
            return 0;
        }
    }
}

sub _unshift_rx {
    my ( $self, $rxq ) = @_;

    if ( !$rxq ) { return; }
    if ( ref $rxq eq '' ) {
        unshift @{ $self->{rx_queue} }, $rxq;
    } elsif ( ref $rxq eq 'ARRAY' ) {
        unshift @{ $self->{rx_queue} }, @{$rxq};
    } else {
        die "Unknown parameter type";
    }
}

sub _rx_no_queue {
    my ( $self, $dont_free_id ) = @_;

    my ( $type, $data ) = $self->read_packet();
    return unless defined $type;
    return $self->parse_packet( $type, $data, $dont_free_id );
}

=head2 rx

Accepts no parameters. Receives a packet from the XBee module. This packet
may be a transmission from a remote XBee node or a control packet from the
local XBee module.

If no packet is received before the timeout period expires, undef is returned.

Returned packets will be as a hashref of the packet data, broken out by key for
easy access. Note, as this module is a work in progress, not every XBee packet
type is supported. Callers should check the "api_type" key to determine the
type of the received packet.

=cut

sub rx {
    my ( $self, $dont_free_id ) = @_;

    if ( scalar( @{ $self->{rx_queue} } ) > 0 ) { return shift @{ $self->{rx_queue} }; }
    return $self->_rx_no_queue( $dont_free_id );
}

=head2 rx_frame_id

Accepts a single parameter: the frame id number to receive.

Like L<rx> but only returns the packet with the requested frame id number (or
or undef on failure).

=cut

sub rx_frame_id {
    my ( $self, $frame_id, $dont_free_id ) = @_;
    my @ignored;
    my $r;
    my $start_time = time();

    while( 1 ) {
        $r = $self->rx( $dont_free_id );
        if ( $r ) {
            if ( $r->{frame_id} && $r->{frame_id} == $frame_id ) {
                last;
            } else {
                push @ignored, $r;
            }
        }
        if ( time() - $start_time >= $self->{packet_timeout} ) {
            undef $r;
            last;
        }
    }
    if ( @ignored ) {
        $self->_unshift_rx( \@ignored );
    }
    return $r;
}

=head2 discover_network

Performs a network node discovery via the ND 'AT' command.

=cut

sub discover_network {
    my ( $self ) = @_;
    my $frame_id = $self->at('ND');
    while( $self->rx_frame_id( $frame_id, 1 ) ) { }
    $self->free_frame_id( $frame_id );
}

=head2 node_info

=cut

sub node_info {
    my ( $self, $node ) = @_;
    if ( !$node->{sn} ) { $node->{sn} = $node->{sh} . '_' . $node->{sl} }
    return $self->{known_nodes}->{$node->{sn}};
}

=head2 known_nodes

Returns a hashref of all known nodes indexed by their full serial number (AKA
$node->{sh} . '_' . $node->{sl}).  Nodes that haven't been heard from in the
configured node_forget_time will be automatically removed from this list if
they've not been heard from in that time. Nodes are added to that list when a
message is received from them or a discover_network call has been made.

Note, the age-out mechanism may be susceptable to stepping of the system clock.

=cut

sub known_nodes {
    my ( $self ) = @_;
    $self->_prune_known_nodes();
    return $self->{known_nodes};
}

sub _add_known_node {
    my ( $self, $node ) = @_;
    my $sn = $node->{sn} || ( $node->{sh} . '_' . $node->{sl} );
    $self->_prune_known_nodes();
    # Update the node in-place in case someone else is holding onto a
    # reference.
    if ( $self->{known_nodes}->{ $sn } ) {
        my $sknsn = $self->{known_nodes}->{ $sn };
        # These are the only known values that should change for a node with a
        # given serial number. The rest are burned into the chip.
        foreach my $k ( qw/ my ni profile_id / ) {
            if ( !$sknsn->{$k} || $sknsn->{$k} ne $node->{$k} ) {
                $sknsn->{$k} = $node->{$k};
            }
        }
        $sknsn->{last_seen_time} = time();
    } else {
        $node->{last_seen_time} = time();
        $self->{known_nodes}->{$sn} = $node;
    }
}

sub _prune_known_nodes {
    my ( $self ) = @_;
    my $now = time();
    my @saved_nodes;
    while( my ( $sn, $node ) = each( %{ $self->{known_nodes} } ) ) {
        if ( $now - $node->{last_seen_time} > $self->{node_forget_time} ) {
            # Set just in case a caller has held onto the reference for
            # something.
            $node->{forgotten} = 1;
            delete $self->{known_nodes}->{$sn};
        }
    }
}

=head1 CHANGES

=head2 0.2, 20101206 - jeagle

Initial release to CPAN.

=cut

1;
