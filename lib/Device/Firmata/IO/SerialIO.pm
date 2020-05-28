package Device::Firmata::IO::SerialIO;

=head1 NAME

Device::Firmata::IO::SerialIO - implement the low level serial IO.

=cut

use strict;
use warnings;

use vars qw/ $SERIAL_CLASS /;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
        handle   => undef,
        baudrate => 57600,
    };

$SERIAL_CLASS = $^O eq 'MSWin32' ? 'Win32::SerialPort'
                                 : 'Device::SerialPort';
eval "require $SERIAL_CLASS";


=head2 open ( serialPort , [opts] )

Establish a serial connection with a Firmata device. The first parameter is the name of the serial device connected with the Firmata device, e.g. '/dev/ttyUSB0' or 'COM9'. The second parameter is  an optional hash of parameters for the serial port. The parameter C<baudrate> is supported and defaults to C<57600>. Returns a C<Device::Firmata::IO::SerialIO> object. Typically called internally by the C<open> method of L<Device::Firmata>.

=cut

sub open {
# --------------------------------------------------
  my ( $pkg, $serial_port, $opts ) = @_;
  my $self = ref $pkg ? $pkg : $pkg->new($opts);
  my $serial_obj = $SERIAL_CLASS->new( $serial_port, 1, 0 ) or return;
  $self->attach($serial_obj,$opts);
  $self->{handle}->baudrate($self->{baudrate});
  $self->{handle}->databits(8);
  $self->{handle}->stopbits(1);
  return $self;
}


=head2 attach ( serialPort )

Assign a L<Device::SerialPort> (or L<Win32::SerialPort>) as IO port and return a L<Device::Firmata::IO::SerialIO> object. Typically used internally by the C<open()> method.

=cut

sub attach {
  my ( $pkg, $serial_obj, $opts ) = @_;
  my $self = ref $pkg ? $pkg : $pkg->new($opts);
  $self->{handle} = $serial_obj;
  return $self;
}


=head2 data_write

Send a bunch of data to the Firmata device. Typically used internally by L<Device::Firmata::Platform>.

=cut

sub data_write {
# --------------------------------------------------
  my ( $self, $buf ) = @_;
  $Device::Firmata::DEBUG and print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
  return $self->{handle}->write( $buf );
}


=head2 data_read

Fetch up to given number of bytes from the serial port. This function is non-blocking. Returns the received data. Typically used internally by L<Device::Firmata::Platform>.

=cut

sub data_read {
# --------------------------------------------------
  my ( $self, $bytes ) = @_;
  my ( $count, $string ) = $self->{handle}->read($bytes);
  print "<".join(",",map{sprintf"%02x",ord$_}split//,$string)."\n" if ( $Device::Firmata::DEBUG and $string );
  return $string;
}


=head2 close

Close serial connection to Firmata device.

=cut

sub close($) {
# --------------------------------------------------
  my ( $self ) = @_;
  if ($self->{handle}) {
    $self->{handle}->close();
    delete $self->{handle};
  }
}


=head1 SEE ALSO

L<Device::Firmata::Base>

=cut

1;
