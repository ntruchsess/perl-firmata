package Device::Firmata::IO::NetIO;

=head1 Device::Firmata::IO::NetIO

Implements the low level TCP/IP server socket IO.

=cut

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

use vars qw//;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

=head2 METHODS

=head3 listen ( host, port )

Start a TCP server bound to given local address and port for the Firmata device to connect to. Returns a C<Device::Firmata::IO::NetIO> object. Typically called by method C<listen> of L<Device::Firmata>. An implementation example can be found in file F<examples/example-tcpserver.pl>.

=cut

sub listen {
# --------------------------------------------------
    my ( $pkg, $ip, $port, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

	# flush after every write
	$| = 1;

	my $socket;

	# creating object interface of IO::Socket::INET modules which internally does
	# socket creation, binding and listening at the specified port address.
	$socket = new IO::Socket::INET (
	LocalHost => $ip,
	LocalPort => $port,
	Proto => 'tcp',
	Listen => 5,
	Reuse => 1
	) or die "ERROR in Socket Creation : $!\n";

	$self->{'socket'} = $socket;
	return $self;
}

=head3 accept ( timeout )

Wait until timeout seconds for an Firmata device to connect. Returns a L<Device::Firmata::Platform> object on success or C<undef>. An implementation example can be found in file F<examples/example-tcpserver.pl>.

=cut

sub accept {

	my ($self,$timeout) = @_;
	# waiting for new client connection.
	my $s = $self->{'select'};
	if (!($s)) {
		$s = IO::Select->new();
		$s->add($self->{'socket'});
		$self->{'select'} = $s;
	}
	if(my @ready = $s->can_read($timeout)) {
		my $socket = $self->{'socket'};
		foreach my $fh (@ready) {
			if ($fh == $socket) {
				if (my $client_socket = $socket->accept()) {
					return $self->attach($client_socket);
				}
			}
		}
	}
	return undef;
}

=head3 close ( )

Closes the TCP server socket and disconnects all Firmata devices. An implementation example can be found in file F<examples/example-tcpserver.pl>.

=cut

sub close {
	my $self = shift;
	if ($self->{'select'} && $self->{'socket'}) {
		$self->{'select'}->remove($self->{'socket'});
		delete $self->{'select'};
	}
	if ($self->{'socket'}) {
		$self->{'socket'}->close();
		delete $self->{'socket'};
	}
	if ($self->{clients}) {
		foreach my $client (@{$self->{clients}}) {
			$client->close();
		}
		delete $self->{clients};
	}
}

=head3 attach ( connectedSocket )

Assign a connected L<IO::Socket::INET> as IO port and return a L<Device::Firmata::Platform> object. Typically used internally by the C<accept()> method.

=cut

sub attach {
  my ( $pkg, $client_socket, $opts ) = @_;

  my $self = ref $pkg ? $pkg : $pkg->new($opts);

	my $clientpackage = "Device::Firmata::IO::NetIO::Client";
	eval "require $clientpackage";

	my $clientio = $clientpackage->attach($client_socket);

  my $package = "Device::Firmata::Platform";
  eval "require $package";
  my $platform = $package->attach( $clientio, $opts ) or die "Could not connect to Firmata Server";

	my $s = $self->{'select'};
	if (!($s)) {
		$s = IO::Select->new();
		$self->{'select'} = $s;
	}
	$s->add($client_socket);
	my $clients = $self->{clients};
	if (!($clients)) {
		$clients = [];
		$self->{clients} = $clients;
	}
	push @$clients, $platform;

	# Figure out what platform we're running on
  $platform->probe();

  return $platform;
}

=head3 poll ( timeout )

Wait for timeout seconds for data from Firmata devices. If data is received the method C<poll> of L<Device::Firmata::Platform> will be called for processing. An implementation example can be found in file F<examples/example-tcpserver.pl>.

=cut

sub poll {
	my ($self,$timeout) = @_;
	my $s = $self->{'select'};
	return unless $s;
	if(my @ready = $s->can_read($timeout)) {
		my $socket = $self->{'socket'};
		my $clients = $self->{clients};
		if (! defined($clients)) {
			$clients = [];
			$self->{clients} = $clients;
		}
		my @readyclients = ();
		foreach my $fh (@ready) {
			if ($fh != $socket) {
				push @readyclients, grep { $fh == $_->{io}->{client}; } @$clients;
			}
		}
		foreach my $readyclient (@readyclients) {
			$readyclient->poll();
		}
	}
}

package Device::Firmata::IO::NetIO::Client;

=head1 Device::Firmata::IO::NetIO::Client

Implements the low level TCP/IP client socket IO.

=cut

use strict;
use warnings;
use IO::Socket::INET;

use vars qw//;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

=head2 METHODS

=head3 attach ( connectedSocket )

Assign a connected L<IO::Socket::INET> as IO port and return a C<Device::Firmata::IO::NetIO::Client> object. Typically used internally by the C<attach()> method of L<Device::Firmata::IO::NetIO>.

=cut

sub attach {
  my ( $pkg, $client_socket, $opts ) = @_;

  my $self = ref $pkg ? $pkg : $pkg->new($opts);

  $self->{client} = $client_socket;

  return $self;
}

=head3 data_write ( buffer )

Send a bunch of data to the Firmata device. Typically used internally by L<Device::Firmata::Platform>.

=cut

sub data_write {
# --------------------------------------------------
  my ( $self, $buf ) = @_;
  $Device::Firmata::DEBUG and print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
  return $self->{client}->write( $buf );
}


=head3 data_read ( bytes )

Fetch up to given number of bytes from the client socket. This function is non-blocking. Returns the received data. Typically used internally by L<Device::Firmata::Platform>.

=cut

sub data_read {
# --------------------------------------------------
  my ( $self, $bytes ) = @_;
	my ($buf, $res);
	$res = $self->{client}->sysread($buf, 512);
  $buf = "" if(!defined($res));

  if ( $Device::Firmata::DEBUG and $buf ) {
    print "<".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
  }
  return $buf;
}

=head3 close

Close the TCP client socket to the Firmata device. The listening socket will not be affected. Typically used internally by L<Device::Firmata::Platform> and C<Device::Firmata::IO::NetIO>.

=cut

sub close {
	my $self = shift;
	$self->{client}->close() if (($self->{client}) and $self->{client}->connected());
}

=head1 SEE ALSO

L<Device::Firmata::Base>

=cut

1;
