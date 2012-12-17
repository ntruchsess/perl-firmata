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

while (1) {
	$device->poll();
	sleep 1;
	if ( defined $ow_devices ) {
		for ( my $i = 0 ; $i < @$ow_devices ; $i++ ) {
			my $ds = @$ow_devices[$i];

			$device->onewire_reset($pin);
			$device->onewire_select( $pin, $ds );
			my @bytes =  (0x44);
			$device->onewire_write($pin, \@bytes);    # start conversion

			sleep 1;                         #maybe 750ms is enough, maybe not

		#// we might do a ds.depower() here, but the reset will take care of it.

			$device->onewire_reset($pin);
			$device->onewire_select( $pin, $ds );
			@bytes = (0xbe);
			$device->onewire_write($pin, \@bytes);    # Read Scratchpad
			$device->onewire_read( $pin, 9 );    #we need 9 bytes
		}
	}
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
						$identity .= $identity[$i];
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
			print "read data: ";
			my $bytes = $data->{data};
			for ( my $i = 0 ; $i < @$bytes ; $i++ ) {
				print @$bytes[$i];
			}
			print "\n";
			last;
		};
	}
}
