package Device::Firmata::Platform;

=head1 NAME

Device::Firmata::Platform - platform specifics

=cut

use strict;
use Time::HiRes qw/time/;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::IO;
use Device::Firmata::Protocol;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {

# Object handlers
        io               => undef,
        protocol         => undef,

# Used for internal tracking of events/parameters
        protocol_version => undef,
        sysex_mode       => undef,
        sysex_data       => [],

# To track internal status
        ports            => [],
        analog_pins      => [],
        pins             => {},
        
# To notify on events
        observer         => [],
        digital_observer => [],
        analog_observer  => [],
        onewire_observer => [],

# For information about the device. eg: firmware version
        metadata         => {},
    };


=head2 open

Connect to the IO port and do some basic operations
to find out how to connect to the device

=cut

sub open {
# --------------------------------------------------
    my ( $pkg, $port, $opts ) = @_;
    
    my $self = ref $pkg ? $pkg : $pkg->new($opts);

    my $ioport = Device::Firmata::IO->open($port,$opts) or return;
    
    return $self->attach($ioport,$opts);
}

sub attach {
# --------------------------------------------------
# Attach to an open IO port and do some basic operations
# to find out how to connect to the device
#
    my ( $pkg, $port, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

    $self->{io}       = $port or return;
    $self->{protocol} = Device::Firmata::Protocol->new($opts) or return;

    return $self;
}

sub detach {

	my $self = shift;
	
	delete $self->{io};
}

=head2 messages_handle

Receive identified message packets and convert them
into their appropriate structures and parse
them as required

=cut

sub messages_handle {
# --------------------------------------------------
    my ( $self, $messages ) = @_;

    return unless $messages;
    return unless @$messages;

# Now, handle the messages
    my $proto  = $self->{protocol};
    for my $message ( @$messages ) {
        my $command = $message->{command_str};
        my $data    = $message->{data};

        COMMAND_HANDLE: {

# Handle pin messages
            $command eq 'DIGITAL_MESSAGE' and do {
                my $port_number = $message->{command} & 0x0f;
                my $port_state  = $data->[0] | ($data->[1] << 7);
               	my $old_state = $self->{ports}[$port_number];
               	my $changed_state = defined $old_state ? $old_state ^ $port_state : 0xFF;
               	my $observers = $self->{digital_observer};
               	my $pinbase = $port_number<<3;
               	for (my $i=0;$i<8;$i++) {
               		my $pin = $pinbase+$i;
               		my $observer = $observers->[$pin];
               		if ($observer) {
               			my $pin_mask = 1<<$i;
               			if ($changed_state & $pin_mask) {
               				&$observer($pin,defined $old_state ? ($old_state & $pin_mask) > 0 ? 1 : 0 : undef ,($port_state & $pin_mask) > 0 ? 1 : 0);
               			}
               		}
               	}
                $self->{ports}[$port_number] = $port_state;
            };

# Handle analog pin messages
            $command eq 'ANALOG_MESSAGE' and do {
                my $pin_number = $message->{command} & 0x0f;
                my $pin_value = ( $data->[0] | ($data->[1] << 7) ) / 1023;
                my $observer = $self->{analog_observer}[$pin_number];
                if ($observer) {
                	my $old_value = $self->{analog_pins}[$pin_number];
	               	if (!defined $old_value or $old_value != $pin_value) {
                		&$observer($pin_number,$old_value,$pin_value);
	              	}
                }
                $self->{analog_pins}[$pin_number] = $pin_value;
            };


# Handle metadata information
            $command eq 'REPORT_VERSION' and do {
                $self->{metadata}{firmware_version} = sprintf "V_%i_%02i", @$data;
                last;
            };

# SYSEX handling
            $command eq 'START_SYSEX' and do {
                last;
            };
            $command eq 'DATA_SYSEX' and do {
                my $sysex_data = $self->{sysex_data};
                push @$sysex_data, @$data;
                last;
            };
            $command eq 'END_SYSEX' and do {
                my $sysex_data = $self->{sysex_data};
                my $sysex_message = $proto->sysex_parse($sysex_data);
                if (defined $sysex_message) {
                	$self->sysex_handle($sysex_message);
                }
                $self->{sysex_data} = [];
                last;
            };

        };
 
        $Device::Firmata::DEBUG and print "    < $command\n";
    }

}


=head2 sysex_handle

Receive identified sysex packets and convert them
into their appropriate structures and parse
them as required

=cut

sub sysex_handle {
# --------------------------------------------------
    my ( $self, $sysex_message ) = @_;

    my $data = $sysex_message->{data};

	COMMAND_HANDLER : {	
    	$sysex_message->{command_str} eq 'REPORT_FIRMWARE' and do {
    	    $self->{metadata}{firmware_version} = sprintf "V_%i_%02i", $data->{major_version}, $data->{minor_version};
	        $self->{metadata}{firmware} = $data->{firmware};
        	last;
    	};
    
	    $sysex_message->{command_str} eq 'ONEWIRE_REPLY' and do {
			my $pin = $data->{pin};
			my $observer = $self->{onewire_observer}[$pin];
			&$observer($pin,$data);    	
    		last;
	    }
	}
}


=head2 probe

Request the version of the protocol that the
target device is using. Sometimes, we'll have to
wait a couple of seconds for the response so we'll
try for 2 seconds and rapidly fire requests if 
we don't get a response quickly enough ;)

=cut

sub probe {
# --------------------------------------------------
    my ( $self ) = @_;

    my $proto  = $self->{protocol};
    my $io     = $self->{io};
    $self->{metadata}{firmware_version} = '';

# Wait for 10 seconds only
    my $end_tics = time + 10;

# Query every .5 seconds
    my $query_tics = time;
    while ( $end_tics >= time ) {

        if ( $query_tics <= time ) {
# Query the device for information on the firmata firmware_version
            my $query_packet = $proto->packet_query_firmware;
            $io->data_write($query_packet) or die "OOPS: $!";
            $query_tics = time + 0.5;
        };

# Try to get a response
		$self->poll;

        if ( $self->{metadata}{firmware} && $self->{metadata}{firmware_version}) {
        	$self->{protocol}->{protocol_version} = $self->{metadata}{firmware_version}; 
            return 1;
        }
    }
    return undef;
}


=head2 pin_mode

Similar to the pinMode function on the 
arduino

=cut

sub pin_mode {
# --------------------------------------------------
    my ( $self, $pin, $mode ) = @_;

    ( $mode == PIN_INPUT or $mode == PIN_OUTPUT ) and do {
        my $port_number = $pin >> 3;
        my $mode_packet = $self->{protocol}->message_prepare( REPORT_DIGITAL => $port_number, 1 );
        $self->{io}->data_write($mode_packet);

        $mode_packet = $self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode );
        return $self->{io}->data_write($mode_packet);
    };

    $mode == PIN_PWM and do {
        my $mode_packet = $self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode );
        return $self->{io}->data_write($mode_packet);
    };

    $mode == PIN_ANALOG and do {
        my $port_number = $pin >> 3;
        my $mode_packet = $self->{protocol}->message_prepare( REPORT_ANALOG => $port_number, 1 );
        $self->{io}->data_write($mode_packet);

        $mode_packet = $self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode );
        return $self->{io}->data_write($mode_packet);
    };
    
    $mode == PIN_ONEWIRE and do {
    	my $mode_packet = $self->{protocol}->message_prepare ( SET_PIN_MODE => 0, $pin, $mode );
    	return $self->{io}->data_write($mode_packet);
    };

}


=head2 digital_write

Analogous to the digitalWrite function on the 
arduino

=cut

sub digital_write {
# --------------------------------------------------
    my ( $self, $pin, $state ) = @_;
    my $port_number = $pin >> 3;

    my $pin_offset  = $pin % 8;
    my $pin_mask    = 1<<$pin_offset;

    my $port_state  = $self->{ports}[$port_number] ||= 0;
    if ( $state ) {
        $port_state |= $pin_mask;
    }
    else {
        $port_state &= $pin_mask ^ 0xff;
    }
    $self->{ports}[$port_number] = $port_state;

    my $mode_packet = $self->{protocol}->message_prepare( DIGITAL_MESSAGE => $port_number, $port_state);
    return $self->{io}->data_write($mode_packet);
}


=head2 digital_read

Analogous to the digitalRead function on the 
arduino

=cut

sub digital_read {
# --------------------------------------------------
    my ( $self, $pin ) = @_;
    my $port_number = $pin >> 3;
    my $pin_offset  = $pin % 8;
    my $pin_mask    = 1<<$pin_offset;
    my $port_state = $self->{ports}[$port_number] ||= 0;
    return( $port_state & $pin_mask ? 1 : 0 );
}


=head2 analog_read

Fetches the analog value of a pin 

=cut

sub analog_read {
# --------------------------------------------------
#
    my ( $self, $pin ) = @_;
    return $self->{analog_pins}[$pin];
}


=head2 analog_write

=cut

sub analog_write {
# --------------------------------------------------
# Sets the PWM value on an arduino
#
    my ( $self, $pin, $value ) = @_;

# FIXME: 8 -> 7 bit translation should be done in the protocol module
    my $byte_0 = $value & 0x7f;
    my $byte_1 = $value >> 7;
    my $mode_packet = $self->{protocol}->message_prepare( ANALOG_MESSAGE => $pin, $byte_0, $byte_1 );
    return $self->{io}->data_write($mode_packet);
}

=head2 pwm_write

pmw_write is an alias for analog_write

=cut
*pwm_write = *analog_write;

sub sampling_interval {
	my ($self, $sampling_interval) = @_;
	my $sampling_interval_packet = $self->{protocol}->packet_sampling_interval($sampling_interval);
	return $self->{io}->data_write($sampling_interval_packet);
}

sub onewire_config {
	my ($self, $pin, $power) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'CONFIG',$power);
	return $self->{io}->data_write($onewire_packet);
}

sub onewire_report_config {
	my ($self,$pin,$device,$config) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'REPORT_CONFIG',$device,$config);
	return $self->{io}->data_write($onewire_packet);
}

sub onewire_search {
	my ($self, $pin) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'SEARCH');
	return $self->{io}->data_write($onewire_packet);
}

sub onewire_select_and_write { #PIN,COMMAND,ADDRESS,DATA
	my ($self, $pin, $device, $data) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'SELECT_AND_WRITE',$device,$data); 
	return $self->{io}->data_write($onewire_packet);
}

sub onewire_select_and_read { #PIN,COMMAND,ADDRESS,READCOMMAND,NUMBYTES
	my ($self, $pin, $device, $readcommand, $numbytes) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'SELECT_AND_READ',$device,$readcommand,$numbytes); 
	return $self->{io}->data_write($onewire_packet);
}

sub onewire_skip_and_write { #PIN,COMMAND,DATA
	my ($self, $pin, $data) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'SKIP_AND_WRITE',$data);
	return $self->{io}->data_write($onewire_packet);
}

sub onewire_skip_and_read { #PIN,COMMAND,READCOMMAND,NUMBYTES
	my ($self, $pin, $readcommand, $numbytes) = @_;
	my $onewire_packet = $self->{protocol}->packet_onewire_request($pin,'SKIP_AND_READ',$readcommand,$numbytes);
	return $self->{io}->data_write($onewire_packet);
}

=head2 poll

Call this function every once in a while to
check up on the status of the comm port, receive
and process data from the arduino

=cut

sub poll {
# --------------------------------------------------
    my $self = shift;
    my $buf = $self->{io}->data_read(100) or return;
    my $messages = $self->{protocol}->message_data_receive($buf);
    $self->messages_handle($messages);
    return $messages;
}

sub observe_digital {
	my ($self,$pin,$observer) = @_;
	$self->{digital_observer}[$pin]=$observer; 
}

sub observe_analog {
	my ($self,$pin,$observer) = @_;
	$self->{analog_observer}[$pin]=$observer; 
}

sub observe_onewire {
	my ($self,$pin,$observer) = @_;
	$self->{onewire_observer}[$pin]=$observer; 
}

1;
