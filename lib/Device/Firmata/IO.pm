package Device::Firmata::IO;

use strict;
use vars qw/ $SERIAL_CLASS /;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
        handle   => undef,
        baudrate => 57600,
    };

$SERIAL_CLASS = $^O eq 'MSWin32' ? 'Win32::Serialport' 
                                 : 'Device::SerialPort';
eval "require $SERIAL_CLASS";

sub open {
# --------------------------------------------------
    my ( $pkg, $serial_port, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

    my $serial_obj = $SERIAL_CLASS->new( $serial_port, 1, 0 ) or return;
    $self->{handle} = $serial_obj;
    $self->{handle}->baudrate($self->{baudrate});
    $self->{handle}->databits(8);
    $self->{handle}->stopbits(1);

    return $self;
}

sub data_write {
# --------------------------------------------------
# Dump a bunch of data into the comm port
#
    my ( $self, $buf ) = @_;
    $Device::Firmata::DEBUG and print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
    return $self->{handle}->write( $buf );
}

sub data_read {
# --------------------------------------------------
# We fetch up to $bytes from the comm port
# This function is non-blocking
#
    my ( $self, $bytes ) = @_;
    my ( $count, $string ) = $self->{handle}->read($bytes);
    if ( $Device::Firmata::DEBUG and $string ) {
        print "<".join(",",map{sprintf"%02x",ord$_}split//,$string)."\n";
    }
    return $string;
}

1;
