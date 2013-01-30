#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;

$Device::Firmata::DEBUG = 1;

my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";
$device->system_reset();
$device->probe();

# die Dumper $device;

$device->observe_digital(12,\&onDigitalMessage,"context");

# Set pin to output
$device->pin_mode(11,PIN_OUTPUT);

# Set pin to input
$device->pin_mode(12,PIN_INPUT);
$device->pin_mode(15,PIN_ANALOG);
$device->sampling_interval(500);

my $iteration = 0;

while (1) {
    $device->poll;
    my $strobe_state = $iteration++%2;
    $device->digital_write(11,$strobe_state);
    print $device->digital_read(12)."\n";
    select undef,undef,undef,0.5;
}

sub onDigitalMessage
{
	my ($pin,$old,$new,$hash) = @_;
	print ("onDigitalMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--").", context: ".$hash."\n");
}
