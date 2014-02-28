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

$device->sampling_interval(100);
$device->encoder_attach(0,2,3);
$device->encoder_report_auto(1);

while (1) {
	$device->poll();
	select( undef, undef, undef, 0.1 );
}

sub onEncoderMessage {
	my $data = shift;
	print "encoder: $data->{encoderNum} $data->{value}\n";
}

sub onStringMessage {
	my $string = shift;
	print "string: $string\n";
}

