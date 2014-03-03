#!/usr/bin/perl

use strict;
use warnings;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;

#$Device::Firmata::DEBUG = 1;

my $device = Device::Firmata->open('/dev/ttyACM0')
  or die "Could not connect to Firmata Server";

$device->observe_string( \&onStringMessage, undef );
$device->observe_encoder(0, \&onEncoderMessage, undef );

$device->sampling_interval(100); # report every 100ms
$device->encoder_attach(0,2,3);  # attach encoder number 0 to pin 2 and 3
$device->encoder_report_auto(2); # report only if position has changed (set to 0 to turn of reporting, set to 1 to allways report positions (even unchanged))

while (1) {
#	$device->encoder_report_position(0); #report encoder 0 (if encoder_report_auto is set to 0)
#	$device->encoder_report_positions(); #report all encoders (if encoder_report_auto is set to 0)
	$device->poll();
	select( undef, undef, undef, 0.1 );
}

sub onEncoderMessage {
	my ($encoderNum, $value ) = @_;
	print "encoder: $encoderNum $value\n";
}

sub onStringMessage {
	my $string = shift;
	print "string: $string\n";
}

