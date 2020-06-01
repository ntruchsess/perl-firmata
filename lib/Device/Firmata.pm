package Device::Firmata;

use strict;
use warnings;

use Device::Firmata::Constants;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

=head1 NAME

Device::Firmata - module for controlling Firmata devices

=head1 DESCRIPTION

This module allows a computer running Perl to connect to Firmata devices (Arduinos and compatible, including ESP8266), either via serial I/O (RS-232, USB, etc.) or TCP/IP (LAN, WiFi). Protocol details can be found at L<https://github.com/firmata/protocol>.

=head1 VERSION

Version 0.69

=cut

our $VERSION = '0.69';
our $DEBUG = 0;


=head1 SYNOPSIS

    use strict;
    use warnings;

    use Device::Firmata::Constants qw/ :all /;
    use Device::Firmata;

    use Time::HiRes 'sleep';

    $|++;

    my $led_pin = 13;

    my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";
    $device->pin_mode($led_pin=>PIN_OUTPUT);
    my $iteration = 0;
    while (1) {
        my $strobe_state = $iteration++%2;
        $device->digital_write($led_pin=>$strobe_state);
        sleep 0.5;
    }

=head1 METHODS

=head2 open ( serialPort , [opts] )

Establish a serial connection with a Firmata device. The first parameter is the name of the serial device connected with the Firmata device, e.g. '/dev/ttyUSB0' or 'COM9'. The second parameter is  an optional hash of parameters for the serial port. The parameter C<baudrate> is supported and defaults to C<57600>. Returns a L<Device::Firmata::Platform> object.

=cut

sub open {
# --------------------------------------------------
# Establish a connection to Arduino via the serial port
#
  my ( $self, $serial_port, $opts ) = @_;

# We're going to try and create the device connection first...
  my $package = "Device::Firmata::Platform";
  eval "require $package";
  my $serialio = "Device::Firmata::IO::SerialIO";
  eval "require $serialio";

  my $io = $serialio->open( $serial_port, $opts );
  my $platform = $package->attach( $io, $opts ) or die "Could not connect to Firmata Server";

	# Figure out what platform we're running on
  $platform->probe;
  return $platform;
}

=head2 listen ( host, port, [opts] )

Start a TCP server bound to given local address and port for the Arduino to connect to. Returns a L<Device::Firmata::IO::NetIO> object. An implementation example can be found in file F<examples/example-tcpserver.pl>.

=cut

sub listen {
# --------------------------------------------------
# Listen on socket and wait for Arduino to establish a connection
#
  my ( $pkg, $ip, $port, $opts ) = @_;

  my $netio = "Device::Firmata::IO::NetIO";
  eval "require $netio";

  return $netio->listen( $ip, $port, $opts ) || die "Could not bind to socket";
}

=head1 EXAMPLES

In the folder F<examples> you will find more than 15 implementation examples for various Firmata I/O operations including digital I/O, PWM, stepper and encoder as well as bus I/O for I2C and 1-Wire.

=head1 SEE ALSO

L<Device::Firmata::Platform>

=head1 LICENSE

Copyright (C) 2010 Aki Mimoto

Copyright (C) 2012 Norbert Truchsess

Copyright (C) 2016 Jens B.

This is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;
