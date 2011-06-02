#!/usr/local/bin/perl

use strict;
use warnings;
use Getopt::Tree;
use lib '.';
use zpapp;

my $params = [
    {
        name => 'sensor',
        descr => 'Read a sensor on this node.',
        params => [
            {
                name => 'id',
                descr => 'Sensor ID to read.',
            },
        ],
    },
    {
        name => 'switch',
        descr => 'Read or set a switch on this node.',
        params => [
            {
                name => 'id',
                descr => 'Switch ID to read or set.',
                params => [
                    {
                        name => 'to',
                        descr => 'New switch value: 1, 0, momentary, toggle.',
                        optional => 1,
                    },
                ],
            },
        ],
    },
];

my ( $command, $config ) = parse_command_line( $params );
die print_usage( $params ) unless $command;
my $zp = zpapp->new() || die;


