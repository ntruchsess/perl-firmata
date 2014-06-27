#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Device::Firmata::Platform;
use Device::Firmata::Protocol;

package Firmata_IO;

sub new {
  my ($class) = @_;
  return bless {
    data => [],
  }, $class;
}

sub data_write {
  my ( $self, $buf ) = @_;
  my $hash = $self->{hash};
  print "> ".(defined $buf ? unpack "H*",$buf : "--")."\n";
}

sub data_read {
  my ( $self, $bytes ) = @_;
  my $data = shift @{$self->{data}};
  print "< ".(defined $data ? unpack "H*",$data : "--")."\n";
  return $data;
}

sub append_raw {
  my ( $self, $data ) = @_;
  push @{$self->{data}},$data;
}

sub append {
  my ( $self, $hexdata ) = @_;
  $self->append_raw(pack "H*",$hexdata);
}

sub append_asbytes {
  my ( $self, $hexdata ) = @_;
  foreach my $byte (unpack "C*",(pack "H*",$hexdata)) {
    $self->append_raw(pack "C",$byte);
  }
}

package main;

my $io = Firmata_IO->new();
my $firmata = Device::Firmata::Platform->attach($io);

$io->append("f90206");
$io->append("f079020654006500730074004600690072006d00610074006100f7");
$io->append("f06c077ff7");
$io->append("f06a7ff7");

$firmata->probe;

print "firmware:         ".(defined ($firmata->{metadata}{firmware}) ? $firmata->{metadata}{firmware} : "--")."\n";
print "firmware_version: ".(defined ($firmata->{metadata}{firmware_version}) ? $firmata->{metadata}{firmware_version} : "--")."\n";
print "protocol_version: ".(defined ($firmata->{protocol}->{protocol_version}) ? $firmata->{protocol}->{protocol_version} : "--")."\n";
print "capabilities:     ";
if (defined ($firmata->{metadata}{capabilities})) {
  foreach my $pin (sort keys %{$firmata->{metadata}{capabilities}}) {
    print $pin."->".(join (",",sort keys %{$firmata->{metadata}{capabilities}->{$pin}}))." ";
  }
  print "\n";
} else {
  print " --\n";
}
print "analog_mappings:  ";
if (defined ($firmata->{metadata}{analog_mappings})) {
  foreach my $pin (sort keys %{$firmata->{metadata}{analog_mappings}}) {
    print $pin."->".$firmata->{metadata}{analog_mappings}->{$pin}." ";
  }
  print "\n";
} else {
  print " --\n";
}

$firmata->pin_mode(0,7);
$firmata->onewire_config(0,0);
$firmata->observe_onewire(0,sub {
  print Dumper(\@_);
  return undef;
},"context");

$io->append("f07343007f0104103000410200f7");

$firmata->poll;

$io->append_asbytes("f07343007f0104103000410200f7");

$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;

$io->append("f0");
$io->append("73");
$io->append("43");
$io->append("00");
$io->append("00");
$io->append("02");
$io->append("04");
$io->append("10");
$io->append("30");
$io->append("00");
$io->append("41");
$io->append("02");
$io->append("00");
$io->append("f7");

$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;
$firmata->poll;

1;
