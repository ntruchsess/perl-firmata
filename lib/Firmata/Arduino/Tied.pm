package Firmata::Arduino::Tied;

use strict;
use Firmata::Arduino::Tied::Constants;
use Firmata::Arduino::Tied::Device;
use Firmata::Arduino::Tied::Base
    ISA => 'Firmata::Arduino::Tied::Base',
    FIRMATA_ATTRIBS => {
    };

sub open {
# --------------------------------------------------
# Establish a connection with the serial port
#
    my ( $self, $serial_port, $opts ) = @_;

# We're going to try and create the device connection
# first...
    my $device = Firmata::Arduino::Tied::Device->open($serial_port,$opts);

    return $device;
}

1;
