#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;
$Device::Firmata::DEBUG = 1;
use Time::HiRes 'sleep';

my $led_pin = 13;

my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";
$device->pin_mode($led_pin=>PIN_OUTPUT);
my $iteration = 0;
while (1) {
    my $strobe_state = $iteration++%2;
    $device->digital_write($led_pin=>$strobe_state);
    #select undef,undef,undef,1;
    sleep 0.5;
}

