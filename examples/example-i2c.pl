#!/usr/bin/perl

use strict;
use lib '../lib';
use Data::Dumper;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
use DateTime;
$|++;

$Device::Firmata::DEBUG = 0;

my $device = Device::Firmata->open('/dev/ttyACM0')
  or die "Could not connect to Firmata Server";

$device->system_reset();
$device->observe_i2c( \&onI2CMessage );

$device->pin_mode( 18, PIN_I2C );
$device->pin_mode( 19, PIN_I2C );
$device->i2c_config(0);
$device->sampling_interval(1000);

# DS1307 ADDRESS MAP
# 0x00 SECONDS
# 0x01 MINUTES
# 0x02 HOURS
# 0x03 DAY
# 0x04 DATE
# 0x05 MONTH
# 0x06 YEAR
# 0x07 CONTROL
# 0x08 RAM 56 x 8
# ...
# 0x3F

# DS1307 Control Register:
# BIT 7 OUT
# BIT 6 0
# BIT 5 0
# BIT 4 SQWE
# BIT 3 0
# BIT 2 0
# BIT 1 RS1
# BIT 0 RS0

my $now = DateTime->now;

my $DS1307=0b1101000;

$device->i2c_write(
$DS1307,        #slave address
0,              #register
$now->second(), #data...
$now->minute(),
$now->hour(),
($now->day_of_week()+1)%7, #DS1307 week starts on Sunday
$now->day(),
$now->month(),
$now->year()%100,
0);             #control

$device->i2c_read($DS1307,0,7);

while(1) {
	$device->poll();
	select(undef,undef,undef,0.1);
}

sub onI2CMessage {
	my $i2cdata = shift;
		
	my $address = $i2cdata->{address};
	my $register = $i2cdata->{register};
	my $data = $i2cdata->{data};
	
	my @days = ('Sun','Mon','Tue','Wed','Thi','Fri','Sat');

	my $second = shift @$data;
	my $minute = shift @$data;
	my $hour   = shift @$data;
	my $day    = shift @$data;
	my $date   = shift @$data;
	my $month  = shift @$data;
	my $year   = shift @$data;
	
	printf "%s, 20%02d-%02d-%02d %02d:%02d:%02d UTC\n",$days[$day],$year,$month,$date,$hour,$minute,$second;
}