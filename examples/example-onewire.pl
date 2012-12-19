#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;

#$Device::Firmata::DEBUG = 1;

our $ow_devices;

my $pin = 10;

my $device = Device::Firmata->open('/dev/ttyUSB0')
  or die "Could not connect to Firmata Server";

print "Firmware: " . $device->{metadata}{firmware} . "\n";
print "Version: " . $device->{metadata}{firmware_version} . "\n";

$device->observe_onewire( $pin, \&onOneWireMessage );
$device->pin_mode( $pin, PIN_ONEWIRE );
$device->onewire_search($pin);

while (not defined $ow_devices) {
	$device->poll();
	sleep 1;
}

for ( my $i = 0 ; $i < @$ow_devices ; $i++ ) {
	my $ds = @$ow_devices[$i];
	$device->onewire_report_config($pin,$ds,{ preReadCommand => 0x44, readDelay => 1000, readCommand => 0xbe, numBytes => 9,}); #pin,device,config
}


while (1) {
	$device->poll();
	sleep 0.1;
}

sub onOneWireMessage {
	my ( $pin, $data ) = @_;

	print(  "onOneWireMessage for pin " 
		  . $pin
		  . ", command: "
		  . $data->{command}
		  . "\n" );

  REPLY_HANDLER: {
		$data->{command} eq 'SEARCH' and do {
			$ow_devices = $data->{devices};
			if ($ow_devices) {
				print( "devices found: " . @$ow_devices . "\n" );
				for ( my $i = 0 ; $i < @$ow_devices ; $i++ ) {
					my $device      = @$ow_devices[$i];
					my $identityref = $device->{identity};
					my @identity    = @$identityref;
					my $identity;
					for ( my $i = 0 ; $i < @identity ; $i++ ) {
						$identity .= " ".uc(sprintf("%x", $identity[$i]));
					}
					print "family: "
					  . $device->{family}
					  . ", identity: "
					  . $identity
					  . ", crc: "
					  . $device->{crc} . "\n";
				}
			}
			else {
				print "devices undefined\n";
			}
			last;
		};

		$data->{command} eq 'READ' and do {
			my $device = $data->{device};
			my $bytes = $data->{data};
			for ( my $i = 0 ; $i < @$bytes ; $i++ ) {
				print " ".uc(sprintf("%x", @$bytes[$i]));
			}
			print "\n";
			my $raw = (@$bytes[1] << 8) | @$bytes[0];
			
			my $family = $device->{family};
			
			if ($family eq 0x10) {
				print "Chip = DS18S20 or old DS1820,";
    			$raw = $raw << 3; # 9 bit resolution default
    			if (@$bytes[7] == 0x10) {
	      			# count remain gives full 12 bit resolution
    	  			$raw = ($raw & 0xFFF0) + 12 - @$bytes[6];
    			}
			} elsif ($family eq 0x28 || $family eq 0x22) {
				print "Chip = DS18B20 or DS1822,";
    			my $cfg = (@$bytes[4] & 0x60);
    			if ($cfg == 0x00) {
    				$raw = $raw << 3; # 9 bit resolution, 93.75 ms
    			} elsif ($cfg == 0x20) {
    				$raw = $raw << 2; # 10 bit res, 187.5 ms
    			} elsif ($cfg == 0x40) {
    				$raw = $raw << 1; # 11 bit res, 375 ms
    			}
    			# default is 12 bit resolution, 750 ms conversion time
			} else {
				print "device: ".$family." is not a DS18x20 family device";
			}
  			my $celsius = $raw / 16.0;
  			my $fahrenheit = $celsius * 1.8 + 32.0;
			print "  Temperature = ".$celsius." Celsius, ".$fahrenheit." Fahrenheit\n\n";			
			last;
		};
	}
}
