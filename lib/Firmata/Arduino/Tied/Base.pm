package Firmata::Arduino::Tied::Base;

use strict 'vars', 'subs';
use vars qw/ 
    $AUTOLOAD 

    $FIRMATA_DEBUG_LEVEL
    $FIRMATA_ERROR_CLASS
    $FIRMATA_ERROR

    $FIRMATA_ATTRIBS 
    $FIRMATA_DEBUGGING 

    $FIRMATA_LOCALE 
    $FIRMATA_LOCALE_PATH
    $FIRMATA_LOCALE_MESSAGES 
/;

$FIRMATA_DEBUGGING = 1;

$FIRMATA_ATTRIBS = {
};
$FIRMATA_LOCALE = 'en';
$FIRMATA_LOCALE_PATH = '.';

$FIRMATA_DEBUG_LEVEL = 0; 
$FIRMATA_ERROR_CLASS = 'Firmata::Arduino::Tied::Error';

sub import {
# --------------------------------------------------
# Ease the use of setting up configuration options
#
    my $self = shift;
    my $pkg  = caller;

    my $config_opts = {
        debugging       => $FIRMATA_DEBUGGING,
    };

    if ( @_ ) {
        my $opts = $self->parameters( @_ );

        if ( my $attrs = $opts->{FIRMATA_ATTRIBS} ) {
            *{$pkg.'::FIRMATA_ATTRIBS'} = \$attrs;
        }

        unless ( ref *{$pkg.'::ISA'} eq 'ARRAY' and @${$pkg.'::ISA'}) {
            my @ISA = ref $opts->{ISA} ? @{$opts->{ISA}} :
                          $opts->{ISA} ? $opts->{ISA} :
                           __PACKAGE__;
            *{$pkg.'::ISA'} = \@ISA;
        }

        use strict;

        $self->SUPER::import( @_ );
    }
}

sub new {
# --------------------------------------------------
    my $pkg = shift;
    my $basis = copy_struct( $pkg->init_class_attribs );
    my $self = bless $basis, $pkg;

    @_ = $self->pre_init( @_ ) if $self->{_biofunc_pre_init};

    if ( $self->{_biofunc_init} ) {
        $self->init( @_ );
    }
    else {
        $self->init_instance_attribs( @_ );
    }

    return $self->post_init if $self->{_biofunc_post_init};
    return $self;
}

sub create {
# --------------------------------------------------
# A soft new as some objects will override new and 
# we don't want to cause problems but still want
# to invoice our creation code
#
    my $self = shift;
    my $basis = copy_struct( $self->init_class_attribs );

    @$self{ keys %$basis } = values %$basis;

    @_ = $self->pre_init( @_ ) if $self->{_biofunc_pre_init};

    if ( $self->{_biofunc_init} ) {
        $self->init( @_ );
    }
    else {
        $self->init_instance_attribs( @_ );
    }

    return $self->post_init if $self->{_biofunc_post_init};
    return $self;
}

sub init_instance_attribs {
# --------------------------------------------------
    my $self = shift;
    my $opts = $self->parameters( @_ );

    foreach my $k ( keys %$self ) {
        next unless exists $opts->{$k};
        next if $k =~ /^_biofunc/;
        $self->{$k} = $opts->{$k};
    }

    return $self;
}

sub init_class_attribs {
# --------------------------------------------------
    my $class       = ref $_[0] || shift;
    my $track       = { $class => 1, @_ ? %{$_[0]} : () };

    return ${"${class}::ABSOLUTE_ATTRIBS"} if ${"${class}::ABSOLUTE_ATTRIBS"};

    my $u = ${"${class}::FIRMATA_ATTRIBS"} || {};

    for my $c ( @{"${class}::ISA"} ) {
        next unless ${"${c}::FIRMATA_ATTRIBS"};

        my $h;
        if ( ${"${c}::ABSOLUTE_ATTRIBS"} ) {
            $h = ${"${c}::ABSOLUTE_ATTRIBS"};
        }
        else {
            $c->fatal( "Cyclic dependancy!" ) if $track->{$c};
            $h = $c->init_class_attribs( $c, $track );
        }

        foreach my $k ( keys %$h ) {
            next if exists $u->{$k};
            $u->{$k} = copy_struct( $h->{$k} );
        }
    }

    foreach my $f ( qw( pre_init init post_init ) ) {
        $u->{"_biofunc_" . $f} = $class->can( $f ) ? 1 : 0;
    }

    ${"${class}::ABSOLUTE_ATTRIBS"} = $u;

    return $u;
}

# logging/exception functions



# Utiilty functions

sub parameters {
# --------------------------------------------------
    return {} unless @_ > 1;

    if ( @_ == 2 ) {
        return $_[1] if ref $_[1];
        return; # something wierd happened
    }

    @_ % 2 or $_[0]->warn( "Even number of elements were not passed to call.", join( " ", caller() )  );

    shift; 

    return {@_};
}

sub copy_struct {
# --------------------------------------------------
    my $s = shift;

    if ( ref $s ) {
        if ( UNIVERSAL::isa( $s, 'HASH' ) ) {
            return {
                map { my $v = $s->{$_}; (
                    $_ => ref $v ? copy_struct( $v ) : $v
                )} keys %$s
            };
        }
        elsif ( UNIVERSAL::isa( $s, 'ARRAY' ) ) {
            return [
                map { ref $_ ? copy_struct($_) : $_ } @$s
            ];
        }
        die "Cannot copy struct! : ".ref($s);
    }

    return $s;
}

sub locale {
# --------------------------------------------------
    @_ >= 2 and shift;
    $FIRMATA_LOCALE = shift;
}

sub locale_path {
# --------------------------------------------------
    @_ >= 2 and shift;
    $FIRMATA_LOCALE_PATH = shift;
}

sub language {
# --------------------------------------------------
    my $self = shift;
    require Firmata::Arduino::Tied::Language;
    return Firmata::Arduino::Tied::Language->language(@_);
}

sub error {
# --------------------------------------------------
# Handle any error messages
#
    my $self = shift;

    if ( @_ ) {
        my $err_msg = $self->init_error->error(@_);
        $self->{error} = $err_msg;
        return;
    }

    my $err_msg = $self->{error};
    $self->{error} = '';
    return $err_msg;
}

sub init_error {
# --------------------------------------------------
# Creates the global error object that will collect
# all error messages generated on the system. This
# function can be called as many times as desired.
#
    $FIRMATA_ERROR and return $FIRMATA_ERROR;

    if ( $FIRMATA_ERROR_CLASS eq 'Firmata::Arduino::Tied::Error' ) {
        require Firmata::Arduino::Tied::Error;
        return $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS;
    }

# Try and load the file. Use default if fails
    eval "require $FIRMATA_ERROR_CLASS";
    $@ and return $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS;

# Try and init the error object. Use default if fails
    eval { $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS->new(); };
    $@ and return $FIRMATA_ERROR = $FIRMATA_ERROR_CLASS;
    return $FIRMATA_ERROR;
}

sub fatal {
# --------------------------------------------------
# Handle tragic and unrecoverable messages
#
    my $self = shift;
    return $self->error( -1, @_ );
}

sub warn {
# --------------------------------------------------
# Handle tragic and unrecoverable messages
#
    my $self = shift;
    return $self->error( 0, @_ );
}

sub debug {
# --------------------------------------------------
    my ( $self, $debug ) = @_;
    $FIRMATA_DEBUG_LEVEL = $debug;
}

sub DESTROY {
# --------------------------------------------------
    my $self = shift;
}

sub AUTOLOAD {
# --------------------------------------------------
    my $self = shift;
    my ($attrib) = $AUTOLOAD =~ /::([^:]+)$/;

    if ( $self and UNIVERSAL::isa( $self, 'Firmata::Arduino::Tied::Base' ) ) {
        $self->error( FIRMATA__unhandled => $attrib, join( " ", caller() ) );
        die $self->error;
    }
    else {
        die "Tried to call function '$attrib' via object '$self' @ ", join( " ", caller(1) ), "\n";
    }

}

####################################################
# Object instantiation code
####################################################

sub object_load {
# --------------------------------------------------
# Load the appropriate package and attempt to initialize
# the object as well
#
    my $self         = shift;
    my $object_class = shift;
    return unless $object_class =~ /^\w+(?:::\w+)*$/; # TODO ERROR MESSAGE
    eval "require $object_class; 1" or die $@;
    my $object      = $object_class->new(@_);
    return $object;
}


1;

