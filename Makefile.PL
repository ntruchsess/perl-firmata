use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Device::Firmata',
    AUTHOR              => [
        'Aki Mimoto <amimoto@cpan.org>', 
        'Norbert Truchsess <ntruchses@cpan.org>', 
        'Jens B. <jnsbyr@cpan.org>', 
    ],
    VERSION_FROM        => 'lib/Device/Firmata.pm',
    ABSTRACT_FROM       => 'lib/Device/Firmata.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3001? ('LICENSE'=> 'perl_5') : ()),
    ($ExtUtils::MakeMaker::VERSION >= 6.18? ('SIGN'=> '0') : ()),
    PL_FILES            => {},
    MIN_PERL_VERSION    => 5.006,
    BUILD_REQUIRES      => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        ($^O eq 'MSWin32'? ('Win32::SerialPort' => 0) : ('Device::SerialPort' => 0)),
        'IO::Select' => 0,
        'IO::Socket::INET' => 0,
        'Time::HiRes' => 0,
        'strict' => 0,
        'warnings' => 0
    },
    dist                => {
        COMPRESS => 'gzip -9f',
        SUFFIX => 'gz',
    },
    clean               => {
        FILES => 'Device-Firmata-*'
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
         homepage => 'https://github.com/ntruchsess/perl-firmata/',
         resources => {
             repository => {
                 type => 'git',
                 url  => 'https://github.com/ntruchsess/perl-firmata.git',
                 web  => 'https://github.com/ntruchsess/perl-firmata',
             },
         },
    },
);
