#!/usr/local/bin/perl

use warnings;
use strict;
use POSIX;
use Data::Dumper;
use YAML;
use Data::Hexdumper qw/hexdump/;
use Device::SerialPort;
use IO::Select;
use IO::Socket::UNIX;
use Getopt::Tree;
use Getopt::Long;
use lib '.';
use Device::XBee::API::Power;
use zpdapp;
$Getopt::Tree::SWITCH_PREFIX_STR = '';
$Data::Dumper::Useqq             = 1;

my %pending_power_events;
my $sock;

sub on_exit {
    if ( $sock ) {
        unlink zpdapp::COM_SOCKET_PATH;
    }
    exit 2;
}

$SIG{INT}  = \&on_exit;
$SIG{TERM} = \&on_exit;
$SIG{PIPE} = 'IGNORE';

my $ui_options = [
    { name => 'help',  abbr  => '?',     descr  => 'This message.', exists => 1 },
    { name => 'exit',  descr => 'Exit.', exists => 1 },
    { name => 'ping',  descr => 'Ping a node.', },
    { name => 'query', descr => 'Query a node\'s power API details.', },
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
                        name     => 'discover',
                        descr    => 'Initiate active network discovery.',
                        exists   => 1,
                        optional => 1,
                    },
                ],
            },
            {
                name   => 'clients',
                descr  => 'Shows other connected clients.',
                exists => 1,
            },
            {
                name   => 'aliases',
                descr  => 'Shows configured node aliases.',
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
                        name     => 'value',
                        descr    => 'Set switch to specified value.',
                        optional => 1,
                    }
                ],
            },
        ],
    },
    {
        name   => 'set',
        descr  => 'Set various settings.',
        exists => 1,
        params => [
            {
                name  => 'unsolicited',
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
my $do_daemon;
{
    my $node_alias_file;
    die unless GetOptions( 'node-alias-file:s' => \$node_alias_file, 'daemon' => \$do_daemon );
    if ( $node_alias_file ) {
        $node_aliases = YAML::LoadFile( $node_alias_file ) || die "Failed to read node alias file: $!";
        if ( ref $node_aliases ne 'HASH' ) { die "Node alias file appears invalid."; }
        foreach my $n ( keys( %{$node_aliases} ) ) {
            if ( $n =~ /^\d+_\d+$/ ) {
                warn "Node alias $n looks like an address, this is probably a bad idea.";
                if (   ( $node_aliases->{$n} ne 'HASH' )
                    || ( !defined $node_aliases->{$n}->{addr_h} )
                    || ( $node_aliases->{$n}->{addr_h} !~ /^\d+$/ )
                    || ( !defined $node_aliases->{$n}->{addr_l} )
                    || ( $node_aliases->{$n}->{addr_l} !~ /^\d+$/ ) )
                {
                    die "Node alias for $n appears to have missing or invalid address data";
                }
            }
        }
    } else {
        $node_aliases = {};
    }
}

if ( -e zpdapp::COM_SOCKET_PATH ) {
    if ( IO::Socket::UNIX->new( Type => SOCK_STREAM, Peer => zpdapp::COM_SOCKET_PATH ) ) {
        die "Process already running!";
    }
    unlink zpdapp::COM_SOCKET_PATH;
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
umask 0117;
$sock = IO::Socket::UNIX->new( Type => SOCK_STREAM, Local => zpdapp::COM_SOCKET_PATH, Listen => 10 ) || die $!;
my $sel = IO::Select->new( $sock, $serial_port_device->{FD} ) || die $!;
my %clients;

make_daemon() if $do_daemon;

while ( my @ready = $sel->can_read() ) {
    foreach my $r ( @ready ) {
        my $read;
        if ( $r == $sock ) {
            my $s = $sock->accept() || next;
            $sel->add( $s );
            $s->autoflush( 1 );
            $clients{$s} = { unsolicited => 0, sock => $s, connected_time => time() };

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
            if ( !defined eval { $read = parse_command( $read, $r ); return 42; } ) {
                zpdapp::syswrite_zpd_reply( $r, { exiting => $@ } );
                delete $clients{$r};
                $sel->remove( $r );
                close( $r );
                next;
            }
            zpdapp::syswrite_zpd_reply( $r, $read );
        }
    }
}

die "Should not be here!";

sub sn_or_alias_to_addrs {
    my ( $sn ) = @_;
    if ( $node_aliases->{$sn} ) {
        return $node_aliases->{$sn}->{sh}, $node_aliases->{$sn}->{sl};
    }
    if ( $sn !~ /^\d+_\d+$/ ) { return; }
    return split( /_/, $sn );
}

sub handle_xbee_event {
    my ( $packet ) = @_;

    return unless $packet->{power};
    my $sent_id = Device::XBee::API::Power::__make_unacked_id( $packet->{power}->{id} );
    my $client  = $pending_power_events{$sent_id};

    if ( $client ) {
        zpdapp::syswrite_zpd_reply( $client, { request_id => $sent_id, power => $packet->{power} } );
        delete $pending_power_events{$sent_id};
    } else {
        my @handles = $sel->handles();
        foreach my $c ( @handles ) {
            next if $c == $sock;
            next if $c == $serial_port_device->{FD};
            next unless $clients{$c}->{unsolicited};
            zpdapp::syswrite_zpd_reply( $client, { unsolicited => 1, power => $packet->{power} } );
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
        return { error => "Syntax error:\n$warnings\nSee 'help' for usage." };
    }

    # Caller will disconnect client if we die in this function.
    if ( defined $op && $op eq 'exit' ) { die; }

    my $success = eval {
        # Remove the line number from the error message to be pretty.
        local $SIG{__DIE__} = sub {
            my ( $m ) = @_;
            $m =~ s/ at .+ line \d+\.\z//;
            die $m;
        };
        if ( !$op ) {
            die print_usage( $ui_options, { return => 1, hide_top_line => 1 } );

        } elsif ( $op eq 'help' ) {
            return { usage => print_usage( $ui_options, { return => 1, hide_top_line => 1 } ) };

        } elsif ( $op eq 'show' ) {
            if ( $config->{network} ) {
                if ( $config->{discover} ) {
                    $api->discover_network();
                }
                my $h = $api->known_nodes();
                foreach my $n ( values( %{$h} ) ) {
                    foreach my $alias ( keys( %{$node_aliases} ) ) {
                        if (   ( $n->{sh} eq $node_aliases->{$alias}->{sh} )
                            && ( $n->{sl} eq $node_aliases->{$alias}->{sl} ) )
                        {
                            $n->{alias} = $alias;
                            last;
                        }
                    }
                }
                return { known_nodes => $h };
            } elsif ( $config->{clients} ) {
                my %c;
                while ( my ( $client_sock, $client_data ) = each( %clients ) ) {
                    $c{"$client_sock"} = {};
                    while ( my ( $k, $v ) = each( %{$client_data} ) ) {
                        if ( $k eq 'sock' ) {
                            $c{"$client_sock"}->{$k} = 'socket';
                        } else {
                            $c{"$client_sock"}->{$k} = $v;
                        }
                    }
                }
                return { clients => \%c };
            } elsif ( $config->{aliases} ) {
                return $node_aliases;
            }

        } elsif ( $op eq 'set' ) {
            if ( defined $config->{unsolicited} ) {
                $clients{$client}->{unsolicited} = $config->{unsolicited} ? 1 : 0;
            }
            return { unsolicited => $clients{$client}->{unsolicited} };

        } elsif ( $op eq 'switch' ) {
            my ( $sh, $sl ) = sn_or_alias_to_addrs( $config->{switch} );
            die "Invalid target" unless defined $sl;
            my $t;
            if ( defined $config->{value} ) {
                $t = $api->switch_set( { sh => $sh, sl => $sl }, $config->{id}, $config->{value} );
            } else {
                $t = $api->switch_get( { sh => $sh, sl => $sl }, $config->{id} );
            }
            if ( !$t ) {
                die "Operation failed";
            } else {
                $pending_power_events{$t} = $client;
                return { tx_id => $t };
            }

        } elsif ( $op eq 'sensor' ) {
            my ( $sh, $sl ) = sn_or_alias_to_addrs( $config->{sensor} );
            die "Invalid target" unless defined $sl;
            my $t = $api->sensor_get( { sh => $sh, sl => $sl }, $config->{id} );
            if ( !$t ) {
                die "Operation failed";
            } else {
                $pending_power_events{$t} = $client;
                return { tx_id => $t };
            }

        } elsif ( $op eq 'ping' ) {
            my ( $sh, $sl ) = sn_or_alias_to_addrs( $config->{ping} );
            die "Invalid target" unless defined $sl;
            my $t = $api->ping( { sh => $sh, sl => $sl } );
            if ( !$t ) {
                die "Operation failed";
            } else {
                $pending_power_events{$t} = $client;
                return { tx_id => $t };
            }

        } elsif ( $op eq 'query' ) {
            my ( $sh, $sl ) = sn_or_alias_to_addrs( $config->{query} );
            die "Invalid target" unless defined $sl;
            my $t = $api->query( { sh => $sh, sl => $sl } );
            if ( !$t ) {
                die "Operation failed";
            } else {
                $pending_power_events{$t} = $client;
                return { tx_id => $t };
            }
        }

        die "I don't know how to '$cmd'. Try 'help' for usage.";
    };

    if ( !defined $success ) {
        return { error => $@ };
    }
    if ( ref $success eq '' || ref $success ne 'HASH' || exists $success->{error} ) { die "This doesn't seem right"; }
    return $success;
}

sub make_daemon {
    eval {
        chdir( '/' ) or die( "Can't chdir to /: $!" );
        defined( my $pid = fork() ) or die( "Can't fork: $!" );
        if ( $pid ) {
            exit( 0 );
        }
        setsid() or die( "Can't start a new session: $!" );
        open( STDIN,  '</dev/null' ) or die( "Can't read /dev/null: $!" );
        open( STDOUT, '>/dev/null' ) or die( "Can't write to /dev/null: $!" );
        open( STDERR, '>/dev/null' ) or die( "Can't write to /dev/null: $!" );
    };
    if ( $@ ) {
        warn $@;
        exit( 2 );
    }
}

