#!/usr/bin/perl

use strict;
use lib '../lib';
use vars qw/ $PULSE_LEN $PIN_LOOKUP /;
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

while (1) {
    # Wipe the screen
    cs1_pulse_inv();
    preamble_send($device,"101");
    data_send($device,"0000000"); # address (MA)
    for (1..64) {
        data_send($device,"0000"); # data (MA)
    }

    # Turn on the screen
    cs1_pulse_inv();
    preamble_send($device,"101");
    data_send($device,"0000000"); # address (MA)
    for (1..64) {
        data_send($device,"1111"); # data (MA)
    }
}


cs1(1);


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

