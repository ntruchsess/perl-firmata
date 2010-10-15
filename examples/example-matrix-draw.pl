#!/usr/bin/perl

use strict;
use lib '../lib';
use vars qw/ $PULSE_LEN $PIN_LOOKUP $CHARMAP /;
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::Protocol;
use Device::Firmata;

use constant ($PIN_LOOKUP={
    CS1  => 5,
    CS2  => 6,
    CS3  => 7,
    CS4  => 8,

    WR   => 2,
    RD   => 3,
    DATA => 4,

    FONT_PARSER_WAITING  => 0,
    FONT_PARSER_METADATA => 1,
    FONT_PARSER_BITMAP   => 2,
});

#$Device::Firmata::DEBUG = 1;
$PULSE_LEN = 0.001;

$|++;

my $device = Device::Firmata->open('/dev/ttyUSB0');

# Pin connection table

# cs1  - digital 5
# cs2  - digital 6
# cs3  - digital 7
# cs4  - digital 8
# osc  - ground
# sync - floating

# wr   - read/write toggle - digital 2
# rd   - clock read signal - digital 3
# data - 1 bit data.       - digital 4

# Create all the functions that we'll use to play with the pins
no strict 'refs';
while ( my ($name,$pin) = each %$PIN_LOOKUP ) {
    $device->pin_mode($pin=>,PIN_OUTPUT);
    my $lc_name = lc $name;
    my $lc_sub = *{"::".$lc_name} = sub { 
        print "$name is $_[0]\n";
        $device->digital_write($pin=>$_[0]);
        select undef, undef, undef, $PULSE_LEN;
    };
    *{"::".$lc_name."_pulse"} = sub { 
        print "Pulsing: $name\n";
        $device->digital_write($pin=>0);
        select undef, undef, undef, $PULSE_LEN;
        $device->digital_write($pin=>1);
        select undef, undef, undef, $PULSE_LEN;
    };
    *{"::".$lc_name."_pulse_inv"} = sub { 
        print "Pulsing: $name\n";
        $device->digital_write($pin=>1);
        select undef, undef, undef, $PULSE_LEN;
        $device->digital_write($pin=>0);
        select undef, undef, undef, $PULSE_LEN;
    };

}
use strict;

# Now let's initialize firmata
$device->probe;

# Set all pins high since that seems to be the default state
cs1(1);
wr(1);
rd(1);
data(1);

# Disable the unit
cs1(0);
preamble_send($device,"100");
data_send($device,"000000000");

# Turn on the LEDs
cs1_pulse_inv();
preamble_send($device,"100");
data_send($device,"000000111");

# Turn on system oscillator
cs1_pulse_inv();
preamble_send($device,"100");
data_send($device,"000000011");

# Commons option
cs1_pulse_inv();
preamble_send($device,"100");
data_send($device,"001010111");

# Init the matrix!
matrix_init($device);

# Draw a line?
for my $x ( 0..31 ) {
    my $y = int($x/31*7);
    matrix_set_pixel( $x, $y, 1 );
    matrix_commit($device);
}

# Draw a sine curve
for my $x (0..31) {
    my $y = int(4+sin($x/3)*4);
    matrix_set_pixel( $x, $y, 1 );
    matrix_commit($device);
}


sub preamble_send {
# --------------------------------------------------
    my ( $device, $data ) = @_;
    my $buf = substr $data, 0, 3;
    for my $d (split //, $buf) {
        data($d);
        wr_pulse();
    }
}

sub data_send {
# --------------------------------------------------
    my ( $device, $data ) = @_;
    for my $d (split //, $data) {
        data($d);
        wr_pulse();
    }
}

sub data_send_int {
# --------------------------------------------------
    my ( $device, $v, $bits, $offset ) = @_;
    $bits ||= 8;
    if ( not defined $offset ) {
        $offset ||= 8-$bits;
    }
    my $data = substr unpack( "B*", pack "c", $v ), $offset, $bits;
    print "V <$v> BITS: $bits SENDING: $data\n";

    data_send($device,$data);
}

my @matrix_current = map {0} (1..32);
my @matrix_pending = map {0} (1..32);

sub matrix_init {
# --------------------------------------------------
    my ( $device ) = @_;

# Wipe the screen
    cs1_pulse_inv();
    preamble_send($device,"101");
    data_send($device,"0000000"); # address (MA)
    for (1..64) {
        data_send($device,"0000"); # data (MA)
    }

# Wipe the arrays
    @matrix_current = map {0} (1..32);
    @matrix_pending = map {0} (1..32);
}

sub matrix_write {
# --------------------------------------------------
    my ( $device, $address, $data ) = @_;

# 3 preamble bits 101
    preamble(qw( 1 0 1 ));

# Then the address, which is 7 bits
    for my $i ( 0..6 ) {
        data($address & 0x40);
        wr_pulse();
        $address <<= 1;
    }

# And then the 4 bits of data
    for my $i ( 0..3 ) {
        data($data & 0x01);
        wr_pulse();
        $address >>= 1;
    }
}

sub matrix_set_pixel {
# --------------------------------------------------
    my ( $x, $y, $on ) = @_;
    if ( $on ) {
        $matrix_pending[$x] |= 1<<$y;
    }
    else {
        $matrix_pending[$x] &= ~(1<<$y);
    }
}

sub matrix_get_pixel {
# --------------------------------------------------
    my ( $x, $y ) = @_;
    return ( $matrix_pending[$x] & (1<<$y) );
}

sub matrix_commit {
# --------------------------------------------------
# Only update the memory that requires refreshing
#
    my ( $device ) = @_;

    for my $i (0..31) {
        my $diff = $matrix_current[$i] ^ $matrix_pending[$i];
        my $v    = $matrix_current[$i] = $matrix_pending[$i];

# Low nybble
        if ( $diff & 0x0f ) {
        print "LOW $i: DIFF: $diff V: $v\n";

            cs1_pulse_inv();
            preamble_send($device,"101");
            data_send_int($device,$i*2+1,7); # address (MA)
            data_send_int($device,$v,4);
        }

# High nybble
        if ( $diff & 0xf0 ) {
        print "HIGH $i: DIFF: $diff V: $v\n";

            cs1_pulse_inv();
            preamble_send($device,"101");
            data_send_int($device,$i*2,7); # address (MA)
            data_send_int($device,$v,4,0);
        }
    }
}

sub matrix_dump {
# --------------------------------------------------
    for my $i ( 0..31 ) {
        printf "%02i: %s\n", $i, $matrix_pending[$i];
    }
}

sub matrix_clear {
# --------------------------------------------------
    for my $i (0..31) {
        $matrix_pending[$i] = 0;
    };
}


