package Device::Firmata;

use strict;
use warnings;

use Device::Firmata::Constants;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

=head1 NAME

Device::Firmata - Perl interface to Firmata for the arduino platform.

=head1 VERSION

Version 0.64

=cut

our $VERSION = '0.64';
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

=head1 SUBROUTINES/METHODS

=head2 open(serialPort)

Establish a serial connection with an Arduino micro-controller. The first argument is the name of the serial device mapped to the arduino, e.g. '/dev/ttyUSB0' or 'COM9'.

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

=head2 listen(host, port)

Start a TCP server bound to given local address and port for the arduino to connect to.

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

=head1 LICENSE

    Copyright (C) 2010 amimato
    Copyright (C) 2012 ntruchsess
    Copyright (C) 2016 jnsbyr

    This is free software; you can redistribute it and/or modify it under
    the same terms as the Perl 5 programming language system itself.

    See http://dev.perl.org/licenses/ for more information.

=cut

1;
