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
use Getopt::Long;
use zpd_lib;
$Getopt::Tree::SWITCH_PREFIX_STR = '';
$Data::Dumper::Useqq = 1;

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
            {
                name => 'aliases',
                descr => 'Shows configured node aliases.',
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

my $node_aliases;
{
    my $node_alias_file;
    GetOptions( 'node-alias-file=s' => \$node_alias_file );
    if ( $node_alias_file ) {
        $node_aliases = YAML::LoadFile( $node_alias_file ) || die "Failed to read node alias file: $!";
        if ( ref $node_aliases ne 'HASH' ) { die "Node alias file appears invalid."; }
        foreach my $n ( keys( %{ $node_aliases } ) ) {
            if ( $n =~ /^\d+_\d+$/ ) {
                warn "Node alias $n looks like an address, this is probably a bad idea.";
                if ( ( $node_aliases->{$n} ne 'HASH' )
                     || ( !defined $node_aliases->{$n}->{addr_h} )
                     || ( $node_aliases->{$n}->{addr_h} !~ /^\d+$/ ) 
                     || ( !defined $node_aliases->{$n}->{addr_l} )
                     || ( $node_aliases->{$n}->{addr_l} !~ /^\d+$/ ) 
                ) {
                    die "Node alias for $n appears to have missing or invalid address data";
                }
            }
        }
    }
}

if ( -e zpd_lib::COM_SOCKET_PATH ) {
    if ( IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => zpd_lib::COM_SOCKET_PATH ) ) {
        die "Process already running!";
    }
    unlink zpd_lib::COM_SOCKET_PATH;
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
my $sock = IO::Socket::UNIX->new( Type => SOCK_STREAM, Local => zpd_lib::COM_SOCKET_PATH, Listen => 10 ) || die $!;
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
                zpd_lib::syswrite_zpd_reply( $r, "Exiting: $@" );
                delete $clients{$r};
                $sel->remove( $r );
                close( $r );
                next;
            }
            zpd_lib::syswrite_zpd_reply( $r, $read );
        }
    }
}

sub sn_or_alis_to_addrs {
    my ( $sn ) = @_;
    if ( $node_aliases->{$sn} ) {
        return $node_aliases->{$sn}->{addr_h}, $node_aliases->{$sn}->{addr_l};
    }
    if ( $sn !~ /^\d+_\d+$/ ) { return; }
    return split( /_/, $sn );
}

sub handle_xbee_event {
    my ( $packet ) = @_;

    return unless $packet->{power};
    my $sent_id = Device::XBee::API::Power::__make_unacked_id( $packet->{power}->{id} );
    my $client = $pending_power_events{ $sent_id };

    if ( $client ) {
        zpd_lib::syswrite_zpd_reply( $client, { request_id => $sent_id, power => $packet->{power} } );
        delete $pending_power_events{ $sent_id };
    } else {
        my @handles = $sel->handles();
        foreach my $c ( @handles ) {
            next if $c == $sock;
            next if $c == $serial_port_device->{FD};
            next unless $clients{$c}->{unsolicited};
            zpd_lib::syswrite_zpd_reply( $client, { unsolicited => 1, power => $packet->{power} } );
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
        } elsif ( $config->{aliases} ) {
            return $node_aliases;
        }

    } elsif ( $op eq 'set' ) {
        if ( defined $config->{unsolicited} ) {
            $clients{ $client }->{unsolicited} = $config->{unsolicited} ? 1 : 0;
        }

    } elsif ( $op eq 'switch' ) {
        my ( $sh, $sl ) = sn_or_alis_to_addrs( $config->{switch} );
        return "Invalid target" unless defined $sl;
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
        my ( $sh, $sl ) = sn_or_alis_to_addrs( $config->{sensor} );
        return "Invalid target" unless defined $sl;
        my $t = $api->sensor_get( { sh => $sh, sl => $sl }, $config->{id} );
        if ( !$t ) {
            return "Operation failed";
        } else {
            $pending_power_events{$t} = $client;
            return "Request id $t sent.";
        }

    } elsif ( $op eq 'ping' ) {
        my ( $sh, $sl ) = sn_or_alis_to_addrs( $config->{ping} );
        return "Invalid target" unless defined $sl;
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

