package Device::Firmata::Protocol;

=head1 NAME 

Device::Firmata::Protocol - details of the actual firmata protocol

=cut

use strict;
use warnings;
use vars qw/ $MIDI_DATA_SIZES /;

use constant {
	MIDI_COMMAND      => 0x80,
	MIDI_PARSE_NORMAL => 0,
	MIDI_PARSE_SYSEX  => 1,
	MIDI_START_SYSEX  => 0xf0,
	MIDI_END_SYSEX    => 0xf7,
};

use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::Base
  ISA             => 'Device::Firmata::Base',
  FIRMATA_ATTRIBS => {
	buffer           => [],
	parse_status     => MIDI_PARSE_NORMAL,
	protocol_version => 'V_2_01',
  };

$MIDI_DATA_SIZES = {
	0x80 => 2,
	0x90 => 2,
	0xA0 => 2,
	0xB0 => 2,
	0xC0 => 1,
	0xD0 => 1,
	0xE0 => 2,
	0xF0 => 0,    # note that this requires special handling

	# Special for version queries
	0xF4 => 2,
	0xF9 => 2,

	0x79 => 0,
	0x7A => 2,
};

our $ONE_WIRE_COMMANDS = {
	SEARCH           => 0,
	SKIP_AND_WRITE   => 1,
	SKIP_AND_READ    => 2,
	SELECT_AND_WRITE => 3,
	SELECT_AND_READ  => 4,
	READ             => 5,
	CONFIG           => 6,
	REPORT_CONFIG    => 7,
};

=head1 DESCRIPTION

Because we're dealing with a permutation of the
MIDI protocol, certain commands are one bytes,
others 2 or even 3. We do this part to figure out
how many bytes we're actually looking at

One of the first things to know is that that while
MIDI is packet based, the bytes have specialized
construction (where the top-most bit has been
reserved to differentiate if it's a command or a
data bit)

So on any byte being transferred in a MIDI stream, it
will look like the following

 BIT# | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
 DATA | X | ? | ? | ? | ? | ? | ? | ? |

If X is a "1" this byte is considered a command byte
If X is a "0" this byte is considered a data bte

We figure out how many bytes a packet is by looking at the
command byte and of that byte, only the high nybble.
This nybble tells us the requisite information via a lookup 
table... 

See: http://www.midi.org/techspecs/midimessages.php
And
http://www.ccarh.org/courses/253/handout/midiprotocol/
For more information

Basically, however:

command
nibble  bytes   
8       2
9       2
A       2
B       2
C       1
D       1
E       2
F       0 or variable

=cut

=head2 message_data_receive

Receive a string of data. Normally, only one byte 
is passed due to the code but you can also pass as
many bytes in a string as you'd like

=cut

sub message_data_receive {

	# --------------------------------------------------
	my ( $self, $data ) = @_;

	defined $data and length $data or return;

	my $protocol_version  = $self->{protocol_version};
	my $protocol_commands = $COMMANDS->{$protocol_version};
	my $protocol_lookup   = $COMMAND_LOOKUP->{$protocol_version};

	# Add the new data to the buffer
	my $buffer = $self->{buffer} ||= [];
	push @$buffer, unpack "C*", $data;

	my @packets;

	# Loop until we're finished parsing all available packets
	while (@$buffer) {

		# Not in SYSEX mode, we can proceed normally
		if (    $self->{parse_status} == MIDI_PARSE_NORMAL
			and $buffer->[0] == MIDI_START_SYSEX )
		{
			my $command = shift @$buffer;
			push @packets,
			  {
				command     => $command,
				command_str => $protocol_lookup->{$command} || 'START_SYSEX',
			  };
			$self->{parse_status} = MIDI_PARSE_SYSEX;
			next;
		}

		# If in sysex mode, we will check for the end of the sysex message here
		elsif ( $self->{parse_status} == MIDI_PARSE_SYSEX
			and $buffer->[0] == MIDI_END_SYSEX )
		{
			$self->{parse_status} = MIDI_PARSE_NORMAL;
			my $command = shift @$buffer;
			push @packets,
			  {
				command     => $command,
				command_str => $protocol_lookup->{$command} || 'END_SYSEX',
			  };
			# shift @$buffer;
		}

# Regardless of the SYSEX mode we are in, we will allow commands to interrupt the flowthrough
		elsif ( $buffer->[0] & MIDI_COMMAND ) {
			my $command = $buffer->[0] & 0xf0;
			my $bytes =
			  (      $MIDI_DATA_SIZES->{$command}
				  || $MIDI_DATA_SIZES->{ $buffer->[0] } ) + 1;
			if ( @$buffer < $bytes ) {
				last;
			}
			my @data = splice @$buffer, 0, $bytes;
			$command = shift @data;
			push @packets,
			  {
				command     => $command,
				command_str => $protocol_lookup->{$command}
				  || $protocol_lookup->{ $command & 0xf0 }
				  || 'UNKNOWN',
				data => \@data
			  };
		}

# We have a data byte, if we're in SYSEX mode, we'll just add that to the data stream
# packet
		elsif ( $self->{parse_status} == MIDI_PARSE_SYSEX ) {

			my $data = shift @$buffer;
			if ( @packets and $packets[-1]{command_str} eq 'DATA_SYSEX' ) {
				push @{ $packets[-1]{data} }, $data;
			}
			else {
				push @packets,
				  {
					command     => 0x0,
					command_str => 'DATA_SYSEX',
					data        => [$data]
				  };
			}

		}

		# No idea what to do with this one, eject it and skip to the next
		else {
			shift @$buffer;
			if ( not @$buffer ) {
				last;
			}
		}

	}

	return if not @packets;
	return \@packets;
}

=head2 sysex_parse

Takes the sysex data buffer and parses it into 
something useful

=cut

sub sysex_parse {

	# --------------------------------------------------
	my ( $self, $sysex_data ) = @_;

	my $protocol_version  = $self->{protocol_version};
	my $protocol_commands = $COMMANDS->{$protocol_version};
	my $protocol_lookup   = $COMMAND_LOOKUP->{$protocol_version};

	my $command = shift @$sysex_data;
	if ( defined $command ) {
		my $command_str = $protocol_lookup->{$command};

		my $return_data;

	  COMMAND_HANDLER: {
			$command == $protocol_commands->{REPORT_FIRMWARE} and do {
				$return_data = $self->handle_report_firmware($sysex_data);
				last;
			};

			$command == $protocol_commands->{CAPABILITY_RESPONSE} and do {
				$return_data = $self->handle_capability_response($sysex_data);
				last;
			};

			$command == $protocol_commands->{ANALOG_MAPPING_RESPONSE} and do {
				$return_data =
				  $self->handle_analog_mapping_response($sysex_data);
				last;
			};

			$command == $protocol_commands->{PIN_STATE_RESPONSE} and do {
				$return_data = $self->handle_pin_state_response($sysex_data);
				last;
			};

			$command == $protocol_commands->{ONEWIRE_REPLY} and do {
				$return_data = $self->handle_onewire_reply($sysex_data);
				last;
			};

			$command == $protocol_commands->{ONEWIRE_CONFIG} and do {
				$return_data = $self->handle_onewire_config($sysex_data);
				last;
			};

		}

		return {
			command     => $command,
			command_str => $command_str,
			data        => $return_data
		};
	}
	return undef;
}

=head2 message_prepare

Using the midi protocol, create a binary packet
that can be transmitted to the serial output

=cut

sub message_prepare {

	# --------------------------------------------------
	my ( $self, $command_name, $channel, @data ) = @_;

	my $protocol_version  = $self->{protocol_version};
	my $protocol_commands = $COMMANDS->{$protocol_version};
	my $command           = $protocol_commands->{$command_name} or return;

	my $bytes = 1 +
	  ( $MIDI_DATA_SIZES->{ $command & 0xf0 } || $MIDI_DATA_SIZES->{$command} );
	my $packet = pack "C" x $bytes, $command | $channel, @data;
	return $packet;
}

=head2 packet_sysex_command

create a binary packet containing a sysex-command

=cut

sub packet_sysex_command {

	my ( $self, $command_name, @data ) = @_;

	my $protocol_version  = $self->{protocol_version};
	my $protocol_commands = $COMMANDS->{$protocol_version};
	my $command           = $protocol_commands->{$command_name} or return;

#    my $bytes = 3+($MIDI_DATA_SIZES->{$command & 0xf0}||$MIDI_DATA_SIZES->{$command});
	my $bytes = @data + 3;
	my $packet = pack "C" x $bytes, $protocol_commands->{START_SYSEX},
	  $command,
	  @data,
	  $protocol_commands->{END_SYSEX};
	return $packet;
}

=head2 packet_query_version

Craft a firmware version query packet to be sent

=cut

sub packet_query_version {

	my $self = shift;
	return $self->message_prepare( REPORT_VERSION => 0 );

}

sub handle_query_version_response {

}

=head2 packet_query_firmware

Craft a firmware variant query packet to be sent

=cut

sub packet_query_firmware {

	my $self = shift;

	return $self->packet_sysex_command(REPORT_FIRMWARE);
}

sub handle_report_firmware {

	my ( $self, $sysex_data ) = @_;

	return {
		major_version => shift @$sysex_data,
		minor_version => shift @$sysex_data,
		firmware      => double_7bit_to_string($sysex_data)
	};
}

sub packet_query_capability {

	my $self = shift;

	return $self->packet_sysex_command(CAPABILITY_QUERY);
}

#/* capabilities response
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  capabilities response (0x6C)
# * 2  1st mode supported of pin 0
# * 3  1st mode's resolution of pin 0
# * 4  2nd mode supported of pin 0
# * 5  2nd mode's resolution of pin 0
# ...   additional modes/resolutions, followed by a single 127 to mark the
#       end of the first pin's modes.  Each pin follows with its mode and
#       127, until all pins implemented.
# * N  END_SYSEX (0xF7)
# */

sub handle_capability_response {

	my ( $self, $sysex_data ) = @_;

	my @pins;

	my $firstbyte = shift @$sysex_data;

	while ( defined $firstbyte ) {

		my @pinmodes;
		while ( defined $firstbyte && $firstbyte != 127 ) {
			my $pinmode = {
				mode       => $firstbyte,
				resolution => shift @$sysex_data    # /secondbyte
			};
			push @pinmodes, $pinmode;
			$firstbyte = shift @$sysex_data;
		}
		push @pins, \@pinmodes;
		$firstbyte = shift @$sysex_data;
	}

	return { pins => \@pins };

}

sub packet_query_analog_mapping {

	my $self = shift;

	return $self->packet_sysex_command(ANALOG_MAPPING_QUERY);
}

#/* analog mapping response
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  analog mapping response (0x6A)
# * 2  analog channel corresponding to pin 0, or 127 if pin 0 does not support analog
# * 3  analog channel corresponding to pin 1, or 127 if pin 1 does not support analog
# * 4  analog channel corresponding to pin 2, or 127 if pin 2 does not support analog
# ...   etc, one byte for each pin
# * N  END_SYSEX (0xF7)
# */

sub handle_analog_mapping_response {

	my ( $self, $sysex_data ) = @_;

	# my @pins;

	# my $pin_mapping = shift @$sysex_data;

	# while ( defined $pin_mapping ) {
	#	push @pins, $pin_mapping;
	# }

	# return { pins => \@pins };
	return { pins => $sysex_data }; # FIXME how to handle this?

}

#/* pin state query
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  pin state query (0x6D)
# * 2  pin (0 to 127)
# * 3  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
# */

sub packet_query_pin_state {

	my ( $self, $pin ) = @_;

	return $self->packet_sysex_command( PIN_STATE_QUERY, $pin );
}

#/* pin state response
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  pin state response (0x6E)
# * 2  pin (0 to 127)
# * 3  pin mode (the currently configured mode)
# * 4  pin state, bits 0-6
# * 5  (optional) pin state, bits 7-13
# * 6  (optional) pin state, bits 14-20
# ...  additional optional bytes, as many as needed
# * N  END_SYSEX (0xF7)
# */

sub handle_pin_state_response {

	my ( $self, $sysex_data ) = @_;

	my $pin   = shift @$sysex_data;
	my $mode  = shift @$sysex_data;
	my $state = shift @$sysex_data & 0x7f;

	my $nibble = shift @$sysex_data;
	for ( my $i = 1 ; defined $nibble ; $nibble = shift @$sysex_data ) {
		$state += ( $nibble & 0x7f ) << ( 7 * $i );
	}

	return {
		pin   => $pin,
		mode  => $mode,
		state => $state
	};

}

sub packet_sampling_interval {

	my ( $self, $interval ) = @_;

	return $self->packet_sysex_command( SAMPLING_INTERVAL,
		$interval & 0x7f,
		$interval >> 7
	);
}

#/* I2C read/write request
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  I2C_REQUEST (0x76)
# * 2  slave address (LSB)
# * 3  slave address (MSB) + read/write and address mode bits
#      {7: always 0} + {6: reserved} + {5: address mode, 1 means 10-bit mode} +
#      {4-3: read/write, 00 => write, 01 => read once, 10 => read continuously, 11 => stop reading} +
#      {2-0: slave address MSB in 10-bit mode, not used in 7-bit mode}
# * 4  data 0 (LSB)
# * 5  data 0 (MSB)
# * 6  data 1 (LSB)
# * 7  data 1 (MSB)
# * ...
# * n  END_SYSEX (0xF7)
# */

sub packet_i2c_request {

}

#/* I2C reply
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  I2C_REPLY (0x77)
# * 2  slave address (LSB)
# * 3  slave address (MSB)
# * 4  register (LSB)
# * 5  register (MSB)
# * 6  data 0 LSB
# * 7  data 0 MSB
# * ...
# * n  END_SYSEX (0xF7)
# */

sub handle_i2c_reply {

	my ( $self, $sysex_data ) = @_;

	my $slave_address =
	  ( shift @$sysex_data & 0x7f ) + ( shift @$sysex_data << 7 );
	my $register = ( shift @$sysex_data & 0x7f ) + ( shift @$sysex_data << 7 );

	my @data;

	my $lsb = shift @$sysex_data;
	while ( defined $lsb ) {
		my $msb = shift @$sysex_data;
		push @data, ( $lsb & 0x7f + ( $msb << 7 ) & 0x7f );
		$lsb = shift @$sysex_data;
	}

	return {
		slave_address => $slave_address,
		register      => $register,
		data          => \@data,
	};
}

#/* I2C config
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  I2C_CONFIG (0x78)
# * 2  Delay in microseconds (LSB)
# * 3  Delay in microseconds (MSB)
# * ... user defined for special cases, etc
# * n  END_SYSEX (0xF7)
# */

sub packet_i2c_config {

	my ( $self, $data ) = @_;

	my $delay  = $data->{delay};
	my @custom = $data->{custom_data};

	return $self->packet_sysex_command( I2C_CONFIG,
		$delay & 0x7f,
		$delay >> 7, @custom
	);
}

#/* servo config
# * --------------------
# * 0  START_SYSEX (0xF0)
# * 1  SERVO_CONFIG (0x70)
# * 2  pin number (0-127)
# * 3  minPulse LSB (0-6)
# * 4  minPulse MSB (7-13)
# * 5  maxPulse LSB (0-6)
# * 6  maxPulse MSB (7-13)
# * 7  END_SYSEX (0xF7)
# */

sub packet_servo_config {

	my ( $self, $data ) = @_;

	my $min_pulse = $data->{min_pulse};
	my $max_pulse = $data->{max_pulse};

	return $self->packet_sysex_command( SERVO_CONFIG,
		$data->{pin} & 0x7f,
		$min_pulse & 0x7f,
		$min_pulse >> 7,
		$max_pulse & 0x7f,
		$max_pulse >> 7
	);
}

#This is just the standard SET_PIN_MODE message:

#/* set digital pin mode
# * --------------------
# * 1  set digital pin mode (0xF4) (MIDI Undefined)
# * 2  pin number (0-127)
# * 3  state (INPUT/OUTPUT/ANALOG/PWM/SERVO, 0/1/2/3/4)
# */

#Then the normal ANALOG_MESSAGE data format is used to send data.

#/* write to servo, servo write is performed if the pins mode is SERVO
# * ------------------------------
# * 0  ANALOG_MESSAGE (0xE0-0xEF)
# * 1  value lsb
# * 2  value msb
# */

# ONE_WIRE_COMMANDS:
#	SEARCH           => 0,
#	RESET            => 1,
#	SKIP_AND_WRITE   => 2,
#	SKIP_AND_READ    => 3,
#	SELECT_AND_WRITE => 4,
#	SELECT_AND_READ  => 5,
#   CONFIG           => 6,

sub packet_onewire_request {

	my ( $self, $pin, $command, @args ) = @_;

  COMMAND_HANDLER: {

		$command eq 'SELECT_AND_WRITE'
		  and do {    #PIN,COMMAND,ADDRESS,NUMBYTES,DATA
			my $device   = shift @args;
			my $data     = shift @args;
			my $numbytes = @$data;
			my @buffer;
			push_onewire_device_as_two_7bit( $device, \@buffer );
			push_value_as_two_7bit( $numbytes, \@buffer );
			push_array_as_two_7bit( $data, \@buffer );
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{SELECT_AND_WRITE}, @buffer );
		  };

		$command eq 'SELECT_AND_READ'
		  and do {    #PIN,COMMAND,ADDRESS,READCOMMAND,NUMBYTES
			my $device      = shift @args;
			my $readcommand = shift @args;
			my $numbytes    = shift @args;
			my @buffer;
			push_onewire_device_as_two_7bit( $device, \@buffer );
			push_value_as_two_7bit( $readcommand, \@buffer );
			push_value_as_two_7bit( $numbytes,    \@buffer );
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{SELECT_AND_READ}, @buffer );
		  };

		$command eq 'SKIP_AND_WRITE' and do {    #PIN,COMMAND,NUMBYTES,DATA
			my $data     = shift @args;
			my $numbytes = @$data;
			my @buffer;
			push_value_as_two_7bit( $numbytes, \@buffer );
			push_array_as_two_7bit( $data, \@buffer );
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{SKIP_AND_WRITE}, @buffer );
		};

		$command eq 'SKIP_AND_READ' and do {   #PIN,COMMAND,READCOMMAND,NUMBYTES
			my $readcommand = shift @args;
			my $numbytes    = shift @args;
			my @buffer;
			push_value_as_two_7bit( $readcommand, \@buffer );
			push_value_as_two_7bit( $numbytes,    \@buffer );
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{SKIP_AND_READ}, @buffer );
		};

		$command eq 'SEARCH' and do {
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{SEARCH} );
		};
		
		$command eq 'CONFIG' and do {
			my $power = shift @args;
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{CONFIG},( defined $power ) ? $power : 1 );
		};
		
		$command eq 'REPORT_CONFIG' and do {
			my $device = shift @args;
			my $config = shift @args;
			my @buffer;
			push_onewire_device_as_two_7bit( $device, \@buffer );
			push_value_as_two_7bit ($config->{preReadCommand}, \@buffer);
			push_value_as_two_7bit ($config->{readDelay}, \@buffer);
			push_value_as_two_7bit ($config->{readCommand}, \@buffer);
			push_value_as_two_7bit ($config->{numBytes}, \@buffer);
			return $self->packet_sysex_command( ONEWIRE_REQUEST, $pin,
				$ONE_WIRE_COMMANDS->{REPORT_CONFIG}, @buffer);
		}
	}
}

sub handle_onewire_reply {

	my ( $self, $sysex_data ) = @_;

	my $pin     = shift @$sysex_data;
	my $command = shift @$sysex_data;

	if ( defined $command ) {
	  COMMAND_HANDLER: {

			$command == $ONE_WIRE_COMMANDS->{READ}
			  and do {    #PIN,COMMAND,ADDRESS,DATA

				my $device = shift_onewire_device_from_two_7bit($sysex_data);
				my @data   = double_7bit_to_array($sysex_data);

				return {
					pin     => $pin,
					command => 'READ',
					device  => $device,
					data    => \@data
				};
			  };

			$command == $ONE_WIRE_COMMANDS->{SEARCH}
			  and do {    #PIN,COMMAND,ADDRESS...

				my @devices;

				my $device = shift_onewire_device_from_two_7bit($sysex_data);
				while ( defined $device ) {
					push @devices, $device;
					$device = shift_onewire_device_from_two_7bit($sysex_data);
				}
				return {
					pin     => $pin,
					command => 'SEARCH',
					devices => \@devices,
				};
			  };
		}
	}
}

sub shift14bit {

	my $data = shift;

	my $lsb = shift @$data;
	my $msb = shift @$data;
	return
	    defined $lsb
	  ? defined $msb 
		  ? ( $msb << 7 ) + ( $lsb & 0x7f ) 
		  : $lsb
	  : undef;
}

sub double_7bit_to_string {
	my ( $data, $numbytes ) = @_;
	my $ret;
	if ( defined $numbytes ) {
		for ( my $i = 0 ; $i < $numbytes ; $i++ ) {
			my $value = shift14bit($data);
			$ret .= chr($value);
		}
	}
	else {
		while (@$data) {
			my $value = shift14bit($data);
			$ret .= chr($value);
		}
	}
	return $ret;
}

sub double_7bit_to_array {
	my ( $data, $numbytes ) = @_;
	my @ret;
	if ( defined $numbytes ) {
		for ( my $i = 0 ; $i < $numbytes ; $i++ ) {
			push @ret, shift14bit($data);
		}
	}
	else {
		while (@$data) {
			my $value = shift14bit($data);
			push @ret, $value;
		}
	}
	return @ret;
}

sub shift_onewire_device_from_two_7bit {
	my $buffer = shift;

	my $family = shift14bit($buffer);
	if ( defined $family ) {
		my @addressbytes = double_7bit_to_array( $buffer, 6 );
		my $crc = shift14bit($buffer);
		return {
			family   => $family,
			identity => \@addressbytes,
			crc      => $crc
		};
	}
	else {
		return undef;
	}

}

sub push_value_as_two_7bit {
	my ( $value, $buffer ) = @_;
	push @$buffer, $value & 0x7f;    #LSB
	push @$buffer, ( $value >> 7 ) & 0x7f;    #MSB
}

sub push_onewire_device_as_two_7bit {
	my ( $device, $buffer ) = @_;
	push_value_as_two_7bit( $device->{family}, $buffer );
	for ( my $i = 0 ; $i < 6 ; $i++ ) {
		push_value_as_two_7bit( $device->{identity}[$i], $buffer );
	}
	push_value_as_two_7bit( $device->{crc}, $buffer );
}

sub push_array_as_two_7bit {
	my ( $data, $buffer ) = @_;
	my $byte = shift @$data;
	while ( defined $byte ) {
		push_value_as_two_7bit( $byte, $buffer );
		$byte = shift @$data;
	}
}

1;
