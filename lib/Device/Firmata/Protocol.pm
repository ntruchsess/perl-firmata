package Device::Firmata::Protocol;

use strict;
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
};

# Because we're dealing with a permutation of the
# MIDI protocol, certain commands are one bytes,
# others 2 or even 3. We do this part to figure out
# how many bytes we're actually looking at

# One of the first things to know is that that while
# MIDI is packet based, the bytes have specialized
# construction (where the top-most bit has been
# reserved to differentiate if it's a command or a
# data bit)

# So on any byte being transferred in a MIDI stream, it
# will look like the following

# BIT# | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
# DATA | X | ? | ? | ? | ? | ? | ? | ? |

# If X is a "1" this byte is considered a command byte
# If X is a "0" this byte is considered a data bte

# We figure out how many bytes a packet is by looking at the
# command byte and of that byte, only the high nybble.
# This nybble tells us the requisite information via a lookup 
# table... 

# See: http://www.midi.org/techspecs/midimessages.php
# And
# http://www.ccarh.org/courses/253/handout/midiprotocol/
# For more information

# Basically, however:
# 
# command
# nibble  bytes   
# 8       2
# 9       2
# A       2
# B       2
# C       1
# D       1
# E       2
# F       0 or variable

sub message_data_receive {
# --------------------------------------------------
# Receive a string of data. Normally, only one byte 
# is passed due to the code but you can also pass as
# many bytes in a string as you'd like
#
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
            my $command = shift @data;
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

sub message_packet_parse {
# --------------------------------------------------
# Receive a SINGLE full message packet and convert the 
# binary string into an easier-to-use hash
#
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

sub sysex_parse {
# --------------------------------------------------
# Takes the sysex data buffer and parses it into 
# something useful
#
    my ( $self, $sysex_data ) = @_;

    my $protocol_version  = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};
    my $protocol_lookup   = $COMMAND_LOOKUP->{$protocol_version};

    my $command = shift @$sysex_data;

    $command == $protocol_commands->{REPORT_FIRMWARE} and do {
        my $major_version = shift @$sysex_data;
        my $minor_version = shift @$sysex_data;
#        my $firmware      = pack "B*", join "", map { substr(unpack("B*",chr($_)),1,7) } @$sysex_data;
        my $firmware      = join "", map {chr$_} @$sysex_data;
        return {
            command     => $command,
            command_str => $protocol_lookup->{$command}||'UNKNOWN',
            data        => [$major_version,$minor_version,$firmware]
        };
    };

    return;
}

sub message_prepare {
# --------------------------------------------------
# Using the midi protocol, create a binary packet
# that can be transmitted to the serial output
#
    my ( $self, $command_name, $channel, @data ) = @_;

    my $protocol_version  = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};
    my $command = $protocol_commands->{$command_name} or return;

    my $bytes = 1+($MIDI_DATA_SIZES->{$command & 0xf0}||$MIDI_DATA_SIZES->{$command});
    my $packet = pack "C"x$bytes, $command|$channel, @data;
    return $packet;
}

sub packet_query_version {
# --------------------------------------------------
# Craft a firmware version query packet to be sent
#
    my $self = shift;

    my $protocol_version = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};
    my $packet = pack "C", $protocol_commands->{REPORT_VERSION};

    return $packet;
}

sub packet_query_firmware {
# --------------------------------------------------
# Craft a firmware variant query packet to be sent
#
    my $self = shift;

    my $protocol_version = $self->{protocol_version};
    my $protocol_commands = $COMMANDS->{$protocol_version};
    my $packet = pack "CCC", $protocol_commands->{START_SYSEX},
                             $protocol_commands->{REPORT_FIRMWARE},
                             $protocol_commands->{END_SYSEX};

    return $packet;
}

1;
