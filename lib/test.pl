#!/usr/bin/perl

use strict;
use Data::Dumper;
use Firmata::Arduino::Tied::Constants qw/ :all /;
use Firmata::Arduino::Tied::Protocol;
use Firmata::Arduino::Tied;
$|++;

my $device = Firmata::Arduino::Tied->open('/dev/ttyUSB0');

$device->probe;

