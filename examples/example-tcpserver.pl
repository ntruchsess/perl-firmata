#!/usr/bin/perl
#tcpserver.pl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;

$|++;
$Device::Firmata::DEBUG = 1;
use Time::HiRes 'sleep';

use constant {
	IN 	=> 3,
	OUT => 5,
	AD  => 17,
};

my $firmata = Device::Firmata->listen('192.168.0.1',3030);

my $device;

do {
	print "waiting for firmata-client to connect...\n";
} while(!($device = $firmata->accept(5)));

$device->system_reset();
$device->probe();

if ($device->{metadata}{input_pins}) {
	foreach my $pin (sort {$a <=> $b} @{$device->{metadata}{input_pins}}) {
		print "input: $pin\n";
	}
}

if ($device->{metadata}{output_pins}) {
	foreach my $pin (sort {$a <=> $b} @{$device->{metadata}{output_pins}}) {
		print "output: $pin\n";
	}
}

if ($device->{metadata}{analog_pins}) {
	foreach my $pin (sort {$a <=> $b} @{$device->{metadata}{analog_pins}}) {
		print "analog: $pin\n";
	}
}

if ($device->{metadata}{pwm_pins}) {
	foreach my $pin (sort {$a <=> $b} @{$device->{metadata}{pwm_pins}}) {
		print "pwm: $pin\n";
	}
}

$device->sampling_interval(500);
$device->pin_mode(AD,PIN_ANALOG);
$device->pin_mode(OUT,PIN_OUTPUT);
$device->pin_mode(IN,PIN_INPUT);
$device->observe_digital(IN,\&onDigitalMessage);
$device->observe_analog(AD,\&onAnalogMessage);

my $iteration = 0;
while ($iteration < 20) {
	my $strobe_state = $iteration++%2;
	$device->digital_write(OUT,$strobe_state);
	select( undef, undef, undef, 0.5 );
	$firmata->poll();
}

$firmata->close();

sub onDigitalMessage {
	my ($pin,$old,$new) = @_;
	print ("onDigitalMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--")."\n");
}

sub onAnalogMessage {
	my ($pin,$old,$new) = @_;
	print ("onAnalogMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--")."\n");
}

1;

