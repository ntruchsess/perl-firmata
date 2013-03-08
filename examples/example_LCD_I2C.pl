#!/usr/bin/perl

use strict;
use warnings;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
use LiquidCrystal_I2C;

$Device::Firmata::DEBUG = 1;

my $device = Device::Firmata->open('/dev/ttyUSB0')
  or die "Could not connect to Firmata Server";

$device->system_reset();
$device->observe_i2c( \&onI2CMessage );

$device->pin_mode( 18, PIN_I2C );
$device->pin_mode( 19, PIN_I2C );
$device->i2c_config(0);
$device->sampling_interval(1000);

my $lcd = LiquidCrystal_I2C->new( 0x3f, 16, 2 );
$lcd->attach($device);

my @bell     = ( 0x4, 0xe,  0xe,  0xe,  0x1f, 0x0,  0x4 );
my @note     = ( 0x2, 0x3,  0x2,  0xe,  0x1e, 0xc,  0x0 );
my @clock    = ( 0x0, 0xe,  0x15, 0x17, 0x11, 0xe,  0x0 );
my @heart    = ( 0x0, 0xa,  0x1f, 0x1f, 0xe,  0x4,  0x0 );
my @duck     = ( 0x0, 0xc,  0x1d, 0xf,  0xf,  0x6,  0x0 );
my @check    = ( 0x0, 0x1,  0x3,  0x16, 0x1c, 0x8,  0x0 );
my @cross    = ( 0x0, 0x1b, 0xe,  0x4,  0xe,  0x1b, 0x0 );
my @retarrow = ( 0x1, 0x1,  0x5,  0x9,  0x1f, 0x8,  0x4 );

$lcd->init();
$lcd->backlight();

$lcd->createChar( 0, \@bell );
$lcd->createChar( 1, \@note );
$lcd->createChar( 2, \@clock );
$lcd->createChar( 3, \@heart );
$lcd->createChar( 4, \@duck );
$lcd->createChar( 5, \@check );
$lcd->createChar( 6, \@cross );
$lcd->createChar( 7, \@retarrow );
$lcd->home();

$lcd->print("Hello World...");
$lcd->setCursor( 0, 1 );
$lcd->print(" I ");
$lcd->write(3);
$lcd->print(" Firmata!");
select( undef, undef, undef, 5 );
displayKeyCodes();
while (1) {
	$device->poll();
	select( undef, undef, undef, 0.1 );
}

# display all keycodes
sub displayKeyCodes() {
	my $i = 0;
	while (1) {
		$lcd->clear();
		$lcd->print(sprintf("Codes %2x-%2x",$i,$i + 16));
		$lcd->setCursor( 0, 1 );
		for ( my $j = 0 ; $j < 16 ; $j++ ) {
			$lcd->write( $i + $j );
		}
		$i += 16;
		select( undef, undef, undef, 4 );
	}
}

sub onI2CMessage {
	my $i2cdata = shift;

	my $address  = $i2cdata->{address};
	my $register = $i2cdata->{register};
	my $data     = $i2cdata->{data};

	print "$address, $register, $data\n";
}

