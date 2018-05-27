#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

# No manifest test for normal user install
plan skip_all => "These tests are for authors only, skipping!" unless $ENV{AUTHOR_TESTING} or $ENV{RELEASE_TESTING};

my $min_tcm = 0.9;
eval "use Test::CheckManifest $min_tcm";
plan skip_all => "Test::CheckManifest $min_tcm required" if $@;

ok_manifest();
