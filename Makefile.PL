use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Device::Firmata',
    AUTHOR              => q{amimato <amimoto>, ntruchsess <Norbert Truchsess>},
    VERSION_FROM        => 'lib/Device/Firmata.pm',
    ABSTRACT_FROM       => 'lib/Device/Firmata.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Device-Firmata-*' },
);
