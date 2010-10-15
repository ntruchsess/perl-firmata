package Device::Firmata;

use strict;
use vars qw/ $DEBUG /;
use Device::Firmata::Constants;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

$DEBUG = 0;

sub open {
# --------------------------------------------------
# Establish a connection with the serial port
#
    my ( $self, $serial_port, $opts ) = @_;

# We're going to try and create the device connection first...
    my $package = "Device::Firmata::Platform";
    eval "require $package";
    my $device = $package->open($serial_port,$opts);

# Figure out what platform we're running on
    $device->probe;

    return $device;
}

1;
