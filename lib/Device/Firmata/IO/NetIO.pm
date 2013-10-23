package Device::Firmata::IO::NetIO;

use strict;
use warnings;
use IO::Socket::INET;

use vars qw//;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

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
	
	print "SERVER Waiting for client connection on port $port\n";

	$self->{'socket'} = $socket;
	return $self;
}

sub accept {
	
	my $self = shift;
	# waiting for new client connection.
	my $client_socket = $self->{'socket'}->accept();
	
	return $self->attach($client_socket) if ($client_socket);
	return undef;
}

sub attach {
    my ( $pkg, $client_socket, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

	# get the host and port number of newly connected client.
	my $peer_address = $client_socket->peerhost();
	my $peer_port = $client_socket->peerport();
	print "Attaching new Client Connection From : $peer_address, $peer_port\n ";
	
	my $clientpackage = "Device::Firmata::IO::NetIO::Client";
	eval "require $clientpackage";
	
	my $clientio = $clientpackage->attach($client_socket);
	
    my $package = "Device::Firmata::Platform";
    eval "require $package";
  	my $platform = $package->attach( $clientio, $opts ) or die "Could not connect to Firmata Server";

	# Figure out what platform we're running on
    $platform->probe;

    return $platform;
}

package Device::Firmata::IO::NetIO::Client;

use strict;
use warnings;
use IO::Socket::INET;

use vars qw//;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

sub attach {
    my ( $pkg, $client_socket, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

    $self->{client} = $client_socket;
    
    return $self;
}

=head2 data_write

Dump a bunch of data into the comm port

=cut

sub data_write {
# --------------------------------------------------
    my ( $self, $buf ) = @_;
    $Device::Firmata::DEBUG and print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
    return $self->{client}->write( $buf );
}


=head2 data_read

We fetch up to $bytes from the comm port
This function is non-blocking

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

=head2 close

close the underlying connection

=cut

sub close {
	my $self = shift;
	$self->{client}->close() if (($self->{client}) and $self->{client}->connected());
}

1;
