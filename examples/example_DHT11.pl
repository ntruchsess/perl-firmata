#!/usr/bin/perl

use strict;
use warnings;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;

use constant PIN_DHT11 => 0x7e;
use constant DHT11_DATA => 0x00;

$Device::Firmata::DEBUG = 1;

my $device = Device::Firmata->open('/dev/ttyUSB0')
  or die "Could not connect to Firmata Server";

$device->observe_sysex( \&onSysexMessage, undef );
$device->observe_string( \&onStringMessage, undef );

$device->sampling_interval(1000);
$device->pin_mode( 7, PIN_DHT11 );

while (1) {
	$device->poll();
	select( undef, undef, undef, 0.1 );
}

sub onSysexMessage {
	my $sysex_message = shift;

	my $command = $sysex_message->{command};
	my $data = $sysex_message->{data};

	if (defined $command && $command == DHT11_DATA) {
		if (scalar @$data >4) {
			my $pin = shift @$data;
			my $temperature = shift @$data;
			$temperature += ((shift @$data) << 7);
			my $humidity = shift @$data;
			$humidity += ((shift @$data) << 7);
			print "pin: $pin, temperature: $temperature, humidity: $humidity\n";
		} else {
			print "not enaugh data: @$data\n";
		}
	}
}

sub onStringMessage {
	my $string = shift;
	print "string: $string\n";
}

