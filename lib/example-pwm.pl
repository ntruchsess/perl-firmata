#!/usr/bin/perl

use strict;
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;
#$Device::Firmata::DEBUG = 1;

my $led_pin = 11;

my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";
$device->pin_mode($led_pin=>PIN_PWM);
while (1) {
    for my $intensity ( 0..127 ) {
        $device->analog_write($led_pin=>$intensity*2);
        select undef,undef,undef,0.01;
    }

    for my $intensity ( 0..127) {
        $device->analog_write($led_pin=>255-$intensity*2);
        select undef,undef,undef,0.01;
    }

}

