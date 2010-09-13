#!/usr/bin/perl

use strict;
use vars qw/ $PULSE_LEN /;
use Data::Dumper;
use Firmata::Arduino::Tied::Constants qw/ :all /;
use Firmata::Arduino::Tied::Protocol;
use Firmata::Arduino::Tied;
$|++;

my $device = Firmata::Arduino::Tied->open('/dev/ttyUSB0');

$device->probe;

$PULSE_LEN = 0.1;

# Pin connection table

# cs1  - ground
# cs2  - ground
# cs3  - ground
# cs4  - ground
# osc  - ground
# sync - floating

# wr   - read/write toggle - digital 2
# rd   - clock read signal - digital 3
# data - 1 bit data.       - digital 4

$device->pin_mode(2=>PIN_OUTPUT);
$device->pin_mode(3=>PIN_OUTPUT);
$device->pin_mode(4=>PIN_OUTPUT);

wr(1);
rd(1);
data(1);

my $iteration = 0;

#$Firmata::Arduino::Tied::DEBUG = 1;

while (1) {
    $device->poll;
    matrix_write( $device, 0x10, 0x0f );
    select undef,undef,undef,0.01;
}

sub wr {
# --------------------------------------------------
    print "WR: ".($_[0])."\n";
    $device->digital_write(2=>$_[0]);
}

sub wr_pulse {
# --------------------------------------------------
    select undef, undef, undef, $PULSE_LEN;
    wr(0);
    select undef, undef, undef, $PULSE_LEN;
    wr(1);
}

sub rd {
# --------------------------------------------------
    print "RD: ".($_[0])."\n";
    $device->digital_write(3=>$_[0]);
}

sub data {
# --------------------------------------------------
    print "DATA: ".($_[0])."\n";
    $device->digital_write(4=>$_[0]);
}

sub matrix_write {
# --------------------------------------------------
    my ( $device, $address, $data ) = @_;

# 3 preamble bits 101
    data(1);
    wr_pulse();
    data(0);
    wr_pulse();
    data(1);
    wr_pulse();

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

