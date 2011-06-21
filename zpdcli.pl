#!/usr/local/bin/perl

use warnings;
use strict;
use IO::Select;
use IO::Socket::UNIX;
use YAML;
use Getopt::Long;
use lib '.';
use zpdapp;

my $silent = 0;
my $exit_with;
my $exit_print;
my @commands;

sub usage {
    die "Usage:
-cmd         Command to run non-interactively. Can be set multiple times.

The following only with in non-interactive mode:

-silent      Don't print the server output.
-exit-with   Exits with the exit code of value in specified power field.
-exit-print  Before exiting, print the value in specified power field.

Exits 255 on internal error, 0 on success, or as above.
";
}

usage()
 unless GetOptions(
         'exit-with:s'  => \$exit_with,
         'exit-print:s' => \$exit_print,
         'cmd:s'        => \@commands,
         'silent'       => \$silent
 );
usage() if @ARGV;

# Dies for you.
$SIG{__DIE__} = sub { warn $_[0] unless $silent; exit 255; };
$SIG{__WARN__} = sub { warn $_[0] unless $silent; };
my $sock = zpdapp::connect_to_zpd();

# We do silly stuff if @commands/non-interactive mode was specified.
# Basically, do some trickery to make sure we wait for the whole reply (by
# exiting on the first reply that doesn't have a delay).
if ( @commands ) {
    foreach my $m ( @commands ) {
        print $sock "$m\n";
    }
} else {
    print "Connected!\n";
    $|++;
}

my $stdin = IO::Handle->new_from_fd( fileno( STDIN ), 'r' ) || die $!;
my $sel = IO::Select->new( $sock ) || die $!;
if ( !@commands ) { $sel->add( $stdin ); }

while ( my @ready = $sel->can_read() ) {
    foreach my $r ( @ready ) {
        my $read;
        if ( $r == $stdin ) {
            $read = <$stdin>;
            die unless $read;
            syswrite( $sock, $read );
        } elsif ( $r == $sock ) {
            $read = zpdapp::sysread_zpd_reply_raw( $r );
            if ( !defined $read ) {
                die "Read error (protocol mismatch?)";
            } else {
                if ( !$silent ) {
                    $read =~ s/\n+\z/\n/;
                    print $read;
                }
            }

            if ( @commands ) {
                $read = YAML::Load( $read );
                if ( ref $read eq 'HASH' && !exists $read->{id} ) {
                    if ( !defined $exit_with && !defined $exit_print ) { exit 0; }
                    if ( !ref $read->{power} eq 'HASH' ) { exit 255; }
                    if ( defined $exit_print && defined $read->{power}->{$exit_print} ) {
                        print $read->{power}->{$exit_print}, "\n";
                    }
                    if ( !defined $exit_with ) { exit 0; }
                    if (   defined $read->{power}->{$exit_with}
                        && $read->{power}->{$exit_with} =~ /^\d+$/
                        && $read->{power}->{$exit_with} < 256 )
                    {
                        exit $read->{power}->{$exit_with};
                    }
                    exit 255;    # Something went wrong with exit_with
                } elsif ( ref $read ne 'HASH' ) {
                    # Don't know what else we would do with these types...
                    exit 0;
                }
            }

        } else {
            die "??";
        }
    }
}
