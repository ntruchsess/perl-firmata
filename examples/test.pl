#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;

my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";

$device->probe;

die Dumper $device;

#$device->pin_mode(13=>PIN_OUTPUT);

# Set the pull high value
#$device->pin_mode(12=>PIN_OUTPUT);
#$device->digital_write(12=>1);

# Set pin to input
#$device->pin_mode(12=>PIN_INPUT);

# Set PWM pin
#$device->pin_mode(3=>PIN_PWM);

# Set Analog pin
$device->pin_mode(1=>PIN_ANALOG);

my $iteration = 0;

#$Device::Firmata::DEBUG = 1;

while (1) {
    $device->poll;
    print $device->analog_read(1)."\n";
#    my $strobe_state = $iteration++%2;
#    $device->digital_write(13=>$strobe_state);
#    $device->analog_write(3=>( $iteration % 256 ) );
    select undef,undef,undef,0.01;
}

