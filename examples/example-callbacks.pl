#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;
#$Device::Firmata::DEBUG = 1;

my $led_pin = 11;
my $input_pin = 2; #for testing physically connect pin 11 to pin 2 (and / or pin 0)
my $analog_pin = 0;

my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";

printf "   Firmware name: %s\n",$device->{metadata}{firmware};
printf "Firmware version: %s\n",$device->{metadata}{firmware_version};

do { $device->{protocol}->{protocol_version} = $_ if $device->{metadata}{firmware_version} eq $_ } foreach keys %$COMMANDS;
printf "Protocol version: %s\n",$device->{protocol}->{protocol_version};

$device->pin_mode($led_pin=>PIN_OUTPUT);
$device->pin_mode($input_pin=>PIN_INPUT);
$device->pin_mode($analog_pin=>PIN_ANALOG);
$device->observe_digital($input_pin,\&onDigitalMessage);
$device->observe_analog($analog_pin,\&onAnalogMessage);
$device->sampling_interval(200);

my $iteration = 0;
while (1) {
    my $strobe_state = $iteration++%2;
    $device->digital_write($led_pin=>$strobe_state);
    for (my $i=0;$i<10;$i++) {
    	$device->poll;
    	select undef,undef,undef,0.1;
    }
}

sub onDigitalMessage {
	my ($pin,$old,$new) = @_;
	print ("onDigitalMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--")."\n");
}

sub onAnalogMessage {
	my ($pin,$old,$new) = @_;
	print ("onAnalogMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--")."\n");
}
