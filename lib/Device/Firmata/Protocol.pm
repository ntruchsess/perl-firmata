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
    ISA => 'Device::Firmata::Base',
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
    0xF0 => 0, # note that this requires special handling

# Special for version queries
    0xF4 => 2,
    0xF9 => 2,
    
	0x79 => 0,    
    0x7A => 2
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

    my $protocol_version = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};
    my $protocol_lookup   = $COMMAND_LOOKUP->{$protocol_version};

# Add the new data to the buffer
    my $buffer = $self->{buffer} ||= [];
    push @$buffer, unpack "C*", $data;

    my @packets;

# Loop until we're finished parsing all available packets
    while (@$buffer) {

# Not in SYSEX mode, we can proceed normally
        if ( $self->{parse_status} == MIDI_PARSE_NORMAL and $buffer->[0] == MIDI_START_SYSEX ) {
            my $command = shift @$buffer;
            push @packets, {
                command     => $command,
                command_str => $protocol_lookup->{$command}||'START_SYSEX',
            };
            $self->{parse_status} = MIDI_PARSE_SYSEX;
            next;
        }

# If in sysex mode, we will check for the end of the sysex message here
        elsif ( $self->{parse_status} == MIDI_PARSE_SYSEX and $buffer->[0] == MIDI_END_SYSEX ) {
            $self->{parse_status} = MIDI_PARSE_NORMAL;
            my $command = shift @$buffer;
            push @packets, {
                command     => $command,
                command_str => $protocol_lookup->{$command}||'END_SYSEX',
            };
            shift @$buffer;
        }

# Regardless of the SYSEX mode we are in, we will allow commands to interrupt the flowthrough
        elsif ( $buffer->[0] & MIDI_COMMAND ) {
            my $command = $buffer->[0] & 0xf0;
            my $bytes = ($MIDI_DATA_SIZES->{$command}||$MIDI_DATA_SIZES->{$buffer->[0]})+1;
            if ( @$buffer < $bytes ) {
                last;
            }
            my @data = splice @$buffer, 0, $bytes;
            $command = shift @data;
            push @packets, {
                command => $command,
                command_str => $protocol_lookup->{$command}||$protocol_lookup->{$command&0xf0}||'UNKNOWN',
                data    => \@data
            };
        }

# We have a data byte, if we're in SYSEX mode, we'll just add that to the data stream
# packet
        elsif ( $self->{parse_status} == MIDI_PARSE_SYSEX ) {

            my $data = shift @$buffer;
            if ( @packets and $packets[-1]{command_str} eq 'DATA_SYSEX' ) {
                push @{$packets[-1]{data}}, $data;
            }
            else {
                push @packets, {
                    command => 0x0,
                    command_str => 'DATA_SYSEX',
                    data    => [ $data ]
                };
            };

        }

# No idea what to do with this one, eject it and skip to the next
        else {
            shift @$buffer;
            if ( not @$buffer ) {
                last;
            }
        };


    }

    return if not @packets;
    return \@packets;
}


=head2 message_packet_parse

Receive a SINGLE full message packet and convert the 
binary string into an easier-to-use hash

=cut

sub message_packet_parse {
# --------------------------------------------------
    my ( $self, $packet ) = @_;

# Standardize input: Make sure that $packet is an array ref
    if (ref $packet) {
        $packet = [ split //, $packet ];
    }

# Now figure out what command we're playing with
    my $command = shift @$packet;
    my $bytes = 1+$MIDI_DATA_SIZES->{$command & 0xf0};

# Now that we have the command byte, let's figure out
# what it actually means. What does it mean?! 
# Sadly, 0x42 or 42 implies a data byte so it's nothing
# very exciting. *sniff*
    my $protocol_version = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};

    COMMAND_HANDLER: {
        my $command_nybble = $command & 0xf0;

        $command_nybble == $protocol_commands->{DIGITAL_MESSAGE} and do {
            last;
        };

        $command_nybble == $protocol_commands->{ANALOG_MESSAGE} and do {
            last;
        };

        $command_nybble == $protocol_commands->{REPORT_ANALOG} and do {
            last;
        };

        $command_nybble == $protocol_commands->{REPORT_DIGITAL} and do {
            last;
        };

        $command == $protocol_commands->{SET_PIN_MODE} and do {
            last;
        };

        $command == $protocol_commands->{REPORT_VERSION} and do {
            last;
        };

        $command == $protocol_commands->{SYSTEM_RESET} and do {
            last;
        };

        $command == $protocol_commands->{START_SYSEX} and do {
            last;
        };

        $command == $protocol_commands->{END_SYSEX} and do {
            last;
        };

        $command == $protocol_commands->{SERVO_CONFIG} and do {
            last;
        };

        $command == $protocol_commands->{STRING_DATA} and do {
            last;
        };

        $command == $protocol_commands->{I2C_REQUEST} and do {
            last;
        };

        $command == $protocol_commands->{I2C_REPLY} and do {
            last;
        };

        $command == $protocol_commands->{I2C_CONFIG} and do {
            last;
        };

        $command == $protocol_commands->{REPORT_FIRMWARE} and do {
            last;
        };

        $command == $protocol_commands->{SAMPLING_INTERVAL} and do {
            last;
        };

        $command == $protocol_commands->{SYSEX_NON_REALTIME} and do {
            last;
        };

        $command == $protocol_commands->{SYSEX_REALTIME} and do {
            last;
        };

    };

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
    my $command_str = $protocol_lookup->{$command};

    my $return_data;

	COMMAND_HANDLER : {
    	$command == $protocol_commands->{REPORT_FIRMWARE} and do {
    		$return_data = $self->handle_report_firmware($sysex_data);
    		last;
    	};
    	
    	$command == $protocol_commands->{CAPABILITY_RESPONSE} and do {
    		$return_data = $self->handle_capability_response($sysex_data);
    		last;
    	};

    	$command == $protocol_commands->{ANALOG_MAPPING_RESPONSE} and do {
    		$return_data = $self->handle_analog_mapping_response($sysex_data);
    		last;
    	};

    	$command == $protocol_commands->{PIN_STATE_RESPONSE} and do {
    		$return_data = $self->handle_pin_state_response($sysex_data);
    		last;
    	};
    	
	}

    return {
    	command => $command,
    	command_str => $command_str,
    	data => $return_data
    };
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
    my $command = $protocol_commands->{$command_name} or return;

    my $bytes = 1+($MIDI_DATA_SIZES->{$command & 0xf0}||$MIDI_DATA_SIZES->{$command});
    my $packet = pack "C"x$bytes, $command|$channel, @data;
    return $packet;
}

sub packet_sysex_command {
	
	my ($self,$command_name,@data) = @_;
	
    my $protocol_version  = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};
    my $command = $protocol_commands->{$command_name} or return;
	
    my $bytes = 3+($MIDI_DATA_SIZES->{$command & 0xf0}||$MIDI_DATA_SIZES->{$command});
    my $packet = pack "C"x$bytes, $protocol_commands->{START_SYSEX},
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
	return $self->message_prepare(REPORT_VERSION => 0);

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

	my ($self,$sysex_data) = @_;
	
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

	my ($self,$sysex_data) = @_;
	
	my @pins;
	
	my $firstbyte = shift @$sysex_data;
	
	while (defined $firstbyte) {

		my @pinmodes;
		while (defined $firstbyte && $firstbyte != 127) {
			my $pinmode = {
				mode => $firstbyte,
				resolution => shift @$sysex_data # /secondbyte
			};
			push @pinmodes,$pinmode;
			$firstbyte = shift @$sysex_data;
		};
		push @pins, \@pinmodes;
		$firstbyte = shift @$sysex_data;		
	};
	
    return {
    	pins => \@pins
    };
	
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
	
	my ($self,$sysex_data) = @_;
	
	my @pins;
	
	my $pin_mapping = shift @$sysex_data;
	
	while (defined $pin_mapping) {
		push @pins, $pin_mapping;
	}
	
    return {
    	pins => \@pins
    };
	
}

#/* pin state query
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  pin state query (0x6D)
# * 2  pin (0 to 127)
# * 3  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
# */
 
sub packet_query_pin_state {
	
	my ($self,$pin) = @_;
	
	return $self->packet_sysex_command(PIN_STATE_QUERY,$pin);
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
	
	my ($self,$sysex_data) = @_;
	
	my $pin = shift @$sysex_data;
	my $mode = shift @$sysex_data;
	my $state = shift @$sysex_data & 0x7f;
	
	my $nibble = shift @$sysex_data;
	for (my $i=1; defined $nibble; $nibble = shift @$sysex_data) {
		$state += ($nibble & 0x7f) << (7*$i);
	}
	
    return {
    	pin => $pin,
    	mode => $mode,
    	state => $state
    };
	
}

sub packet_sampling_interval {

	my ($self,$interval) = @_;

	return $self->packet_sysex_command(SAMPLING_INTERVAL,$interval & 0x7f,$interval >> 7);
}

sub double_7bit_to_string($) {
	my ($data) = @_;
	my $ret;
	my @data = @$data if ref $data eq "ARRAY";
	while (@data) {
		my $value = shift(@data);
		$value+=shift(@data)<<7 if @data;
		$ret.=chr($value);
	}
	return $ret;
}

1;
