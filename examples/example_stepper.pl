#!/usr/bin/perl

use strict;
use warnings;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;

#$Device::Firmata::DEBUG = 1;

my $device = Device::Firmata->open('/dev/ttyACM0')
  or die "Could not connect to Firmata Server";

$device->observe_string( \&onStringMessage, undef );

my $steps = [
	[0,1000,5000],
	[1,500,5000],
	[0,1000,5000],
	[1,1500,5000]
];

my $stepperContext = { position => 0, progStep => 0, program => $steps };

$device->observe_stepper(0, \&onStepperMessage, $stepperContext );

#$device->stepper_config(0,'DRIVER',1000,4,5);  #   $stepperNum, $interface, $stepsPerRev, $directionPin, $stepPin,[$motorPin3, $motorPin4] 
#$device->stepper_config(0,'TWO_WIRE',1000,4,5);  #   $stepperNum, $interface, $stepsPerRev, $directionPin, $stepPin,[$motorPin3, $motorPin4] 
$device->stepper_config(0,'FOUR_WIRE',64,8,6,5,7);  #   $stepperNum, $interface, $stepsPerRev, $directionPin, $stepPin,[$motorPin3, $motorPin4] 


nextStep($stepperContext,0);

while (1) {
	$device->poll();
}

sub onStepperMessage {
	my ($stepperNum, $context) = @_;
	
	updatePosition($context);
	
	print "stepper: $stepperNum, $context->{position}\n";
	
	nextStep($context);
}

sub nextStep {
	my ($context, $nextStep) = @_;
	
	my @stepperProgram = @{$context->{program}};
	
	if (!defined $nextStep) {
		my $lastStep = $context->{progStep};
		$nextStep = ($lastStep == scalar(@stepperProgram) - 1) ? 0 : $lastStep + 1;
	}
	
	my @nextProg = @{$stepperProgram[$nextStep]};

	$context->{progStep} = $nextStep;
	$device->stepper_step(0,$nextProg[0],$nextProg[1],$nextProg[2]);
}

sub updatePosition {
	my ($context) = @_;

	my @stepperProgram = @{$context->{program}};
	my $lastStep = $context->{progStep};
	my @lastProg = @{$stepperProgram[$lastStep]};

	if ($lastProg[0] > 0) {
		$context->{position} -= $lastProg[1];
	} else {
		$context->{position} += $lastProg[1];
	}
}

sub onStringMessage {
	my $string = shift;
	print "string: $string\n";
}

1;

