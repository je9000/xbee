#!/usr/local/bin/perl

use warnings;
use strict;
use lib '.';
use Device::XBee::API::Power;
use Data::Dumper;
use YAML;
use Data::Hexdumper qw/hexdump/;
use Device::SerialPort;
use IO::Select;
use IO::Socket::UNIX;
use Math::BigInt;
use Getopt::Tree;
$Getopt::Tree::SWITCH_PREFIX_STR = '';
$Data::Dumper::Useqq = 1;

use constant USERLAND_COM_SOCKET => '/tmp/xbee_power';
use constant REPLY_SIZE_LENGTH => 8;
my %pending_power_events;

my $ui_options = [
    {   name => 'help', abbr => '?', descr => 'This message.', exists => 1 },
    {   name => 'exit', descr => 'Exit.', exists => 1 },
    {
        name => 'ping',
        descr => 'Ping a node.', 
    },
    {
        name   => 'show',
        descr  => 'Show stuff.',
        exists => 1,
        params => [
            {
                name   => 'network',
                descr  => 'Show connected nodes.',
                exists => 1,
                params => [
                    {
                        name => 'discover',
                        descr => 'Initiate active network discovery.',
                        exists => 1,
                        optional => 1,
                    },
                ],
            },
            {
                name => 'clients',
                descr => 'Shows other connected clients.',
                exists => 1,
            },
        ],
    },
    {
        name   => 'switch',
        descr  => 'Set or get switch status for a given node.',
        params => [
            {
                name   => 'id',
                descr  => 'Switch id.',
                params => [
                    {
                        name => 'value',
                        descr => 'Set switch to specified value.',
                    }
                ],
            },
        ],
    },
    {
        name => 'set',
        descr => 'Set various settings.',
        exists => 1,
        params => [
            {
                name => 'unsolicited',
                descr => 'Enable or disable receiving unsolicited events.',
            },
        ]
    },
    {
        name   => 'sensor',
        descr  => 'Read sensor data for node.',
        params => [
            {
                name  => 'id',
                descr => 'Sensor id to read.',
            },
        ],
    },
];

if ( -e USERLAND_COM_SOCKET ) {
    if ( IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => USERLAND_COM_SOCKET ) ) {
        die "Process already running!";
    }
    unlink USERLAND_COM_SOCKET;
}

my $serial_port_device_path = '/dev/ttyU0';

sub init_serial {
    my ( $path ) = @_;
    my $dev = Device::SerialPort->new( $path ) || die $!;
    $dev->baudrate( 9600 );
    $dev->databits( 8 );
    $dev->stopbits( 1 );
    $dev->parity( 'none' );
    $dev->read_char_time( 0 );        # don't wait for each character
    $dev->read_const_time( 1000 );    # 1 second per unfulfilled "read" call
    return $dev;
}

my $serial_port_device = init_serial( $serial_port_device_path );

my $api = Device::XBee::API::Power->new( { fh => $serial_port_device, async => 1, packet_timeout => 10 } ) || die $!;
my $sock = IO::Socket::UNIX->new( Type => SOCK_STREAM, Local => USERLAND_COM_SOCKET, Listen => 10 ) || die $!;
my $sel = IO::Select->new( $sock, $serial_port_device->{FD} ) || die $!;
my %clients;

while ( my @ready = $sel->can_read() ) {
    foreach my $r ( @ready ) {
        my $read;
        if ( $r == $sock ) {
            my $s = $sock->accept() || next;
            $sel->add( $s );
            $s->autoflush(1);
            $clients{$s} = { unsolicited => 0, sock => $s };

        } elsif ( $r == $serial_port_device->{FD} ) {
            $read = $api->rx();
            handle_xbee_event( $read );

        } else {
            $read = <$r>;
            if ( !$read ) {
                $sel->remove( $r );
                close( $r );
                next;
            }
            eval { $read = parse_command( $read, $r ); };
            if ( $@ ) {
                reply_to_client( $r, "Exiting: $@" );
                delete $clients{$r};
                $sel->remove( $r );
                close( $r );
                next;
            }
            reply_to_client( $r, $read );
        }
    }
}

sub reply_to_client {
    my ( $c, $msg ) = @_;

    $msg = YAML::Dump( $msg );
    my $ml = length( $msg ) + 1;
    return syswrite( $c, sprintf( '%0' . REPLY_SIZE_LENGTH . "x\n%s\n", $ml, $msg ) );
}

sub sn_to_parts {
    my ( $sn ) = @_;
    return split( /_/, $sn );
}

sub handle_xbee_event {
    my ( $packet ) = @_;

    return unless $packet->{power};
    my $sent_id = Device::XBee::API::Power::__make_unacked_id( $packet->{power}->{id} );
    my $client = $pending_power_events{ $sent_id };

    if ( $client ) {
        reply_to_client( $client, { request_id => $sent_id, power => $packet->{power} } );
        delete $pending_power_events{ $sent_id };
    } else {
        my @handles = $sel->handles();
        foreach my $c ( @handles ) {
            next if $c == $sock;
            next if $c == $serial_port_device->{FD};
            next unless $clients{$c}->{unsolicited};
            reply_to_client( $client, { unsolicited => 1, power => $packet->{power} } );
        }
    }
}

sub parse_command {
    my ( $cmd, $client ) = @_;
    chomp $cmd;

    my ( $op, $config );
    my $warnings = '';
    eval {
        local $SIG{__WARN__} = sub { $warnings .= shift; };
        ( $op, $config ) = parse_command_line( $ui_options, $cmd );
    };
    if ( $warnings ) {
        return $warnings . "\nSee 'help' for usage.";

    } elsif ( !$op || $op eq 'help' ) {
        return print_usage( $ui_options, { return => 1, hide_top_line => 1 } );

    } elsif ( $op eq 'exit' ) {
        die 'exit';

    } elsif ( $op eq 'show' ) {
        if ( $config->{network} ) {
            if ( $config->{discover} ) {
                $api->discover_network();
            }
            return [ $api->known_nodes() ];
        } elsif ( $config->{clients} ) {
            return [ keys %clients ];
        }

    } elsif ( $op eq 'set' ) {
        if ( defined $config->{unsolicited} ) {
            $clients{ $client }->{unsolicited} = $config->{unsolicited} ? 1 : 0;
        }

    } elsif ( $op eq 'switch' ) {
        my ( $sh, $sl ) = sn_to_parts( $config->{switch} );
        my $t;
        if ( defined $config->{value} ) {
            $t = $api->switch_set( { sh => $sh, sl => $sl }, $config->{id}, $config->{value} );
        } else {
            $t = $api->switch_get( { sh => $sh, sl => $sl }, $config->{id} );
        }
        if ( !$t ) {
            return "Operation failed";
        } else {
            $pending_power_events{$t} = $client;
            return "Request id $t sent.";
        }

    } elsif ( $op eq 'sensor' ) {
        my ( $sh, $sl ) = sn_to_parts( $config->{sensor} );
        my $t = $api->sensor_get( { sh => $sh, sl => $sl }, $config->{id} );
        if ( !$t ) {
            return "Operation failed";
        } else {
            $pending_power_events{$t} = $client;
            return "Request id $t sent.";
        }

    } elsif ( $op eq 'ping' ) {
        my ( $sh, $sl ) = sn_to_parts( $config->{ping} );
        my $t = $api->ping( { sh => $sh, sl => $sl } );
        if ( !$t ) {
            return "Operation failed";
        } else {
            $pending_power_events{$t} = $client;
            return "Request id $t sent.";
        }
    }

    return "I don't know how to '$cmd'. Try 'help' for usage.";
}

