package Firmata::Arduino::Tied::IO;

use strict;
use vars qw/ $SERIAL_CLASS /;
use Firmata::Arduino::Tied::Base
    ISA => 'Firmata::Arduino::Tied::Base',
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

    $self->{handle} = $SERIAL_CLASS->new( $serial_port, 1, 0 ) or return;
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
    print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
    return $self->{handle}->write( $buf );
}

sub data_read {
# --------------------------------------------------
# We fetch up to $bytes from the comm port
# This function is non-blocking
#
    my ( $self, $bytes ) = @_;
    my ( $count, $string ) = $self->{handle}->read($bytes);
    if ( $string ) {
        print "<".join(",",map{sprintf"%02x",ord$_}split//,$string)."\n";
    }
    return $string;
}

1;
