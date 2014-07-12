package Device::Firmata::Platform;

=head1 NAME

Device::Firmata::Platform - Platform specifics

=cut

use strict;
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
  scheduler_observer          => undef,
  string_observer             => undef,
  rc_observer                 => [],

  # To track scheduled tasks
  tasks                       => [],

  # For information about the device. eg: firmware version
  metadata                    => {},

  # latest STRING_DATA response:
  stringresponse              => {},
  };

=head2 open

Connect to the IO port and do some basic operations
to find out how to connect to the device

=cut

sub attach {
  # --------------------------------------------------
  # Attach to an open IO port and do some basic operations
  # to find out how to connect to the device
  #
  my ( $pkg, $port, $opts ) = @_;
  my $self = ref $pkg ? $pkg : $pkg->new($opts);
  $self->{io} = $port or return;
  $self->{protocol} = Device::Firmata::Protocol->new($opts) or return;
  return $self;
}

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
  $self->{scheduler_observer} = undef;
  $self->{rc_observer}        = [];
  $self->{tasks}              = [];
  $self->{metadata}           = {};
}

sub close {
  my $self = shift;
  $self->{io}->close();
  $self->detach();
}

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
  $self->{scheduler_observer} = undef;
  $self->{rc_observer}        = [];
  $self->{tasks}              = [];
  $self->{metadata}           = {};
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
        $self->{metadata}{firmware_version} = sprintf "V_%i_%02i",
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

=head2 sysex_handle

Receive identified sysex packets and convert them
into their appropriate structures and parse
them as required

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
      my @rcoutputpins;
      my @rcinputpins;
      
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
          if ($capabilities->{$pin}->{PIN_RCOUTPUT+0}) {
          	push @rcoutputpins, $pin;
          }
          if ($capabilities->{$pin}->{PIN_RCINPUT+0}) {
          	push @rcinputpins, $pin;
          }
        }
      }
      $self->{metadata}{input_pins}    = \@inputpins;
      $self->{metadata}{output_pins}   = \@outputpins;
      $self->{metadata}{analog_pins}   = \@analogpins;
      $self->{metadata}{pwm_pins}      = \@pwmpins;
      $self->{metadata}{servo_pins}    = \@servopins;
      $self->{metadata}{shift_pins}    = \@shiftpins;
      $self->{metadata}{i2c_pins}      = \@i2cpins;
      $self->{metadata}{onewire_pins}  = \@onewirepins;
      $self->{metadata}{stepper_pins}  = \@stepperpins;
      $self->{metadata}{encoder_pins}  = \@encoderpins;
      $self->{metadata}{rcoutput_pins} = \@rcoutputpins;
      $self->{metadata}{rcinput_pins}  = \@rcinputpins;
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

    $sysex_message->{command_str} eq 'RC_DATA' and do {
      my $pin      = $data->{pin};
      my $observer = $self->{rc_observer}[$pin];
      if (defined $observer) {
        $observer->{method}( $data->{command}, $data->{data}, $observer->{context} );
      }
      last;
    };
  }
}

=head2 probe

On device boot time we wait 3 seconds for firmware name
that the target device is using.
If not received the starting message, then we wait for
response another 2 seconds and fire requests for version.
If the response received, then we store protocol version
and analog mapping and capability.

=cut

sub probe {
  # --------------------------------------------------
  my ($self) = @_;
  $self->{metadata}{firmware}         = '';
  $self->{metadata}{firmware_version} = '';

  # Wait for 5 seconds only
  my $end_tics = time + 5;
  $self->firmware_version_query();
  while ( $end_tics >= time ) {
    select( undef, undef, undef, 0.2 );    # wait for response
    if ( $self->poll && $self->{metadata}{firmware} && $self->{metadata}{firmware_version} ) {
      $self->{protocol}->{protocol_version} = $self->{metadata}{firmware_version};
      if ( $self->{metadata}{capabilities} ) {
        if ( $self->{metadata}{analog_mappings} ) {
          return 1;
        } else {
          $self->analog_mapping_query();
        }
      } else {
        $self->capability_query();
      }
    } else {
      $self->firmware_version_query() unless $end_tics - 2 >= time;    # version query on last 2 sec only
    }
  }
  return;
}

=head2 pin_mode

Similar to the pinMode function on the
arduino

=cut

sub pin_mode {

  # --------------------------------------------------
  my ( $self, $pin, $mode ) = @_;

  die "unsupported mode '".$mode."' for pin '".$pin."'" unless $self->is_supported_mode($pin,$mode);

  PIN_MODE_HANDLER: {

    ( $mode == PIN_INPUT ) and do {
      my $port_number = $pin >> 3;
      $self->{io}->data_write($self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode ));
      $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_DIGITAL => $port_number, 1 ));
      last;
    };

    $mode == PIN_ANALOG and do {
      $self->{io}->data_write($self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode ));
      $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_ANALOG => $pin, 1 ));
      last;
    };

    $self->{io}->data_write($self->{protocol}->message_prepare( SET_PIN_MODE => 0, $pin, $mode ));
  };
  $self->{pin_modes}->{$pin} = $mode;
  return 1;
}

=head2 digital_write

Analogous to the digitalWrite function on the
arduino

=cut

sub digital_write {

  # --------------------------------------------------
  my ( $self, $pin, $state ) = @_;
  die "pin '".$pin."' is not configured for mode 'INPUT' or 'OUTPUT'" unless ($self->is_configured_mode($pin,PIN_OUTPUT) or $self->is_configured_mode($pin,PIN_INPUT));
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

=head2 digital_read

Analogous to the digitalRead function on the
arduino

=cut

sub digital_read {

  # --------------------------------------------------
  my ( $self, $pin ) = @_;
  die "pin '".$pin."' is not configured for mode 'INPUT'" unless $self->is_configured_mode($pin,PIN_INPUT);
  my $port_number = $pin >> 3;
  my $pin_offset  = $pin % 8;
  my $pin_mask    = 1 << $pin_offset;
  my $port_state  = $self->{input_ports}[$port_number] ||= 0;
  return ( $port_state & $pin_mask ? 1 : 0 );
}

=head2 analog_read

Fetches the analog value of a pin

=cut

sub analog_read {

  # --------------------------------------------------
  #
  my ( $self, $pin ) = @_;
  die "pin '".$pin."' is not configured for mode 'ANALOG'" unless $self->is_configured_mode($pin,PIN_ANALOG);
  return $self->{analog_pins}[$pin];
}

=head2 analog_write

=cut

sub analog_write {

  # --------------------------------------------------
  # Sets the PWM value on an arduino
  #
  my ( $self, $pin, $value ) = @_;
  die "pin '".$pin."' is not configured for mode 'PWM'" unless $self->is_configured_mode($pin,PIN_PWM);

  # FIXME: 8 -> 7 bit translation should be done in the protocol module
  my $byte_0 = $value & 0x7f;
  my $byte_1 = $value >> 7;
  return $self->{io}->data_write($self->{protocol}->message_prepare( ANALOG_MESSAGE => $pin, $byte_0, $byte_1 ));
}

=head2 pwm_write

pmw_write is an alias for analog_write

=cut

*pwm_write = *analog_write;

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

sub sysex_send {
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
  # Sets the SERVO value on an arduino
  #
  my ( $self, $pin, $value ) = @_;
  die "pin '".$pin."' is not configured for mode 'SERVO'" unless $self->is_configured_mode($pin,PIN_SERVO);

  # FIXME: 8 -> 7 bit translation should be done in the protocol module
  my $byte_0 = $value & 0x7f;
  my $byte_1 = $value >> 7;
  return $self->{io}->data_write($self->{protocol}->message_prepare( ANALOG_MESSAGE => $pin, $byte_0, $byte_1 ));
}

sub servo_config {
  my ( $self, $pin, $args ) = @_;
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
  die "pin '".$pin."' is not configured for mode 'ONEWIRE'" unless $self->is_configured_mode($pin,PIN_ONEWIRE);
  return $self->{io}->data_write($self->{protocol}->packet_onewire_search_request( $pin ));
}

sub onewire_search_alarms {
  my ( $self, $pin ) = @_;
  die "pin '".$pin."' is not configured for mode 'ONEWIRE'" unless $self->is_configured_mode($pin,PIN_ONEWIRE);
  return $self->{io}->data_write($self->{protocol}->packet_onewire_search_alarms_request( $pin ));
}

sub onewire_config {
  my ( $self, $pin, $power ) = @_;
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

sub rcoutput_send_code {
  my ( $self, $sendCommand, $pin, @code ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_rcoutput_code( $sendCommand, $pin, @code ));
}

sub rc_set_parameter {
  my ( $self, $parameter, $pin, $value ) = @_;
  return $self->{io}->data_write($self->{protocol}->packet_rc_parameter( $parameter, $pin, $value ));
}

=head2 poll

Call this function every once in a while to
check up on the status of the comm port, receive
and process data from the arduino

=cut

sub poll {

  # --------------------------------------------------
  my $self     = shift;
  my $buf      = $self->{io}->data_read(2048);
  my $messages = $self->{protocol}->message_data_receive($buf) or return;
  $self->messages_handle($messages);
  return $messages;
}

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

sub observe_analog {
  my ( $self, $pin, $observer, $context ) = @_;
  die "unsupported mode 'ANALOG' for pin '".$pin."'" unless ($self->is_supported_mode($pin,PIN_ANALOG));
  $self->{analog_observer}[$pin] =  {
      method  => $observer,
      context => $context,
    };
  $self->{io}->data_write($self->{protocol}->message_prepare( REPORT_ANALOG => $pin, 1 ));
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

sub observe_rc {
  my ( $self, $pin, $observer, $context ) = @_;
  $self->{rc_observer}[$pin] =  {
      method  => $observer,
      context => $context,
  };
  return 1;
}

sub is_supported_mode {
  my ($self,$pin,$mode) = @_;
  return undef if (defined $self->{metadata}->{capabilities} and (!(defined $self->{metadata}->{capabilities}->{$pin}) or !(defined $self->{metadata}->{capabilities}->{$pin}->{$mode})));
  return 1;
}
 
sub is_configured_mode {
  my ($self,$pin,$mode) = @_;
  return undef if (!defined $self->{pin_modes}->{$pin} or $self->{pin_modes}->{$pin} != $mode);
  return 1;
}

1;
