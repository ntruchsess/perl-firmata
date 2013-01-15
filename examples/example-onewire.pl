#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;

$Device::Firmata::DEBUG = 1;

our $ow_devices;

my $pin = 10;

my $device = Device::Firmata->open('/dev/ttyUSB0')
  or die "Could not connect to Firmata Server";

for ( my $j = 0 ; $j < 20 ; $j++ ) {
	sleep 0.1;
	$device->poll();
}

print "Firmware: " . $device->{metadata}{firmware} . "\n";
print "Version: " . $device->{metadata}{firmware_version} . "\n";

for ( my $j = 0 ; $j < 20 ; $j++ ) {
	sleep 0.2;
	$device->poll();
}

$device->observe_onewire( $pin, \&onOneWireMessage );
$device->observe_scheduler( \&onSchedulerMessage );

#while (1) {
#	$device->poll();
#	sleep 0.1;
#}

$device->pin_mode( $pin, PIN_ONEWIRE );

$device->onewire_search($pin);

while ( ( not defined $ow_devices ) or ( @$ow_devices < 2 ) ) {
	$device->poll();
	sleep 1;
}

#while (1) {
#for ( my $i = 0 ; $i < @$ow_devices ; $i++ ) {
#	$device->onewire_reset($pin);
#	$device->onewire_select( $pin, @$ow_devices[$i] );
#	$device->onewire_write( $pin, 0x44 );
#}
#
#sleep 1;
#
#for ( my $i = 0 ; $i < @$ow_devices ; $i++ ) {
#	$device->onewire_reset($pin);
#	$device->onewire_select( $pin, @$ow_devices[$i] );
#	$device->onewire_write( $pin, 0xBE );
#	$device->onewire_read( $pin, 9 );
#}
#
#for ( my $i = 0 ; $i < 5 ; $i++ ) {
#	sleep 1;
#	$device->poll;
#}
#}

#print ("now using scheduling\n");

$device->scheduler_reset();
my $taskid0 = $device->scheduler_create_task();

#$args = {
#	reset => undef | 1,
#	skip => undef | 1,
#	select => undef | device,
#	read => undef | short int,
#	delay => undef | long int,
#	write => undef | bytes[],
#}

$device->scheduler_add_to_task( $taskid0,
	$device->{protocol}->packet_onewire_request($pin , {
		reset => 1,
		select => @$ow_devices[0],
		write => [0x44],
		delay => 800,
	}) );
$device->scheduler_add_to_task( $taskid0,
	$device->{protocol}->packet_onewire_request($pin , {
		reset => 1,
		select => @$ow_devices[0],
		write => [0xBE],
		read => 9,
		delay => 1200,
	}) );
print "schedule taskid: ".$taskid0."\n";
$device->scheduler_schedule_task( $taskid0, 0 );
	
my $taskid1 = $device->scheduler_create_task();
$device->scheduler_add_to_task( $taskid1,
	$device->{protocol}->packet_onewire_request($pin , {
		reset => 1,
		select => @$ow_devices[1],
		write => [0x44],
		delay => 800,
	}) );
$device->scheduler_add_to_task( $taskid1,
	$device->{protocol}->packet_onewire_request($pin , {
		reset => 1,
		select => @$ow_devices[1],
		write => [0xBE],
		read => 9,
		delay => 1200,
	}) );
print "schedule taskid: ".$taskid1."\n";
$device->scheduler_schedule_task( $taskid1, 0 );

while (1) {
	for (my $i=0;$i<50;$i++) {
		$device->poll();
		select(undef,undef,undef,0.1);
	}
	$device->scheduler_query_all_tasks();
	$device->scheduler_query_task($taskid0);
	$device->scheduler_query_task($taskid1);
}

sub onOneWireMessage {
	my ( $pin, $data ) = @_;

	print(  "onOneWireMessage for pin " 
		  . $pin
		  . ", command: "
		  . $data->{command}
		  . "\n" );

  REPLY_HANDLER: {
		$data->{command} eq 'SEARCH_REPLY' and do {
			$ow_devices = $data->{devices};
			if ($ow_devices) {
				print( "devices found: " . @$ow_devices . "\n" );
				for ( my $i = 0 ; $i < @$ow_devices ; $i++ ) {
					my $device      = @$ow_devices[$i];
					my $identityref = $device->{identity};
					my @identity    = @$identityref;
					my $identity;
					for ( my $i = 0 ; $i < @identity ; $i++ ) {
						$identity .= " " . uc( sprintf( "%x", $identity[$i] ) );
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

		$data->{command} eq 'READ_REPLY' and do {
			my $device = $data->{device};
			my $bytes  = $data->{data};
			for ( my $i = 0 ; $i < @$bytes ; $i++ ) {
				print " " . uc( sprintf( "%x", @$bytes[$i] ) );
			}
			print "\n";
			my $raw = ( @$bytes[1] << 8 ) | @$bytes[0];

			my $family = $device->{family};

			if ( $family eq 0x10 ) {
				print "Chip = DS18S20 or old DS1820,";
				$raw = $raw << 3;    # 9 bit resolution default
				if ( @$bytes[7] == 0x10 ) {

					# count remain gives full 12 bit resolution
					$raw = ( $raw & 0xFFF0 ) + 12 - @$bytes[6];
				}
			}
			elsif ( $family eq 0x28 || $family eq 0x22 ) {
				print "Chip = DS18B20 or DS1822,";
				my $cfg = ( @$bytes[4] & 0x60 );
				if ( $cfg == 0x00 ) {
					$raw = $raw << 3;    # 9 bit resolution, 93.75 ms
				}
				elsif ( $cfg == 0x20 ) {
					$raw = $raw << 2;    # 10 bit res, 187.5 ms
				}
				elsif ( $cfg == 0x40 ) {
					$raw = $raw << 1;    # 11 bit res, 375 ms
				}

				# default is 12 bit resolution, 750 ms conversion time
			}
			else {
				print "device: " . $family . " is not a DS18x20 family device";
			}
			my $celsius    = $raw / 16.0;
			my $fahrenheit = $celsius * 1.8 + 32.0;
			print "  Temperature = " 
			  . $celsius
			  . " Celsius, "
			  . $fahrenheit
			  . " Fahrenheit\n\n";
			last;
		};
	}
}

sub onSchedulerMessage {
	my ($data) = @_;

  COMMAND_HANDLER: {

		$data->{command} eq 'QUERY_ALL_TASKS_REPLY' and do {
			my $taskids = $data->{ids};
			print "QueryAllTasksReply: taskids=[";
			while (@$taskids) {
				my $taskid = shift @$taskids; 
				print $taskid.", ";
			}
			print "]\n";
			last;
		};

		($data->{command} eq 'QUERY_TASK_REPLY' or $data->{command} eq 'ERROR_TASK_REPLY') and do {

			if ($data->{command} eq 'QUERY_TASK_REPLY') {
				print "QueryTaskReply: taskid=" . $data->{id};
			} else {
				print "ErrorTaskReply: taskid=" . $data->{id};
			}
			if ( defined $data->{time_ms} ) {
				print ", time_ms="
				  . $data->{time_ms}
				  . ", len="
				  . $data->{len}
				  . ", position="
				  . $data->{position} . "\n";
				print "messages: ";
				my $messages = $data->{messages};
				while (@$messages) {
					my $message = shift @$messages;
					printf "%02x,", $message;
				}
				print "\n";
			}
			else {
				print " is undefined\n";
			}
		};
	}
}

sub encode {
	my @data = @_;
	my @outdata;
	my $numBytes    = @data;
	my $messageSize = ( $numBytes << 3 ) / 7;
	for ( my $i = 0 ; $i < $messageSize ; $i++ ) {
		my $j     = $i * 7;
		my $pos   = $j >> 3;
		my $shift = $j & 7;
		my $out   = $data[$pos] >> $shift & 0x7F;

		if ( $out >> 7 > 0 ) {
			printf "%b, %b, %d\n", $data[$pos], $out, $shift;
		}

		if ( $shift > 1 && $pos < $numBytes - 1 ) {
			$out |= ( $data[ $pos + 1 ] << ( 8 - $shift ) ) & 0x7F;
		}
		push( @outdata, $out );
	}
	return @outdata;
}

sub decode {
	my @data = @_;
	my @outdata;
	my $numBytes = @data;
	my $outBytes = ( $numBytes * 7 ) >> 3;
	for ( my $i = 0 ; $i < $outBytes ; $i++ ) {
		my $j     = $i << 3;
		my $pos   = $j / 7;
		my $shift = $j % 7;
		push( @outdata,
			( $data[$pos] >> $shift ) |
			  ( ( $data[ $pos + 1 ] << ( 7 - $shift ) ) & 0xFF ) );
	}
	return @outdata;
}
