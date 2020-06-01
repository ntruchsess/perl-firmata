package Device::Firmata::Platform::Arduino;

=head1 NAME

Device::Firmata::Platform::Arduino - subclass for Arduino Firmata devices

=head1 DESCRIPTION

Subclass of L<Device::Firmata::Platform> to provide a specific
implementation for Arduino Firmata devices.

Note: Currently there is no specific implemention, consider using the
base class directly.

=cut

use strict;
use warnings;
use Device::Firmata::Platform;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Platform';

1;
