package Device::Firmata::Platform;

=head1 NAME

Device::Firmata::Platform - Firmata API

=head1 DESCRIPTION

Provides the application programming interface for Device::Firmata
implementing all major features of the Firmata 2.5 specification:

=over

=item * Analog Firmata

=item * Digital Firmata

=item * I2C Firmata

=item * 1-Wire Firmata

=item * Serial Firmata

=item * Servo Firmata

=item * Stepper Firmata

=item * Firmata Scheduler

=back

This API documentation is currently incomplete and only covers a small
subset of the implementation. Anyone willing to help improve the
documentation is welcome.

=cut

use strict;
use warnings;
use Time::HiRes qw/time/;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::Protocol;
use Device::Firmata::Base
  ISA                         => 'Device::Firmata::Base',
  FIRMATA_ATTRIBS             => {

  # Object handlers
  io                          => undef,
  protocol                    => undef,

  # Used for internal tracking of events/parameters
  #protocol_version           => undef,
  #sysex_mode                 => undef,
  sysex_data                  => [],

  # To track internal status
  analog_pins                 => [],
  analog_resolutions          => {},
  pwm_resolutions             => {},
  servo_resolutions           => {},
  stepper_resolutions         => {},
  encoder_resolutions         => {},
  serial_resolutions          => {},
  ports                       => [],
  input_ports                 => [],
  pins                        => {},
  pin_modes                   => {},
  encoders                    => [],

  # To notify on events
  digital_observer            => [],
  analog_observer             => [],
  sysex_observer              => undef,
  i2c_observer                => undef,
  onewire_observer            => [],
  stepper_observer            => [],
  encoder_observer            => [],
  serial_observer             => [],
  scheduler_observer          => undef,
  string_observer             => undef,

  # To track scheduled tasks
  tasks                       => [],

  # For information about the device. eg: firmware version
  metadata                    => {},

  # latest STRING_DATA response:
  stringresponse              => {},
  };

=head1 METHODS

=head2 attach ( ioPort )

Creates new Firmata Platform instance and attaches the provided I/O port.

=over

=item * param pkg: Perl package name or an instance of Device::Firmata::Platform

=item * param ioPort: either an instance of L<Device::Firmata::IO::SerialIO> or L<DDevice::Firmata::IO::NetIO> or
                      of any other class that provides compatible implementations for the methods data_read and data_write

=item * return new Device::Firmata::Platform instance

=back

After attaching the I/O port to the Firmata Platform the following sequence of operations is recommended:

=over

=item * 1. Call L</probe ( )> to request the capabilities of the Firmata device.

=item * 2. Call L</pin_mode ( pin, mode )> to configure the pins of the Firmata device.

=item * Periodically call L</poll ( )> to processess messages from the Firmata device.

=back

=cut

sub attach {
  my ( $pkg, $port, $opts ) = @_;
  my $self = ref $pkg ? $pkg : $pkg->new($opts);
  $self->{io} = $port or return;
  $self->{protocol} = Device::Firmata::Protocol->new($opts) or return;
  return $self;
}

=head2 detach ( )

Detach IO port from Firmata Platform.
Typically used only internally by L</close ( )>.

=cut

sub detach {
  my $self = shift;
  delete $self->{io} if ($self->{io});
  delete $self->{protocol} if ($self->{protocol});
  $self->{sysex_data}         = [];
  $self->{analog_pins}        = [];
  $self->{ports}              = [];
  $self->{input_ports}        = [];
  $self->{pins}               = {};
  $self->{pin_modes}          = {};
  $self->{digital_observer}   = [];
  $self->{analog_observer}    = [];
  $self->{sysex_observer}     = undef;
  $self->{i2c_observer}       = undef;
  $self->{onewire_observer}   = [];
  $self->{stepper_observer}   = [];
  $self->{encoder_observer}   = [];
  $self->{serial_observer}    = [];
  $self->{scheduler_observer} = undef;
  $self->{tasks}              = [];
  $self->{metadata}           = {};
}

=head2 close ( )

Close IO port and detach from Firmata Platform.

=cut

sub close {
  my $self = shift;
  $self->{io}->close();
  $self->detach();
}

=head2 system_reset ( )

Try to reset Firmata device. Will only work if Firmata device is connected.

=cut

sub system_reset {
  my $self = shift;
  $self->{io}->data_write($self->{protocol}->message_prepare( SYSTEM_RESET => 0 ));
  $self->{sysex_data}         = [];
  $self->{analog_pins}        = [];
  $self->{ports}              = [];
  $self->{pins}               = {};
  $self->{pin_modes}          = {};
  $self->{digital_observer}   = [];
  $self->{analog_observer}    = [];
  $self->{sysex_observer}     = undef;
  $self->{i2c_observer}       = undef;
  $self->{onewire_observer}   = [];
  $self->{stepper_observer}   = [];
  $self->{encoder_observer}   = [];
  $self->{serial_observer}    = [];
  $self->{scheduler_observer} = undef;
  $self->{tasks}              = [];
  $self->{metadata}           = {};
}

=head2 messages_handle ( messages )

Receive identified message packets and convert them into their appropriate
structures and parse them as required.
Typically used only internally by L</poll ( )>.

=cut

sub messages_handle {
  # --------------------------------------------------
  my ( $self, $messages ) = @_;
  return unless $messages;
  return unless @$messages;
  # Now, handle the messages
  my $proto = $self->{protocol};
  for my $message (@$messages) {
    my $command = $message->{command_str};
    my $data    = $message->{data};
    COMMAND_HANDLE: {
      #* digital I/O message   0x90   port       LSB(bits 0-6)         MSB(bits 7-13)
      # Handle pin messages
      $command eq 'DIGITAL_MESSAGE' and do {
        my $port_number = $message->{command} & 0x0f;
        my $port_state  = $data->[0] | ( $data->[1] << 7 );
        my $old_state   = $self->{input_ports}[$port_number] ||= 0;
        my $observers = $self->{digital_observer};
        my $pinbase   = $port_number << 3;
        for ( my $i = 0 ; $i < 8 ; $i++ ) {
          my $pin      = $pinbase + $i;
          my $observer = $observers->[$pin];
          if ($observer) {
            my $pin_mask = 1 << $i;
            $observer->{method}(
              $pin,
              ( $old_state & $pin_mask ) > 0 ? 1 : 0,
              ( $port_state & $pin_mask ) > 0 ? 1 : 0,
              $observer->{context}
            );
          }
        }
        $self->{input_ports}[$port_number] = $port_state;
      };

      # Handle analog pin messages
      $command eq 'ANALOG_MESSAGE' and do {
        my $pin_number = $message->{command} & 0x0f;
        my $pin_value  = ( $data->[0] | ( $data->[1] << 7 ) );
        if (defined $self->{metadata}{analog_mappings}) {
          $pin_number = $self->{metadata}{analog_mappings}{$pin_number};
        }
        my $observer   = $self->{analog_observer}[$pin_number];
        if ($observer) {
          my $old_value = $self->{analog_pins}[$pin_number];
          if ( !defined $old_value or !($old_value eq $pin_value) ) {
            $observer->{method}( $pin_number, $old_value, $pin_value, $observer->{context} );
          }
        }
        $self->{analog_pins}[$pin_number] = $pin_value;
      };

      # Handle metadata information
      $command eq 'REPORT_VERSION' and do {
        $self->{metadata}{protocol_version} = sprintf "V_%i_%02i",
          @$data;
        last;
      };

      # SYSEX handling
      $command eq 'START_SYSEX' and do { last; };

      $command eq 'DATA_SYSEX' and do {
        my $sysex_data = $self->{sysex_data};
        push @$sysex_data, @$data;
        last;
      };

      $command eq 'END_SYSEX' and do {
        my $sysex_data    = $self->{sysex_data};
        my $sysex_message = $proto->sysex_parse($sysex_data);
        if ( defined $sysex_message ) {
          my $observer = $self->{sysex_observer};
          if (defined $observer) {
            $observer->{method} ($sysex_message, $observer->{context});
          }
          $self->sysex_handle($sysex_message);
        }
        $self->{sysex_data} = [];
        last;
      };
    }
    $Device::Firmata::DEBUG and print "    < $command\n";
  }
}

=head2 sysex_handle ( sysexMessage)

Receive identified sysex packets and convert them into their appropriate
structures and parse them as required.
Typically used only internally by L</messages_handle ( messages )>.

=cut

sub sysex_handle {
  # --------------------------------------------------
  my ( $self, $sysex_message ) = @_;
  my $data = $sysex_message->{data};

  COMMAND_HANDLER: {
    $sysex_message->{command_str} eq 'REPORT_FIRMWARE' and do {
      $self->{metadata}{firmware_version} = sprintf "V_%i_%02i", $data->{major_version}, $data->{minor_version};
      $self->{metadata}{firmware} = $data->{firmware};
      last;
    };

    $sysex_message->{command_str} eq 'CAPABILITY_RESPONSE' and do {
      my $capabilities = $data->{capabilities};
      $self->{metadata}{capabilities} = $capabilities;
      my @analogpins;
      my @inputpins;
      my @outputpins;
      my @pwmpins;
      my @servopins;
      my @shiftpins;
      my @i2cpins;
      my @onewirepins;
      my @stepperpins;
      my @encoderpins;
      my @serialpins;
      my @pulluppins;

      foreach my $pin (keys %$capabilities) {
        if (defined $capabilities->{$pin}) {
          if ($capabilities->{$pin}->{PIN_INPUT+0}) {
            push @inputpins, $pin;
          }
          if ($capabilities->{$pin}->{PIN_OUTPUT+0}) {
            push @outputpins, $pin;
          }
          if ($capabilities->{$pin}->{PIN_ANALOG+0}) {
            push @analogpins, $pin;
            $self->{metadata}{analog_resolutions}{$pin} = $capabilities->{$pin}->{PIN_ANALOG+0}->{resolution};
          }
          if ($capabilities->{$pin}->{PIN_PWM+0}) {
            push @pwmpins, $pin;
            $self->{metadata}{pwm_resolutions}{$pin} = $capabilities->{$pin}->{PIN_PWM+0}->{resolution};
          }
          if ($capabilities->{$pin}->{PIN_SERVO+0}) {
            push @servopins, $pin;
            $self->{metadata}{servo_resolutions}{$pin} = $capabilities->{$pin}->{PIN_SERVO+0}->{resolution};
          }
          if ($capabilities->{$pin}->{PIN_SHIFT+0}) {
            push @shiftpins, $pin;
          }
          if ($capabilities->{$pin}->{PIN_I2C+0}) {
            push @i2cpins, $pin;
          }
          if ($capabilities->{$pin}->{PIN_ONEWIRE+0}) {
            push @onewirepins, $pin;
          }
          if ($capabilities->{$pin}->{PIN_STEPPER+0}) {
            push @stepperpins, $pin;
            $self->{metadata}{stepper_resolutions}{$pin} = $capabilities->{$pin}->{PIN_STEPPER+0}->{resolution};
          }
          if ($capabilities->{$pin}->{PIN_ENCODER+0}) {
            push @encoderpins, $pin;
            $self->{metadata}{encoder_resolutions}{$pin} = $capabilities->{$pin}->{PIN_ENCODER+0}->{resolution};
          }
          if ($capabilities->{$pin}->{PIN_SERIAL+0}) {
            push @serialpins, $pin;
            $self->{metadata}{serial_resolutions}{$pin} = $capabilities->{$pin}->{PIN_SERIAL+0}->{resolution};
          }
          if ($capabilities->{$pin}->{PIN_PULLUP+0}) {
            push @pulluppins, $pin;
          }
        }
      }
      $self->{metadata}{input_pins}   = \@inputpins;
      $self->{metadata}{output_pins}  = \@outputpins;
      $self->{metadata}{analog_pins}  = \@analogpins;
      $self->{metadata}{pwm_pins}     = \@pwmpins;
      $self->{metadata}{servo_pins}   = \@servopins;
      $self->{metadata}{shift_pins}   = \@shiftpins;
      $self->{metadata}{i2c_pins}     = \@i2cpins;
      $self->{metadata}{onewire_pins} = \@onewirepins;
      $self->{metadata}{stepper_pins} = \@stepperpins;
      $self->{metadata}{encoder_pins} = \@encoderpins;
      $self->{metadata}{serial_pins}  = \@serialpins;
      $self->{metadata}{pullup_pins}  = \@pulluppins;
      last;
    };

    $sysex_message->{command_str} eq 'ANALOG_MAPPING_RESPONSE' and do {
      $self->{metadata}{analog_mappings} = $data->{mappings};
      last;
    };

    $sysex_message->{command_str} eq 'PIN_STATE_RESPONSE' and do {
      if (!defined $self->{metadata}{pinstates}) {
        $self->{metadata}{pinstates}     = {};
      };
      $self->{metadata}{pinstates}{ $data->{pin} } = {
        mode  => $data->{mode},
        state => $data->{state},
      };
      last;
    };

    $sysex_message->{command_str} eq 'I2C_REPLY' and do {
      my $observer = $self->{i2c_observer};
      if (defined $observer) {
        $observer->{method}( $data, $observer->{context} );
      }
      last;
    };

    $sysex_message->{command_str} eq 'ONEWIRE_DATA' and do {
      my $pin      = $data->{pin};
      my $observer = $self->{onewire_observer}[$pin];
      if (defined $observer) {
        $observer->{method}( $data, $observer->{context} );
      }
      last;
    };

    $sysex_message->{command_str} eq 'SCHEDULER_DATA' and do {
      my $observer = $self->{scheduler_observer};
      if (defined $observer) {
        $observer->{method}( $data, $observer->{context} );
      }
      last;
    };

    $sysex_message->{command_str} eq 'STRING_DATA' and do {
      my $observer = $self->{string_observer};
      $self->{stringresponse} = $data->{string};
      if (defined $observer) {
        $observer->{method}( $data->{string}, $observer->{context} );
      }
      last;
    };

    $sysex_message->{command_str} eq 'STEPPER_DATA' and do {
      my $stepperNum = $data->{stepperNum};
      my $observer = $self->{stepper_observer}[$stepperNum];
      if (defined $observer) {
        $observer->{method}( $stepperNum, $observer->{context} );
      };
      last;
    };

    $sysex_message->{command_str} eq 'ENCODER_DATA' and do {
      foreach my $encoder_data ( @$data ) {
        my $encoderNum = $encoder_data->{encoderNum};
        my $observer = $self->{encoder_observer}[$encoderNum];
        if (defined $observer) {
          $observer->{method}( $encoderNum, $encoder_data->{value}, $observer->{context} );
        }
      };
      last;
    };

    $sysex_message->{command_str} eq 'SERIAL_DATA' and do {
      my $serialPort = $data->{port};
      my $observer = $self->{serial_observer}[$serialPort];
      if (defined $observer) {
        $observer->{method}( $data, $observer->{context} );
      }
      last;
    };
  }
}

=head2 probe ( )

On device boot time we wait 3 seconds for firmware name
that the target device is using.
If not received the starting message, then we wait for
response another 2 seconds and fire requests for version.
If the response received, then we store protocol version
and analog mapping and capability.

=over

=item * return on success, C<undef> on error

=back

=cut

sub probe {
  # --------------------------------------------------
  my ($self) = @_;
  $self->{metadata}{firmware}         = '';
  $self->{metadata}{firmware_version} = '';
  $self->{metadata}{protocol_version} = '';

  # Wait for 5 seconds only
  my $end_tics = time + 5;
  $self->firmware_version_query();
  $self->protocol_version_query();
  while ( $end_tics >= time ) {
    select( undef, undef, undef, 0.2 );    # wait for responses
    if ( $self->poll && $self->{metadata}{firmware} && $self->{metadata}{firmware_version} && $self->{metadata}{protocol_version} ) {
      $self->{protocol}->{protocol_version} = $self->{protocol}->get_max_supported_protocol_version($self->{metadata}{protocol_version});
      if ( $self->{metadata}{capabilities} ) {
        if ( $self->{metadata}{analog_mappings} ) {
          return 1;
        } else {
          $self->analog_mapping_query();
        }
      } else {
        $self->capability_query();
      }
    } elsif ($end_tics - 2 < time) {
      # version query on last 2 sec only
      $self->firmware_version_query();
      $self->protocol_version_query();
    }
  }
  return;
}

=head2 pin_mode ( pin, mode )

Set mode of Firmata device pin.

=over

=item * parm pin: Firmata device pin

=item * param mode: use a member of constant $BASE from L<Device::Firmata::Constants>

=back

=cut

sub pin_mode {

  # --------------------------------------------------
  my ( $self, $pin, $mode ) = @_;

  die "pin undefined in call to pin_mode() with mode '".$mode."'" unless defined($pin);
  die "unsupported mode '".$mode."' for pin '".$pin."'" unless $self->is_supported_mode($pin,$mode);

  PIN_MODE_HANDLER: {

    ( $mode == PIN_INPUT or $mode == PIN_PULLUP ) and do {
      my $port_number = $pin >> 3;
      $self->{io}->data_write($self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode ));
      $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_DIGITAL => $port_number, 1 ));
      last;
    };

    $mode == PIN_ANALOG and do {
      my $channel = $self->device_pin_to_analog_channel($pin);
      die "pin '".$pin."' is not reported as 'ANALOG' channel by Firmata device" unless defined($channel) && $channel >= 0 && $channel <= 0xF;
      $self->{io}->data_write($self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode ));
      $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_ANALOG => $channel, 1 ));
      last;
    };

    $self->{io}->data_write($self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode ));
  };
  $self->{pin_modes}->{$pin} = $mode;
  return 1;
}

=head2 digital_write ( pin, state )

=over

=item * parm pin: Firmata device pin

=item * param state: new state (0 or 1) for digial pin to set on Firmata device

=back

Deprecation warning:
Writing to pin with mode "PIN_INPUT" is only supported for backward compatibility
to switch pullup on and off. Use sub L</pin_mode ( pin, mode )> with $mode=PIN_PULLUP instead.

=cut

sub digital_write {

  # --------------------------------------------------
  my ( $self, $pin, $state ) = @_;

  die "pin undefined in call to digital_write()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'INPUT', 'PULLUP' or 'OUTPUT'" unless ($self->is_configured_mode($pin,PIN_OUTPUT) or $self->is_configured_mode($pin,PIN_INPUT) or $self->is_configured_mode($pin,PIN_PULLUP));

  my $port_number = $pin >> 3;

  my $pin_offset = $pin % 8;
  my $pin_mask   = 1 << $pin_offset;

  my $port_state = $self->{ports}[$port_number] ||= 0;
  if ($state) {
    $port_state |= $pin_mask;
  }
  else {
    $port_state &= $pin_mask ^ 0xff;
  }
  $self->{ports}[$port_number] = $port_state;
  $self->{io}->data_write($self->{protocol}->message_prepare( DIGITAL_MESSAGE => $port_number, $port_state & 0x7f, $port_state >> 7 ));
  return 1;
}

=head2 digital_read ( pin )

=over

=item * parm pin: Firmata device pin

=item * return last state (0 or 1) of digital pin received from Firmata device

=back

=cut

sub digital_read {

  # --------------------------------------------------
  my ( $self, $pin ) = @_;

  die "pin undefined in call to digital_read()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'INPUT' or 'PULLUP'" unless ($self->is_configured_mode($pin,PIN_INPUT) or $self->is_configured_mode($pin,PIN_PULLUP));

  my $port_number = $pin >> 3;
  my $pin_offset  = $pin % 8;
  my $pin_mask    = 1 << $pin_offset;
  my $port_state  = $self->{input_ports}[$port_number] ||= 0;
  return ( $port_state & $pin_mask ? 1 : 0 );
}

=head2 analog_read ( pin )

=over

=item * parm pin: Firmata device pin

=item * return last value of analog pin received from Firmata device

=back

=cut

sub analog_read {

  # --------------------------------------------------
  my ( $self, $pin ) = @_;

  die "pin undefined in call to analog_read()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'ANALOG'" unless $self->is_configured_mode($pin,PIN_ANALOG);

  my $channel = $self->device_pin_to_analog_channel($pin);
  die "pin '".$pin."' is not reported as 'ANALOG' channel by Firmata device" unless defined($channel) && $channel >= 0 && $channel <= 0xF;
  return $self->{analog_pins}[$channel];
}

=head2 analog_write ( pin, value )

=over

=item * parm pin: Firmata device pin

=item * param state: new value for PWM pin to set on Firmata device

=back

=cut

sub analog_write {

  # --------------------------------------------------
  my ( $self, $pin, $value ) = @_;

  die "pin undefined in call to analog_write()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'PWM'" unless $self->is_configured_mode($pin,PIN_PWM);

  # FIXME: 8 -> 7 bit translation should be done in the protocol module
  my $byte_0 = $value & 0x7f;
  my $byte_1 = $value >> 7;
  return $self->{io}->data_write($self->{protocol}->message_prepare( ANALOG_MESSAGE => $pin, $byte_0, $byte_1 ));
}

=head2 pwm_write ( pin, value )

pmw_write ( pin, value ) is an alias for L</analog_write ( pin, value )>

=cut

*pwm_write = *analog_write;

sub protocol_version_query {
  my $self = shift;
  my $protocol_version_query_packet = $self->{protocol}->packet_query_version;
  return $self->{io}->data_write($protocol_version_query_packet);
}

sub firmware_version_query {
  my $self = shift;
  my $firmware_version_query_packet = $self->{protocol}->packet_query_firmware;
  return $self->{io}->data_write($firmware_version_query_packet);
}

sub capability_query {
  my $self = shift;
  my $capability_query_packet = $self->{protocol}->packet_query_capability();
  return $self->{io}->data_write($capability_query_packet);
}

sub analog_mapping_query {
  my $self = shift;
  my $analog_mapping_query_packet = $self->{protocol}->packet_query_analog_mapping();
  return $self->{io}->data_write($analog_mapping_query_packet);
}

sub pin_state_query {
  my ($self,$pin) = @_;
  my $pin_state_query_packet = $self->{protocol}->packet_query_pin_state($pin);
  return $self->{io}->data_write($pin_state_query_packet);
}

sub sampling_interval {
  my ( $self, $sampling_interval ) = @_;
  my $sampling_interval_packet = $self->{protocol}->packet_sampling_interval($sampling_interval);
  return $self->{io}->data_write($sampling_interval_packet);
}

sub sysex_send  {
  my ( $self, @sysex_data ) = @_;
  my $sysex_packet = $self->{protocol}->packet_sysex(@sysex_data);
  return $self->{io}->data_write($sysex_packet);
}

sub i2c_write {
  my ($self,$address,@data) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_i2c_request($address,0x0,@data));
}

sub i2c_readonce {
  my ($self,$address,$register,$numbytes) = @_;
  my $packet = (defined $numbytes)
    ? $self->{protocol}->packet_i2c_request($address,0x8,$register,$numbytes)
    : $self->{protocol}->packet_i2c_request($address,0x8,$register);
  return $self->{io}->data_write($packet);
}

sub i2c_read {
  my ($self,$address,$register,$numbytes) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_i2c_request($address,0x10,$register,$numbytes));
}

sub i2c_stopreading {
  my ($self,$address) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_i2c_request($address,0x18));
}

sub i2c_config {
  my ( $self, $delay, @data ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_i2c_config($delay,@data));
}

sub servo_write {

  # --------------------------------------------------
  # Sets the SERVO value on an Arduino
  #
  my ( $self, $pin, $value ) = @_;

  die "pin undefined in call to servo_write()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'SERVO'" unless $self->is_configured_mode($pin,PIN_SERVO);

  # FIXME: 8 -> 7 bit translation should be done in the protocol module
  my $byte_0 = $value & 0x7f;
  my $byte_1 = $value >> 7;
  return $self->{io}->data_write($self->{protocol}->message_prepare( ANALOG_MESSAGE => $pin, $byte_0, $byte_1 ));
}

sub servo_config {
  my ( $self, $pin, $args ) = @_;

  die "pin undefined in call to servo_config()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'SERVO'" unless $self->is_configured_mode($pin,PIN_SERVO);

  return $self->{io}->data_write($self->{protocol}->packet_servo_config_request($pin,$args));
}

sub scheduler_create_task {
  my $self = shift;
  my $id=-1;
  my $tasks = $self->{tasks};
  for my $task (@$tasks) {
    if ($id < $task->{id}) {
      $id = $task->{id};
    }
  }
  $id++;
  my $newtask = {
    id => $id,
    data => [],
    time_ms => undef,
  };
  push @$tasks,$newtask;
  return $id;
}

sub scheduler_delete_task {
  my ($self,$id) = @_;
  my $tasks = $self->{tasks};
  for my $task (@$tasks) {
    if ($id == $task->{id}) {
      if (defined $task->{time_ms}) {
        my $packet = $self->{protocol}->packet_delete_task($id);
        $self->{io}->data_write($packet);
      }
      delete $self->{tasks}[$id]; # delete $array[index]; (not delete @array[index];)
      last;
    }
  }
}

sub scheduler_add_to_task {
  my ($self,$id,$packet) = @_;
  my $tasks = $self->{tasks};
  for my $task (@$tasks) {
    if ($id == $task->{id}) {
      my $data = $task->{data};
      push @$data,unpack "C*", $packet;
      last;
    }
  }
}

sub scheduler_schedule_task {
  my ($self,$id,$time_ms) = @_;
  my $tasks = $self->{tasks};
  for my $task (@$tasks) {
    if ($id == $task->{id}) {
      if (!(defined $task->{time_ms})) { # TODO - a bit unclear why I put this test here in the first place. -> TODO: investigate and remove this check if not nessesary
        my $data = $task->{data};
        my $len = @$data;
        my $packet = $self->{protocol}->packet_create_task($id,$len);
        $self->{io}->data_write($packet);
        my $bytesPerPacket = 53; # (64-1)*7/8-2 (1 byte command, 1 byte for subcommand, 1 byte taskid)
        my $j=0;
        my @packetdata;
        for (my $i=0;$i<$len;$i++) {
            push @packetdata,@$data[$i];
            $j++;
            if ($j==$bytesPerPacket) {
              $j=0;
              $packet = $self->{protocol}->packet_add_to_task($id,@packetdata);
            $self->{io}->data_write($packet);
            @packetdata = ();
            }
          }
          if ($j>0) {
            $packet = $self->{protocol}->packet_add_to_task($id,@packetdata);
          $self->{io}->data_write($packet);
          }
      }
      my $packet = $self->{protocol}->packet_schedule_task($id,$time_ms);
      $self->{io}->data_write($packet);
      last;
    }
  }
}

sub scheduler_reset {
  my $self = shift;
  my $packet = $self->{protocol}->packet_reset_scheduler;
  $self->{io}->data_write($packet);
  $self->{tasks} = [];
}

sub scheduler_query_all_tasks {
  my $self = shift;
  my $packet = $self->{protocol}->packet_query_all_tasks;
  $self->{io}->data_write($packet);
}

sub scheduler_query_task {
  my ($self,$id) = @_;
  my $packet = $self->{protocol}->packet_query_task($id);
  $self->{io}->data_write($packet);
}

# SEARCH_REQUEST,
# CONFIG_REQUEST,

#$args = {
# reset => undef | 1,
# skip => undef | 1,
# select => undef | device,
# read => undef | short int,
# delay => undef | long int,
# write => undef | bytes[],
#}

sub onewire_search {
  my ( $self, $pin ) = @_;

  die "pin undefined in call to onewire_search()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'ONEWIRE'" unless $self->is_configured_mode($pin,PIN_ONEWIRE);

  return $self->{io}->data_write($self->{protocol}->packet_onewire_search_request( $pin ));
}

sub onewire_search_alarms {
  my ( $self, $pin ) = @_;

  die "pin undefined in call to onewire_search_alarms()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'ONEWIRE'" unless $self->is_configured_mode($pin,PIN_ONEWIRE);

  return $self->{io}->data_write($self->{protocol}->packet_onewire_search_alarms_request( $pin ));
}

sub onewire_config {
  my ( $self, $pin, $power ) = @_;

  die "pin undefined in call to onewire_config()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'ONEWIRE'" unless $self->is_configured_mode($pin,PIN_ONEWIRE);

  return $self->{io}->data_write($self->{protocol}->packet_onewire_config_request( $pin, $power ));
}

sub onewire_reset {
  my ( $self, $pin ) = @_;
  return $self->onewire_command_series( $pin, {reset => 1} );
}

sub onewire_skip {
  my ( $self, $pin ) = @_;
  return $self->onewire_command_series( $pin, {skip => 1} );
}

sub onewire_select {
  my ( $self, $pin, $device ) = @_;
  return $self->onewire_command_series( $pin, {select => $device} );
}

sub onewire_read {
  my ( $self, $pin, $numBytes ) = @_;
  return $self->onewire_command_series( $pin, {read => $numBytes} );
}

sub onewire_write {
  my ( $self, $pin, @data ) = @_;
  return $self->onewire_command_series( $pin, {write => \@data} );
}

sub onewire_command_series {
  my ( $self, $pin, $args ) = @_;

  die "pin undefined in call to onewire_command_series()" unless defined($pin);
  die "pin '".$pin."' is not configured for mode 'ONEWIRE'" unless $self->is_configured_mode($pin,PIN_ONEWIRE);

  return $self->{io}->data_write($self->{protocol}->packet_onewire_request( $pin, $args ));
}

sub stepper_config {
  my ( $self, $stepperNum, $interface, $stepsPerRev, $directionPin, $stepPin, $motorPin3, $motorPin4 ) = @_;
  die "unsupported mode 'STEPPER' for pin '".$directionPin."'" unless $self->is_supported_mode($directionPin,PIN_STEPPER);
  die "unsupported mode 'STEPPER' for pin '".$stepPin."'" unless $self->is_supported_mode($stepPin,PIN_STEPPER);
  die "unsupported mode 'STEPPER' for pin '".$motorPin3."'" unless (!(defined $motorPin3) or $self->is_supported_mode($motorPin3,PIN_STEPPER));
  die "unsupported mode 'STEPPER' for pin '".$motorPin4."'" unless (!(defined $motorPin4) or $self->is_supported_mode($motorPin4,PIN_STEPPER));
  return $self->{io}->data_write($self->{protocol}->packet_stepper_config( $stepperNum, $interface, $stepsPerRev, $directionPin, $stepPin, $motorPin3, $motorPin4 ));
}

sub stepper_step {
  my ( $self, $stepperNum, $direction, $numSteps, $stepSpeed, $accel, $decel ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_stepper_step( $stepperNum, $direction, $numSteps, $stepSpeed, $accel, $decel ));
}

sub encoder_attach {
  my ( $self, $encoderNum, $pinA, $pinB ) = @_;
  die "unsupported mode 'ENCODER' for pin '".$pinA."'" unless $self->is_supported_mode($pinA,PIN_ENCODER);
  die "unsupported mode 'ENCODER' for pin '".$pinB."'" unless $self->is_supported_mode($pinB,PIN_ENCODER);
  return $self->{io}->data_write($self->{protocol}->packet_encoder_attach( $encoderNum, $pinA, $pinB ));
}

sub encoder_report_position {
  my ( $self, $encoderNum ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_encoder_report_position( $encoderNum ));
}

sub encoder_report_positions {
  my ( $self ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_encoder_report_positions());
}

sub encoder_reset_position {
  my ( $self, $encoderNum ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_encoder_reset_position( $encoderNum ));
}

sub encoder_report_auto {
  my ( $self, $enable ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_encoder_report_auto( $enable ));
}

sub encoder_detach {
  my ( $self, $encoderNum ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_encoder_detach( $encoderNum ));
}

sub serial_write {
  my ( $self, $port, @data ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_serial_write( $port, @data ));
}

sub serial_read {
  my ( $self, $port, $numbytes ) = @_;
  if ($port >= 8) {
    $self->{io}->data_write($self->{protocol}->packet_serial_listen( $port ));
  }
  return $self->{io}->data_write($self->{protocol}->packet_serial_read( $port, 0x00, $numbytes ));
}

sub serial_stopreading {
  my ( $self, $port) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_serial_read( $port, 0x01, 0 ));
}

sub serial_config {
  my ( $self, $port, $baud, $rxPin, $txPin ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_serial_config( $port, $baud, $rxPin, $txPin ));
}

=head2 poll ( )

Call this function every once in a while to
check up on the status of the comm port, receive
and process data from the Firmata device

=cut

sub poll {

  # --------------------------------------------------
  my $self     = shift;
  my $buf      = $self->{io}->data_read(2048);
  my $messages = $self->{protocol}->message_data_receive($buf) or return;
  $self->messages_handle($messages);
  return $messages;
}

=head2 observe_digital ( pin, observer, context )

Register callback sub that will be called by L</messages_handle ( messages )>
if a new value for a digital pin was received from the Firmata device.

=over

=item * parm pin: Firmata device pin

=item * parm observer: callback sub reference with the parameters pin, oldState, newState, context

=item * parm context: context value passed as last parameter to callback sub

=back

=cut

sub observe_digital {
  my ( $self, $pin, $observer, $context ) = @_;
  die "unsupported mode 'INPUT' for pin '".$pin."'" unless ($self->is_supported_mode($pin,PIN_INPUT));
  $self->{digital_observer}[$pin] = {
      method  => $observer,
      context => $context,
    };
  my $port_number = $pin >> 3;
  $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_DIGITAL => $port_number, 1 ));
  return 1;
}

=head2 observe_analog ( pin, observer, context )

Register callback sub that will be called by L</messages_handle ( messages )>
if the value of the analog pin received from the Firmata device has changed.

=over

=item * parm pin: Firmata device pin

=item * parm observer: callback sub reference with the parameters pin, oldValue, newValue, context

=item * parm context: context value passed as last parameter to callback sub

=back

=cut

sub observe_analog {
  my ( $self, $pin, $observer, $context ) = @_;
  die "pin '".$pin."' is not configured for mode 'ANALOG'" unless $self->is_configured_mode($pin,PIN_ANALOG);
  $self->{analog_observer}[$pin] =  {
      method  => $observer,
      context => $context,
    };
  my $channel = $self->device_pin_to_analog_channel($pin);
  die "pin '".$pin."' is not reported as 'ANALOG' channel by Firmata device" unless defined($channel) && $channel >= 0 && $channel <= 0xF;
  $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_ANALOG => $channel, 1 ));
  return 1;
}

sub observe_sysex {
  my ( $self, $observer, $context ) = @_;
  $self->{sysex_observer} = {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_i2c {
  my ( $self, $observer, $context ) = @_;
  return undef if (defined $self->{metadata}->{i2cpins} && @$self->{metadata}->{i2cpins} == 0 );
  $self->{i2c_observer} =  {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_onewire {
  my ( $self, $pin, $observer, $context ) = @_;
  die "unsupported mode 'ONEWIRE' for pin '".$pin."'" unless ($self->is_supported_mode($pin,PIN_ONEWIRE));
  $self->{onewire_observer}[$pin] =  {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_stepper {
  my ( $self, $stepperNum, $observer, $context ) = @_;
#TODO validation?  die "unsupported mode 'STEPPER' for pin '".$pin."'" unless ($self->is_supported_mode($pin,PIN_STEPPER));
  $self->{stepper_observer}[$stepperNum] = {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_encoder {
  my ( $self, $encoderNum, $observer, $context ) = @_;
#TODO validation?  die "unsupported mode 'ENCODER' for pin '".$pin."'" unless ($self->is_supported_mode($pin,PIN_ENCODER));
  $self->{encoder_observer}[$encoderNum] = {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_serial {
  my ( $self, $port, $observer, $context ) = @_;
  return undef if (defined $self->{metadata}->{serialpins} && @$self->{metadata}->{serialpins} == 0 );
  $self->{serial_observer}[$port] =  {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_scheduler {
  my ( $self, $observer, $context ) = @_;
  $self->{scheduler_observer} = {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub observe_string {
  my ( $self, $observer, $context ) = @_;
  $self->{string_observer} = {
      method  => $observer,
      context => $context,
    };
  return 1;
}

sub is_supported_mode {
  my ($self,$pin,$mode) = @_;
  return undef if (!defined($pin) || (defined $self->{metadata}->{capabilities} && (!(defined $self->{metadata}->{capabilities}->{$pin}) || !(defined $self->{metadata}->{capabilities}->{$pin}->{$mode}))));
  return 1;
}

=head2 device_pin_to_analog_channel ( pin )

=over

=item * parm pin: Firmata device pin

=item * return analog channel number if analog mapping is available (e.g. by calling L</probe ( )>),
               C<undef> if given pin is not mapped as an analog channel or
               given pin if analog mapping is not available

=back

=cut

sub device_pin_to_analog_channel {
  my ($self,$pin) = @_;

  if (defined $self->{metadata}{analog_mappings}) {
    my $analog_mappings = $self->{metadata}{analog_mappings};
    foreach my $channel (keys %$analog_mappings) {
      if ($analog_mappings->{$channel} == $pin) {
        return $channel;
      }
    }
    return undef;
  }

  return $pin;
}

=head2 is_configured_mode ( pin, mode )

Verify if pin was configured with L</pin_mode ( pin, mode )> for requested mode.

=over

=item * parm pin: Firmata device pin

=item * param mode: use a member of constant $BASE from L<Device::Firmata::Constants>

=item * return 1 on success or C<undef> on error

=back

=cut

sub is_configured_mode {
  my ($self,$pin,$mode) = @_;
  return undef if (!defined($pin) || !defined $self->{pin_modes}->{$pin} || $self->{pin_modes}->{$pin} != $mode);
  return 1;
}

=head1 SEE ALSO

L<Device::Firmata::Constants>

=cut

1;
