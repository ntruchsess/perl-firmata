#!/bin/bash
#
# @see https://perlmaven.com/creating-makefile-pl-and-a-cpan-distribution-for-the-markua-parser
#
perl Makefile.PL
make
make test
make manifest
rm MANIFEST.bak
make dist
echo
echo "use 'make distclean' to remove build artifacts"
echo
