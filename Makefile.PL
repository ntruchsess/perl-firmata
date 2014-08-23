use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Device::Firmata',
    AUTHOR              => q{Norbert Truchsess <ntruchses@cpan.org>, amimato <amimoto>},
    VERSION_FROM        => 'lib/Device/Firmata.pm',
    ABSTRACT_FROM       => 'lib/Device/Firmata.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    MIN_PERL_VERSION    => 5.006,
    CONFIGURE_REQUIRES  => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES      => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Device-Firmata-*' },
);
