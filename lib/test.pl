#!/usr/bin/perl

use strict;
use Data::Dumper;
use Firmata::Arduino::Tied::Constants qw/ :all /;
use Firmata::Arduino::Tied::Protocol;
use Firmata::Arduino::Tied;
$|++;

my $device = Firmata::Arduino::Tied->open('/dev/ttyUSB0');

$device->probe;

$device->pin_mode(13=>PIN_OUTPUT);

# Set the pull high value
$device->pin_mode(12=>PIN_OUTPUT);
$device->digital_write(12=>1);

# Set pin to input
$device->pin_mode(12=>PIN_INPUT);

my $iteration = 0;
while (1) {
    $device->poll;
    $device->digital_write(13=>($iteration++%2));
    select undef,undef,undef,0.1;
}

