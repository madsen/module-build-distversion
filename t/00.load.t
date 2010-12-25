#! /usr/bin/perl
#---------------------------------------------------------------------

use Test::More tests => 1;

BEGIN {
    use_ok('Module::Build::DistVersion');
}

diag("Testing Module::Build::DistVersion $Module::Build::DistVersion::VERSION");
